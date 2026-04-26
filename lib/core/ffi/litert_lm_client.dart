import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'litert_lm_bindings.dart';

/// Callback typedef with Uint8 for bool (C _Bool = 1 byte)
typedef _StreamCallbackNative = Void Function(
    Pointer<Void> callbackData,
    Pointer<Char> chunk,
    Uint8 isFinal,
    Pointer<Char> errorMsg);

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

  /// Reads back the native log file (set by stream_proxy_redirect_stderr) and
  /// pipes its contents through debugPrint in 200-char chunks. Used after a
  /// failed engine_create to surface absl/glog output that wouldn't otherwise
  /// reach the Flutter test harness.
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
      debugPrint('[LiteRtLmFfi/native] === BEGIN native log ($p, ${content.length} bytes) ===');
      const chunkSize = 800;
      for (var i = 0; i < content.length; i += chunkSize) {
        final end = (i + chunkSize < content.length) ? i + chunkSize : content.length;
        debugPrint(content.substring(i, end));
      }
      debugPrint('[LiteRtLmFfi/native] === END native log ===');
    } catch (e) {
      debugPrint('[LiteRtLmFfi/native] failed to read $p: $e');
    }
  }

  bool get isInitialized => _isInitialized;

  /// Load the native library and create bindings.
  void _ensureBindings() {
    if (_bindings != null) return;

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
      lib = DynamicLibrary.open('@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm');
      proxyLib = DynamicLibrary.open('@executable_path/Frameworks/StreamProxy.framework/StreamProxy');
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
      // - libLiteRtWebGpuAccelerator.so + libLiteRtTopKWebGpuSampler.so
      //   so gpu_registry.cc:162 can resolve them via the loader's
      //   already-loaded modules table when it does basename-only dlopen
      //   (mirrors the Windows LoadLibraryEx preload pattern)
      // - libLiteRtLm.so itself
      for (final name in const [
        'libLiteRt.so',
        'libGemmaModelConstraintProvider.so',
        'libLiteRtWebGpuAccelerator.so',
        'libLiteRtTopKWebGpuSampler.so',
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
      throw UnsupportedError('Platform not supported for FFI: ${Platform.operatingSystem}');
    }

    _bindings = LiteRtLmBindings(lib);
    _proxyLib = proxyLib;
    _proxyCreate = proxyLib.lookupFunction<_ProxyCreateNative, _ProxyCreateDart>(
        'stream_proxy_create');
    _proxyFreeString = proxyLib.lookupFunction<_ProxyFreeStringNative, _ProxyFreeStringDart>(
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
    if (kDebugMode && (Platform.isIOS || Platform.isLinux)) {
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
  }) async {
    _ensureBindings();
    final b = _bindings!;

    // Create engine settings
    final modelPathPtr = modelPath.toNativeUtf8();
    final backendPtr = backend.toNativeUtf8();
    final visionBackendPtr = enableVision ? backend.toNativeUtf8() : nullptr;
    final audioBackendPtr = enableAudio ? 'cpu'.toNativeUtf8() : nullptr;

    try {
      final settings = b.litert_lm_engine_settings_create(
        modelPathPtr.cast(),
        backendPtr.cast(),
        visionBackendPtr == nullptr
            ? nullptr
            : visionBackendPtr.cast(),
        audioBackendPtr == nullptr
            ? nullptr
            : audioBackendPtr.cast(),
      );

      if (settings == nullptr) {
        throw Exception('Failed to create engine settings');
      }

      // Configure settings
      b.litert_lm_engine_settings_set_max_num_tokens(settings, maxTokens);

      if (cacheDir != null) {
        final cacheDirPtr = cacheDir.toNativeUtf8();
        // Sets cache dir on main, vision, and audio executors (C API patched)
        b.litert_lm_engine_settings_set_cache_dir(settings, cacheDirPtr.cast());
        calloc.free(cacheDirPtr);
      }

      if (maxNumImages > 0) {
        b.litert_lm_engine_settings_set_max_num_images(settings, maxNumImages);
      }

      // Create engine in a background isolate to avoid blocking UI.
      // Pass settings pointer as int address (Pointer can't cross isolates).
      debugPrint('[LiteRtLmFfi] Creating engine from $modelPath (backend=$backend, maxTokens=$maxTokens) ...');
      final settingsAddr = settings.address;
      final sw = Stopwatch()..start();
      final engineAddr = await Isolate.run(() {
        final lib = Platform.isIOS
            ? DynamicLibrary.open('@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm')
            : Platform.isMacOS
                ? DynamicLibrary.open('LiteRtLm.framework/LiteRtLm')
                : (Platform.isLinux || Platform.isAndroid)
                    ? DynamicLibrary.open('libLiteRtLm.so')
                    : DynamicLibrary.open('LiteRtLm.dll');
        final create = lib.lookupFunction<
            Pointer Function(Pointer),
            Pointer Function(Pointer)>('litert_lm_engine_create');
        return create(Pointer.fromAddress(settingsAddr)).address;
      });
      _engine = Pointer<LiteRtLmEngine>.fromAddress(engineAddr);
      sw.stop();
      debugPrint('[LiteRtLmFfi] litert_lm_engine_create took ${sw.elapsedMilliseconds}ms');
      b.litert_lm_engine_settings_delete(settings);

      if (_engine == null || _engine == nullptr) {
        _dumpNativeLog();
        throw Exception('Failed to create engine. Model may be invalid: $modelPath');
      }

      _isInitialized = true;
      debugPrint('[LiteRtLmFfi] Engine initialized successfully');
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

    // Only create custom config if system message or tools are provided.
    // Default config (nullptr) uses model's built-in sampler params.
    Pointer<LiteRtLmConversationConfig>? convConfig;
    if (systemMessage != null || toolsJson != null) {
      final sessionConfig = b.litert_lm_session_config_create();

      final samplerParams = calloc<LiteRtLmSamplerParams>();
      samplerParams.ref.typeAsInt = topP != null ? 2 : 1;
      samplerParams.ref.top_k = topK;
      samplerParams.ref.top_p = topP ?? 0.95;
      samplerParams.ref.temperature = temperature;
      samplerParams.ref.seed = seed;
      b.litert_lm_session_config_set_sampler_params(sessionConfig, samplerParams);
      calloc.free(samplerParams);

      final systemPtr = systemMessage?.toNativeUtf8();
      final toolsPtr = toolsJson?.toNativeUtf8();

      convConfig = b.litert_lm_conversation_config_create(
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
        // Don't silently fall back to defaults — the caller asked for specific
        // sampler/system/tools config and those would be dropped on the floor
        // while createConversation appears to succeed.
        throw Exception(
          'litert_lm_conversation_config_create returned null '
          '(systemMessage=${systemMessage != null}, tools=${toolsJson != null}, '
          'temperature=$temperature, topK=$topK, topP=$topP)');
      }
    }

    _conversation = b.litert_lm_conversation_create(
      _engine!,
      convConfig ?? nullptr,
    );

    if (convConfig != null && convConfig != nullptr) {
      b.litert_lm_conversation_config_delete(convConfig);
    }

    if (_conversation == null || _conversation == nullptr) {
      throw Exception('Failed to create conversation');
    }

    debugPrint('[LiteRtLmFfi] Conversation created');
  }

  /// Build the JSON message for the Conversation API.
  ///
  /// Format: `{"role": "user", "content": [{"type": "text", "text": "..."}]}`
  static String buildMessageJson(String text, {Uint8List? imageBytes, Uint8List? audioBytes}) {
    final content = <Map<String, dynamic>>[];
    if (imageBytes != null) {
      content.add({
        'type': 'image',
        'blob': base64Encode(imageBytes),
      });
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
  Stream<String> chat(String text, {
    Uint8List? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    final messageJson = buildMessageJson(text, imageBytes: imageBytes, audioBytes: audioBytes);
    final extraContext = enableThinking ? '{"enable_thinking": true}' : null;
    return sendMessageStreamRaw(messageJson, extraContext: extraContext)
        .map(extractTextFromResponse);
  }

  /// Send a raw JSON message and get streaming response.
  Stream<String> sendMessageStreamRaw(String messageJson, {String? extraContext}) {
    _assertInitialized();
    _assertConversation();
    final b = _bindings!;

    final controller = StreamController<String>();

    final messagePtr = messageJson.toNativeUtf8();
    final extraPtr = extraContext != null
        ? extraContext.toNativeUtf8()
        : nullptr;

    // NativeCallable.listener is thread-safe — the callback can be
    // invoked from the native background thread that LiteRT-LM uses
    // for streaming, and Dart will marshal it to the right isolate.
    // Dart callback — receives heap-copied strings from proxy
    late final NativeCallable<_StreamCallbackNative> callable;
    callable = NativeCallable<_StreamCallbackNative>.listener(
      (Pointer<Void> data, Pointer<Char> chunk, int isFinal, Pointer<Char> errorMsg) {
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

    final result = b.litert_lm_conversation_send_message_stream(
      _conversation!,
      messagePtr.cast(),
      extraPtr == nullptr ? nullptr : extraPtr.cast(),
      proxyFn.cast(),
      proxyData,
    );

    if (result != 0) {
      controller.addError(Exception('Failed to start streaming (code: $result)'));
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
    final extraPtr = extraContext != null ? extraContext.toNativeUtf8() : nullptr;

    try {
      final response = b.litert_lm_conversation_send_message(
        _conversation!,
        messagePtr.cast(),
        extraPtr == nullptr ? nullptr : extraPtr.cast(),
      );

      if (response == nullptr) {
        throw Exception('send_message returned null');
      }

      final strPtr = b.litert_lm_json_response_get_string(response);
      final result = strPtr == nullptr ? '' : strPtr.cast<Utf8>().toDartString();
      b.litert_lm_json_response_delete(response);
      return result;
    } finally {
      calloc.free(messagePtr);
      if (extraPtr != nullptr) calloc.free(extraPtr);
    }
  }

  /// Cancel ongoing generation.
  void cancelGeneration() {
    if (_conversation != null && _conversation != nullptr && _bindings != null) {
      _bindings!.litert_lm_conversation_cancel_process(_conversation!);
      debugPrint('[LiteRtLmFfi] Generation cancelled');
    }
  }

  /// Close the current conversation.
  void closeConversation() {
    if (_conversation != null && _conversation != nullptr && _bindings != null) {
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
