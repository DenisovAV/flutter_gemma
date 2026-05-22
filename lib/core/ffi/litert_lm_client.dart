import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../flutter_gemma_interface.dart';
import 'litert_lm_bindings.dart';

/// Callback typedef with Uint8 for bool (C _Bool = 1 byte)
typedef _StreamCallbackNative = Void Function(Pointer<Void> callbackData,
    Pointer<Char> chunk, Uint8 isFinal, Pointer<Char> errorMsg);

/// stream_proxy_create: creates a proxy that strdup's strings before
/// forwarding to the Dart callback (prevents use-after-free).
typedef _ProxyCreateNative = Pointer<Void> Function(
    Pointer<NativeFunction<_StreamCallbackNative>> dartCallback,
    Pointer<Void> dartData,
    Pointer<Pointer<NativeFunction<_StreamCallbackNative>>> outProxyFn);
typedef _ProxyCreateDart = Pointer<Void> Function(
    Pointer<NativeFunction<_StreamCallbackNative>> dartCallback,
    Pointer<Void> dartData,
    Pointer<Pointer<NativeFunction<_StreamCallbackNative>>> outProxyFn);

/// Free a strdup'd string from the proxy callback.
typedef _ProxyFreeStringNative = Void Function(Pointer<Char> str);
typedef _ProxyFreeStringDart = void Function(Pointer<Char> str);

/// High-level Dart wrapper around the LiteRT-LM C API.
///
/// Provides a clean async interface over the native C functions,
/// managing memory and translating C callbacks into Dart Streams.
class LiteRtLmFfiClient {
  LiteRtLmBindings? _bindings;
  // Holding a reference prevents the proxy DynamicLibrary from being GC'd
  // while function pointers obtained via lookupFunction are still in use.
  // ignore: unused_field
  DynamicLibrary? _proxyLib;
  _ProxyCreateDart? _proxyCreate;
  _ProxyFreeStringDart? _proxyFreeString;
  Pointer<LiteRtLmEngine>? _engine;
  Pointer<LiteRtLmConversation>? _conversation;
  bool _isInitialized = false;
  String? _nativeLogPath;
  String? _backend;

  /// Reads back the native log file (set by stream_proxy_redirect_stderr) and
  /// pipes its contents through debugPrint in 800-char chunks. Surfaces
  /// absl/glog output (model load timing, accelerator init, sampler dlopen,
  /// KV-cache prefill, etc.) that's redirected to a file by
  /// [stream_proxy_redirect_stderr] and wouldn't otherwise reach the Flutter
  /// console / test harness.
  ///
  /// Called automatically after every successful and failed engine_create
  /// (debug builds only) so timing breakdowns are visible in `flutter run`.
  /// Also exposed publicly via [dumpNativeLog] for callers that want to dump
  /// at arbitrary points (e.g. after prefill, after a slow generate).
  ///
  /// Truncates the log file after reading so subsequent dumps only show new
  /// output — otherwise every dump would re-print everything since app start.
  void dumpNativeLog() => _dumpNativeLog();

  void _dumpNativeLog() {
    final p = _nativeLogPath;
    if (p == null) return;
    try {
      final f = File(p);
      if (!f.existsSync()) {
        debugPrint('[LiteRtLmFfi/native] log file missing: $p');
        return;
      }
      final content = f.readAsStringSync();
      if (content.isEmpty) {
        debugPrint('[LiteRtLmFfi/native] (no new native log output)');
        return;
      }
      debugPrint(
          '[LiteRtLmFfi/native] === BEGIN native log ($p, ${content.length} bytes) ===');
      const chunkSize = 800;
      for (var i = 0; i < content.length; i += chunkSize) {
        final end =
            (i + chunkSize < content.length) ? i + chunkSize : content.length;
        debugPrint(content.substring(i, end));
      }
      debugPrint('[LiteRtLmFfi/native] === END native log ===');
      // Truncate so the next dump only shows new output. If truncation fails
      // (read-only fs etc.), next dump just re-prints — non-fatal.
      try {
        f.writeAsStringSync('');
      } catch (_) {}
    } catch (e) {
      debugPrint('[LiteRtLmFfi/native] failed to read $p: $e');
    }
  }

  bool get isInitialized => _isInitialized;

  /// Path to the redirected native stderr log (LiteRT-LM absl/glog output).
  /// Set after [_ensureBindings] runs the stderr redirect; null on platforms
  /// where redirection isn't wired (currently it works on macOS + iOS).
  String? get nativeLogPath => _nativeLogPath;

  /// Load the native library and create bindings.
  void _ensureBindings() {
    if (_bindings != null) return;

    final loadSw = Stopwatch()..start();
    debugPrint('[LiteRtLmFfi] Loading native libraries...');
    final DynamicLibrary lib;
    final DynamicLibrary proxyLib;
    if (Platform.isIOS) {
      // On iOS, Native Assets bundles dylibs in Frameworks/ inside Runner.app.
      // The host app's Xcode project must also copy raw lib*.dylib files
      // alongside the .framework bundles (see "Setup LiteRT-LM iOS" build
      // phase in example/ios/Runner.xcodeproj/project.pbxproj) — needed
      // because gpu_registry.cc uses relative-basename dlopen which iOS
      // dyld 4 cannot resolve from .framework names alone.
      lib = DynamicLibrary.open(
          '@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm');
      proxyLib = DynamicLibrary.open(
          '@executable_path/Frameworks/StreamProxy.framework/StreamProxy');
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('LiteRtLm.framework/LiteRtLm');
      proxyLib = DynamicLibrary.open('StreamProxy.framework/StreamProxy');
    } else if (Platform.isLinux) {
      // Load order matters: libLiteRt.so must be loaded first with
      // RTLD_GLOBAL so libLiteRtLm.so (built with litert_link_capi_so=true)
      // and the WebGPU accelerator can resolve LiteRt* C API symbols
      // against it. StreamProxy exposes a dlopen helper because Dart's
      // DynamicLibrary.open uses RTLD_LOCAL which hides symbols.
      //
      // Native Assets places .so files in <bundle>/lib/. Dart's
      // DynamicLibrary.open finds them by basename via Flutter-set RPATH,
      // but a raw C dlopen via stream_proxy_load_global doesn't see that
      // path — pass an absolute path so it resolves regardless of
      // LD_LIBRARY_PATH / RPATH inheritance.
      final libDir = '${File(Platform.resolvedExecutable).parent.path}/lib';
      proxyLib = DynamicLibrary.open('libStreamProxy.so');
      final loadGlobal = proxyLib.lookupFunction<
          Pointer Function(Pointer<Utf8>),
          Pointer Function(Pointer<Utf8>)>('stream_proxy_load_global');
      // Preload sequence:
      // - libLiteRt.so first (provides LiteRt C API used by the WebGPU
      //   accelerator at registration)
      // - libGemmaModelConstraintProvider.so (libLiteRtLm.so has a
      //   SONAME-level dependency on it)
      // - libLiteRtWebGpuAccelerator.so so gpu_registry.cc:162 can find it
      //   via the loader's already-loaded modules table when it does
      //   basename-only dlopen
      // - libLiteRtLm.so itself
      //
      // libLiteRtTopKWebGpuSampler.so is intentionally NOT preloaded:
      // its Create() holds a process-static wgpu::Instance and rejects
      // any second engine_create with `wgpu::Instance already set`,
      // making model swap and multi-session tests impossible. With the
      // sampler not preloaded, sampler_factory.cc:443's dlopen returns
      // Unavailable and the factory falls back to the static / CPU
      // sampler chain — inference itself still runs on the GPU
      // accelerator, only the per-token argmax happens on CPU
      // (negligible perf hit, ~1-5ms/token).
      for (final name in const [
        'libLiteRt.so',
        'libGemmaModelConstraintProvider.so',
        'libLiteRtWebGpuAccelerator.so',
        'libLiteRtLm.so',
      ]) {
        final fullPath = '$libDir/$name';
        final pathPtr = fullPath.toNativeUtf8();
        final handle = loadGlobal(pathPtr);
        calloc.free(pathPtr);
        if (handle == nullptr) {
          throw Exception('Failed to load $fullPath with RTLD_GLOBAL');
        }
      }
      lib = DynamicLibrary.open('libLiteRtLm.so');
    } else if (Platform.isWindows) {
      // Preload LiteRt.dll first so the WebGPU accelerator and TopK sampler
      // can resolve LiteRt* C API + their own exports through the process
      // module list before sampler_factory does its LoadLibrary lookup
      // (mirrors the Linux/Android RTLD_GLOBAL pattern).
      proxyLib = DynamicLibrary.open('StreamProxy.dll');
      final loadGlobal = proxyLib.lookupFunction<
          Pointer Function(Pointer<Utf8>),
          Pointer Function(Pointer<Utf8>)>('stream_proxy_load_global');
      for (final name in const [
        'LiteRt.dll',
        'libLiteRtTopKWebGpuSampler.dll',
        'libLiteRtWebGpuAccelerator.dll',
        'LiteRtLm.dll',
      ]) {
        final pathPtr = name.toNativeUtf8();
        final handle = loadGlobal(pathPtr);
        calloc.free(pathPtr);
        if (handle == nullptr) {
          throw Exception('Failed to preload $name (LoadLibraryEx)');
        }
      }
      lib = DynamicLibrary.open('LiteRtLm.dll');
    } else if (Platform.isAndroid) {
      // LiteRT-LM ships native libs only for android_arm64 — bail with a
      // typed message before dlopen surfaces a generic ENOENT on x86_64
      // emulators / armeabi-v7a devices (#250). MediaPipe `.task` text
      // inference still works on those ABIs through the Kotlin path; only
      // `.litertlm` (FFI) requires arm64.
      if (Abi.current() != Abi.androidArm64) {
        throw UnsupportedError(
          'flutter_gemma .litertlm models require an arm64-v8a Android device '
          '(got ${Abi.current()}). Use a `.task` MediaPipe model on this ABI '
          'or run on an arm64-v8a device / Apple Silicon emulator.',
        );
      }
      // Load StreamProxy first (it has stream_proxy_load_global helper)
      proxyLib = DynamicLibrary.open('libStreamProxy.so');
      // Load LiteRtLm with RTLD_GLOBAL so GPU accelerator plugins
      // can find LiteRt* symbols via dlsym(RTLD_DEFAULT).
      // Dart's DynamicLibrary.open uses RTLD_LOCAL which hides symbols.
      final loadGlobal = proxyLib.lookupFunction<
          Pointer Function(Pointer<Utf8>),
          Pointer Function(Pointer<Utf8>)>('stream_proxy_load_global');
      final pathPtr = 'libLiteRtLm.so'.toNativeUtf8();
      final handle = loadGlobal(pathPtr);
      calloc.free(pathPtr);
      if (handle == nullptr) {
        throw Exception('Failed to load libLiteRtLm.so with RTLD_GLOBAL');
      }
      lib = DynamicLibrary.open('libLiteRtLm.so'); // Now symbols are global
    } else {
      throw UnsupportedError(
          'Platform not supported for FFI: ${Platform.operatingSystem}');
    }

    _bindings = LiteRtLmBindings(lib);
    _proxyLib = proxyLib;
    _proxyCreate =
        proxyLib.lookupFunction<_ProxyCreateNative, _ProxyCreateDart>(
            'stream_proxy_create');
    _proxyFreeString =
        proxyLib.lookupFunction<_ProxyFreeStringNative, _ProxyFreeStringDart>(
            'stream_proxy_free_string');

    // DEBUG-only: redirect native stderr to a file so we can dump absl/glog
    // output through debugPrint after engine_create failure. Skipped in
    // release builds — production users see crashes via os_log/Crashlytics
    // streams (or systemd journal on Linux); redirecting stderr would
    // silently swallow those.
    //
    // Linux: flutter test does not surface child-process stderr, so without
    // this Linux integration tests get the same opaque 'Failed to create
    // engine' as iOS without any native diagnostics.
    if (kDebugMode &&
        (Platform.isIOS || Platform.isLinux || Platform.isMacOS)) {
      _nativeLogPath = '${Directory.systemTemp.path}/litertlm_native.log';
      final redirect = proxyLib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('stream_proxy_redirect_stderr');
      final pathPtr = _nativeLogPath!.toNativeUtf8();
      final rc = redirect(pathPtr);
      calloc.free(pathPtr);
      if (rc != 0) {
        // Log capture is best-effort but its failure makes _dumpNativeLog
        // useless. Surface it instead of silently continuing.
        debugPrint('[LiteRtLmFfi] WARNING: stderr redirect failed (rc=$rc) — '
            'native log dumps will be empty');
        _nativeLogPath = null;
      } else {
        debugPrint('[LiteRtLmFfi] stderr redirected to $_nativeLogPath');
      }
    }

    debugPrint(
        '[LiteRtLmFfi/perf] _ensureBindings total: ${loadSw.elapsedMilliseconds}ms');
    debugPrint('[LiteRtLmFfi] Libraries loaded');
  }

  /// Initialize the engine with model path and settings.
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    int maxTokens = 2048,
    String? cacheDir,
    bool enableVision = false,
    int maxNumImages = 0,
    bool enableAudio = false,
    bool? enableSpeculativeDecoding,
  }) async {
    final initSw = Stopwatch()..start();
    _ensureBindings();
    _backend = backend;
    final bindingsMs = initSw.elapsedMilliseconds;
    debugPrint('[LiteRtLmFfi/perf] _ensureBindings: ${bindingsMs}ms');
    final b = _bindings!;

    // Create engine settings
    final modelPathPtr = modelPath.toNativeUtf8();
    final backendPtr = backend.toNativeUtf8();
    final visionBackendPtr = enableVision ? backend.toNativeUtf8() : nullptr;
    final audioBackendPtr = enableAudio ? 'cpu'.toNativeUtf8() : nullptr;

    try {
      final settingsCreateStart = initSw.elapsedMilliseconds;
      final settings = b.litert_lm_engine_settings_create(
        modelPathPtr.cast(),
        backendPtr.cast(),
        visionBackendPtr == nullptr ? nullptr : visionBackendPtr.cast(),
        audioBackendPtr == nullptr ? nullptr : audioBackendPtr.cast(),
      );
      debugPrint(
          '[LiteRtLmFfi/perf] settings_create: ${initSw.elapsedMilliseconds - settingsCreateStart}ms');

      if (settings == nullptr) {
        throw Exception('Failed to create engine settings');
      }

      // Configure settings
      b.litert_lm_engine_settings_set_max_num_tokens(settings, maxTokens);

      // Enable benchmarking for session metrics (token counts, timing)
      b.litert_lm_engine_settings_enable_benchmark(settings);

      if (cacheDir != null) {
        final cacheDirPtr = cacheDir.toNativeUtf8();
        // Sets cache dir on main, vision, and audio executors (C API patched)
        b.litert_lm_engine_settings_set_cache_dir(settings, cacheDirPtr.cast());
        calloc.free(cacheDirPtr);
      }

      if (maxNumImages > 0) {
        b.litert_lm_engine_settings_set_max_num_images(settings, maxNumImages);
      }

      // MTP / speculative decoding (LiteRT-LM v0.11.0+). Skip when null so
      // the SDK uses the model's default; only call when caller explicitly
      // forces on/off.
      if (enableSpeculativeDecoding != null) {
        b.litert_lm_engine_settings_set_enable_speculative_decoding(
            settings, enableSpeculativeDecoding);
      }

      // Windows NPU: point LiteRT at the directory containing
      // `LiteRtDispatch.dll` and disable HW mask update path. Native Assets
      // bundles both DLLs next to the executable, so resolvedExecutable.parent
      // is the right path. Without `dispatch_lib_dir` LiteRT reads
      // uninitialized env-option memory and engine_create crashes; without
      // `use_hw_masking_for_npu(false)` LiteRT sets up the kWH HW mask method
      // which Intel preview NPU (LunarLake/PantherLake) doesn't fully support
      // → CFG check failure 0xc0000409 (per Matt Kreileder's Intel NPU
      // pipeline instructions).
      if (Platform.isWindows && backend == 'npu') {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final dirPtr = exeDir.toNativeUtf8();
        b.litert_lm_engine_settings_set_litert_dispatch_lib_dir(
            settings, dirPtr.cast());
        calloc.free(dirPtr);
        b.litert_lm_engine_settings_set_use_hw_masking_for_npu(settings, false);
        debugPrint(
            '[LiteRtLmFfi] NPU Windows: dispatch_lib_dir=$exeDir, use_hw_masking_for_npu=false');
      }

      // Create engine in a background isolate to avoid blocking UI.
      // Pass settings pointer as int address (Pointer can't cross isolates).
      debugPrint(
          '[LiteRtLmFfi] Creating engine from $modelPath (backend=$backend, maxTokens=$maxTokens) ...');
      debugPrint(
          '[LiteRtLmFfi/perf] === START litert_lm_engine_create (native — model load + accelerator init + KV cache prefill) ===');
      final settingsAddr = settings.address;
      final sw = Stopwatch()..start();
      final engineAddr = await Isolate.run(() {
        final isolateSw = Stopwatch()..start();
        final lib = Platform.isIOS
            ? DynamicLibrary.open(
                '@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm')
            : Platform.isMacOS
                ? DynamicLibrary.open('LiteRtLm.framework/LiteRtLm')
                : (Platform.isLinux || Platform.isAndroid)
                    ? DynamicLibrary.open('libLiteRtLm.so')
                    : DynamicLibrary.open('LiteRtLm.dll');
        // ignore: avoid_print
        print(
            '[LiteRtLmFfi/perf]   isolate: DynamicLibrary.open: ${isolateSw.elapsedMilliseconds}ms');
        final lookupStart = isolateSw.elapsedMilliseconds;
        final create = lib.lookupFunction<Pointer Function(Pointer),
            Pointer Function(Pointer)>('litert_lm_engine_create');
        // ignore: avoid_print
        print(
            '[LiteRtLmFfi/perf]   isolate: lookupFunction: ${isolateSw.elapsedMilliseconds - lookupStart}ms');
        final createStart = isolateSw.elapsedMilliseconds;
        final ptr = create(Pointer.fromAddress(settingsAddr)).address;
        // ignore: avoid_print
        print(
            '[LiteRtLmFfi/perf]   isolate: native litert_lm_engine_create: ${isolateSw.elapsedMilliseconds - createStart}ms');
        return ptr;
      });
      _engine = Pointer<LiteRtLmEngine>.fromAddress(engineAddr);
      sw.stop();
      debugPrint(
          '[LiteRtLmFfi/perf] === END litert_lm_engine_create: ${sw.elapsedMilliseconds}ms (includes isolate spawn ~50-200ms) ===');
      debugPrint(
          '[LiteRtLmFfi] litert_lm_engine_create took ${sw.elapsedMilliseconds}ms');
      b.litert_lm_engine_settings_delete(settings);

      if (_engine == null || _engine == nullptr) {
        _dumpNativeLog();
        throw Exception(
            'Failed to create engine. Model may be invalid: $modelPath');
      }

      _isInitialized = true;
      debugPrint(
          '[LiteRtLmFfi/perf] initialize() total: ${initSw.elapsedMilliseconds}ms');
      debugPrint('[LiteRtLmFfi] Engine initialized successfully');

      // Auto-dump the SDK's stderr log after successful engine_create so
      // users can see what happens inside the native call (model load time,
      // accelerator init, sampler dlopen attempts, KV cache prefill, etc.).
      // No-op when stderr redirection isn't wired (release / Android /
      // Windows). Safe to call before _isInitialized was true since the
      // dump only reads a file, doesn't touch native state.
      _dumpNativeLog();
    } finally {
      calloc.free(modelPathPtr);
      calloc.free(backendPtr);
      if (visionBackendPtr != nullptr) calloc.free(visionBackendPtr);
      if (audioBackendPtr != nullptr) calloc.free(audioBackendPtr);
    }
  }

  /// Create a new conversation with optional system message and tools.
  void createConversation({
    String? systemMessage,
    String? toolsJson,
    double temperature = 0.8,
    int topK = 40,
    double? topP,
    int seed = 1,
  }) {
    _assertInitialized();
    final b = _bindings!;

    // Close existing conversation if any
    if (_conversation != null && _conversation != nullptr) {
      b.litert_lm_conversation_delete(_conversation!);
      _conversation = null;
    }

    // Always build a sessionConfig with the caller's sampler params — even
    // when there's no systemMessage/tools. Otherwise temperature, topK,
    // topP, and seed get silently dropped on the floor and the model
    // falls back to its baked-in defaults (typically greedy), making
    // every call ignore stochastic decoding requests.
    //
    // This requires a patched libLiteRtLm.{so,dylib,dll} where
    // litert_lm_conversation_config_create accepts the 6-arg overload
    // and applies session_config via the upstream setter chain. See
    // native/litert_lm/patch_c_api.sh ("PATCH: 6-arg overload").
    final sessionConfig = b.litert_lm_session_config_create();

    // NPU executor on LiteRT-LM only supports internal greedy sampling — any
    // sampler params we pass cause engine_create / generation failures
    // upstream. Skip the setter chain in that case; CPU/GPU paths are
    // unaffected.
    if (_backend != 'npu') {
      final samplerParams = calloc<LiteRtLmSamplerParams>();
      // Upstream LiteRT-LM (commit 5e0d86b) only implements TopP sampling at
      // engine level — sampler type 1 (TopK) and 3 (Greedy) are rejected with
      // "UNIMPLEMENTED: Sampler type: N not implemented yet." Use TopP (=2)
      // unconditionally and pass top_k as a hint; native respects both fields
      // even though it's gated by the type tag.
      samplerParams.ref.typeAsInt = 2; // always TopP
      samplerParams.ref.top_k = topK;
      samplerParams.ref.top_p = topP ?? 0.95;
      samplerParams.ref.temperature = temperature;
      samplerParams.ref.seed = seed;
      b.litert_lm_session_config_set_sampler_params(
          sessionConfig, samplerParams);
      calloc.free(samplerParams);
    } else {
      debugPrint('[LiteRtLmFfi] NPU backend — sampler params '
          '(temperature, topK, topP, seed) ignored, engine uses '
          'internal greedy sampling.');
    }

    final systemPtr = systemMessage?.toNativeUtf8();
    final toolsPtr = toolsJson?.toNativeUtf8();

    final Pointer<LiteRtLmConversationConfig> convConfig =
        b.litert_lm_conversation_config_create(
      _engine!,
      sessionConfig,
      systemPtr?.cast() ?? nullptr,
      toolsPtr?.cast() ?? nullptr,
      nullptr,
      toolsJson != null,
    );

    b.litert_lm_session_config_delete(sessionConfig);
    if (systemPtr != null) calloc.free(systemPtr);
    if (toolsPtr != null) calloc.free(toolsPtr);

    if (convConfig == nullptr) {
      throw Exception(
        'litert_lm_conversation_config_create returned null '
        '(systemMessage=${systemMessage != null}, tools=${toolsJson != null}, '
        'temperature=$temperature, topK=$topK, topP=$topP)',
      );
    }

    _conversation = b.litert_lm_conversation_create(_engine!, convConfig);

    b.litert_lm_conversation_config_delete(convConfig);

    if (_conversation == null || _conversation == nullptr) {
      _dumpNativeLog();
      throw Exception('Failed to create conversation');
    }

    debugPrint('[LiteRtLmFfi] Conversation created');
  }

  /// Build the JSON message for the Conversation API.
  ///
  /// Format: `{"role": "user", "content": [{"type": "text", "text": "..."}]}`
  /// Supports multiple images via `imagesBytes` list.
  static String buildMessageJson(
    String text, {
    List<Uint8List>? imagesBytes,
    Uint8List? audioBytes,
  }) {
    final content = <Map<String, dynamic>>[];
    if (imagesBytes != null) {
      for (final imageBytes in imagesBytes) {
        content.add({'type': 'image', 'blob': base64Encode(imageBytes)});
      }
    }
    if (audioBytes != null) {
      content.add({
        'type': 'audio',
        'blob': base64Encode(audioBytes),
      });
    }
    content.add({'type': 'text', 'text': text});
    return jsonEncode({'role': 'user', 'content': content});
  }

  /// Extract text from a LiteRT-LM JSON response chunk.
  ///
  /// Handles two response formats:
  /// - Text: `{"role":"assistant","content":[{"type":"text","text":"hello"}]}`
  ///   → returns `"hello"`
  /// - Thinking: `{"role":"assistant","channels":{"thought":"reasoning..."}}`
  ///   → returns `<|channel>thought\nreasoning...<channel|>`
  ///   (compatible with ThinkingFilter in extensions.dart)
  static String extractTextFromResponse(String jsonStr) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonStr) as Map<String, dynamic>;
    } on FormatException {
      // Partial / non-JSON chunks pass through verbatim. This is the only
      // shape we want to be permissive about — any other parse error
      // (TypeError, RangeError, etc.) signals a real contract change with
      // LiteRT-LM and must surface, not be silently swallowed.
      return jsonStr;
    }

    // Check for thinking channels first
    final channels = json['channels'] as Map<String, dynamic>?;
    if (channels != null) {
      final thought = channels['thought'] as String?;
      if (thought != null && thought.isNotEmpty) {
        return '<|channel>thought\n$thought<channel|>';
      }
    }

    // Regular text content
    final content = json['content'] as List<dynamic>?;
    if (content == null) return jsonStr;
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map<String, dynamic> && item['type'] == 'text') {
        buffer.write(item['text'] as String? ?? '');
      }
    }
    return buffer.toString();
  }

  /// Send a message and get streaming response as plain text chunks.
  /// Supports multiple images via `imageBytes` list.
  Stream<String> chat(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    final messageJson = buildMessageJson(
      text,
      imagesBytes: imageBytes,
      audioBytes: audioBytes,
    );
    final extraContext = enableThinking ? '{"enable_thinking": true}' : null;
    return sendMessageStreamRaw(messageJson, extraContext: extraContext)
        .map(extractTextFromResponse);
  }

  /// Same as [chat] but yields raw SDK JSON chunks without `extractTextFromResponse`
  /// mapping. Required by Gemma 4 path so callers can read the structured
  /// `tool_calls` field via [extractToolCalls].
  Stream<String> chatRaw(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    final messageJson =
        buildMessageJson(text, imagesBytes: imageBytes, audioBytes: audioBytes);
    final extraContext = enableThinking ? '{"enable_thinking": true}' : null;
    return sendMessageStreamRaw(messageJson, extraContext: extraContext);
  }

  /// Send a raw JSON message and get streaming response.
  Stream<String> sendMessageStreamRaw(String messageJson,
      {String? extraContext}) {
    _assertInitialized();
    _assertConversation();
    final b = _bindings!;

    final controller = StreamController<String>();

    final messagePtr = messageJson.toNativeUtf8();
    final extraPtr =
        extraContext != null ? extraContext.toNativeUtf8() : nullptr;

    // NativeCallable.listener is thread-safe — the callback can be
    // invoked from the native background thread that LiteRT-LM uses
    // for streaming, and Dart will marshal it to the right isolate.
    // Dart callback — receives heap-copied strings from proxy
    late final NativeCallable<_StreamCallbackNative> callable;
    callable = NativeCallable<_StreamCallbackNative>.listener(
      (Pointer<Void> data, Pointer<Char> chunk, int isFinal,
          Pointer<Char> errorMsg) {
        if (errorMsg != nullptr && errorMsg.address != 0) {
          final error = errorMsg.cast<Utf8>().toDartString();
          _proxyFreeString!(errorMsg); // free strdup'd string
          // stopGeneration() (and any other caller-initiated cancel) surfaces
          // here as a CANCELLED error from native. That's not an error from
          // the API consumer's perspective — the stream just stops cleanly
          // at whatever token was last delivered.
          if (error.startsWith('CANCELLED')) {
            controller.close();
          } else {
            controller.addError(Exception('Stream error: $error'));
            controller.close();
          }
          callable.close();
          calloc.free(messagePtr);
          if (extraPtr != nullptr) calloc.free(extraPtr);
          return;
        }

        if (chunk != nullptr && chunk.address != 0) {
          final text = chunk.cast<Utf8>().toDartString();
          _proxyFreeString!(chunk); // free strdup'd string
          if (text.isNotEmpty) {
            controller.add(text);
          }
        }

        if (isFinal != 0) {
          controller.close();
          callable.close();
          calloc.free(messagePtr);
          if (extraPtr != nullptr) calloc.free(extraPtr);
        }
      },
    );

    // Create proxy that strdup's strings before forwarding to Dart callback
    final outProxyFn = calloc<Pointer<NativeFunction<_StreamCallbackNative>>>();
    final proxyData = _proxyCreate!(
      callable.nativeFunction,
      nullptr,
      outProxyFn,
    );
    final proxyFn = outProxyFn.value;
    calloc.free(outProxyFn);

    // v0.12.0 send_message_stream takes a LiteRtLmConversationOptionalArgs*
    // that must be a real allocation (passing null sigsegvs inside
    // litert_lm_lib). We allocate an empty one per call and free it after
    // the native call returns; the callback fires synchronously inside.
    final optionalArgs = b.litert_lm_conversation_optional_args_create();
    if (optionalArgs == nullptr) {
      calloc.free(messagePtr);
      if (extraPtr != nullptr) calloc.free(extraPtr);
      callable.close();
      throw StateError(
          'litert_lm_conversation_optional_args_create returned null — '
          'native libLiteRtLm.dylib initialization failure');
    }

    final result = b.litert_lm_conversation_send_message_stream(
      _conversation!,
      messagePtr.cast(),
      extraPtr == nullptr ? nullptr : extraPtr.cast(),
      optionalArgs,
      proxyFn.cast(),
      proxyData,
    );

    b.litert_lm_conversation_optional_args_delete(optionalArgs);

    if (result != 0) {
      controller
          .addError(Exception('Failed to start streaming (code: $result)'));
      controller.close();
      callable.close();
      calloc.free(messagePtr);
      if (extraPtr != nullptr) calloc.free(extraPtr);
    }

    return controller.stream;
  }

  /// Send a text message and get the full response (sync C API, non-blocking Dart).
  Future<String> sendMessage(String messageJson, {String? extraContext}) async {
    _assertInitialized();
    _assertConversation();
    final b = _bindings!;

    final messagePtr = messageJson.toNativeUtf8();
    final extraPtr =
        extraContext != null ? extraContext.toNativeUtf8() : nullptr;

    // v0.12.0 send_message requires a non-null LiteRtLmConversationOptionalArgs*.
    final optionalArgs = b.litert_lm_conversation_optional_args_create();
    if (optionalArgs == nullptr) {
      calloc.free(messagePtr);
      if (extraPtr != nullptr) calloc.free(extraPtr);
      throw StateError(
          'litert_lm_conversation_optional_args_create returned null — '
          'native libLiteRtLm.dylib initialization failure');
    }

    try {
      final response = b.litert_lm_conversation_send_message(
        _conversation!,
        messagePtr.cast(),
        extraPtr == nullptr ? nullptr : extraPtr.cast(),
        optionalArgs,
      );

      if (response == nullptr) {
        throw Exception('send_message returned null');
      }

      final strPtr = b.litert_lm_json_response_get_string(response);
      final result =
          strPtr == nullptr ? '' : strPtr.cast<Utf8>().toDartString();
      b.litert_lm_json_response_delete(response);
      return result;
    } finally {
      b.litert_lm_conversation_optional_args_delete(optionalArgs);
      calloc.free(messagePtr);
      if (extraPtr != nullptr) calloc.free(extraPtr);
    }
  }

  /// Cancel ongoing generation.
  void cancelGeneration() {
    if (_conversation != null &&
        _conversation != nullptr &&
        _bindings != null) {
      _bindings!.litert_lm_conversation_cancel_process(_conversation!);
      debugPrint('[LiteRtLmFfi] Generation cancelled');
    }
  }

  /// Close the current conversation.
  void closeConversation() {
    if (_conversation != null &&
        _conversation != nullptr &&
        _bindings != null) {
      _bindings!.litert_lm_conversation_delete(_conversation!);
      _conversation = null;
      debugPrint('[LiteRtLmFfi] Conversation closed');
    }
  }

  /// Shutdown the engine and release all resources.
  void shutdown() {
    closeConversation();

    if (_engine != null && _engine != nullptr && _bindings != null) {
      _bindings!.litert_lm_engine_delete(_engine!);
      _engine = null;
      debugPrint('[LiteRtLmFfi] Engine deleted');
    }

    _isInitialized = false;
    _backend = null;
  }

  /// Get session metrics from current conversation including token usage.
  /// Returns empty SessionMetrics if no conversation or benchmark unavailable.
  SessionMetrics getSessionMetrics() {
    if (_conversation == null ||
        _conversation == nullptr ||
        _bindings == null) {
      return SessionMetrics();
    }

    final benchmarkInfo =
        _bindings!.litert_lm_conversation_get_benchmark_info(_conversation!);
    if (benchmarkInfo == nullptr) {
      return SessionMetrics();
    }

    try {
      // Get number of turns
      final numPrefillTurns = _bindings!
          .litert_lm_benchmark_info_get_num_prefill_turns(benchmarkInfo);
      final numDecodeTurns = _bindings!
          .litert_lm_benchmark_info_get_num_decode_turns(benchmarkInfo);

      // Sum up tokens from all turns
      var inputTokens = 0;
      var outputTokens = 0;

      for (var i = 0; i < numPrefillTurns; i++) {
        inputTokens += _bindings!
            .litert_lm_benchmark_info_get_prefill_token_count_at(
                benchmarkInfo, i);
      }

      for (var i = 0; i < numDecodeTurns; i++) {
        outputTokens += _bindings!
            .litert_lm_benchmark_info_get_decode_token_count_at(
                benchmarkInfo, i);
      }

      // Get timing info if available
      final timeToFirstToken = _bindings!
          .litert_lm_benchmark_info_get_time_to_first_token(benchmarkInfo);
      final initTime = _bindings!
          .litert_lm_benchmark_info_get_total_init_time_in_second(
              benchmarkInfo);

      // Calculate average tokens per second from last decode turn if available
      double? tokensPerSecond;
      if (numDecodeTurns > 0) {
        tokensPerSecond = _bindings!
            .litert_lm_benchmark_info_get_decode_tokens_per_sec_at(
                benchmarkInfo, numDecodeTurns - 1);
        if (tokensPerSecond <= 0) tokensPerSecond = null;
      }

      // Cleanup benchmark info
      _bindings!.litert_lm_benchmark_info_delete(benchmarkInfo);

      return SessionMetrics(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: inputTokens + outputTokens,
        timeToFirstTokenMs:
            timeToFirstToken > 0 ? timeToFirstToken * 1000 : null,
        tokensPerSecond: tokensPerSecond,
        initTimeMs: initTime > 0 ? initTime * 1000 : null,
      );
    } catch (e) {
      debugPrint('[LiteRtLmFfiClient] Error getting metrics: $e');
      _bindings!.litert_lm_benchmark_info_delete(benchmarkInfo);
      return SessionMetrics();
    }
  }

  void _assertInitialized() {
    if (!_isInitialized || _engine == null || _engine == nullptr) {
      throw StateError('Engine not initialized. Call initialize() first.');
    }
  }

  void _assertConversation() {
    if (_conversation == null || _conversation == nullptr) {
      throw StateError('No conversation. Call createConversation() first.');
    }
  }
}
