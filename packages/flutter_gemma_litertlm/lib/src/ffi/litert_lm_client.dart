import 'dart:async';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mutex/mutex.dart';

import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/core/parsing/sdk_text_extractor.dart';
import 'litert_lm_bindings.dart';

/// Callback typedef with Uint8 for bool (C _Bool = 1 byte)
typedef _StreamCallbackNative =
    Void Function(
      Pointer<Void> callbackData,
      Pointer<Char> chunk,
      Uint8 isFinal,
      Pointer<Char> errorMsg,
    );

/// stream_proxy_create: creates a proxy that strdup's strings before
/// forwarding to the Dart callback (prevents use-after-free).
typedef _ProxyCreateNative =
    Pointer<Void> Function(
      Pointer<NativeFunction<_StreamCallbackNative>> dartCallback,
      Pointer<Void> dartData,
      Pointer<Pointer<NativeFunction<_StreamCallbackNative>>> outProxyFn,
    );
typedef _ProxyCreateDart =
    Pointer<Void> Function(
      Pointer<NativeFunction<_StreamCallbackNative>> dartCallback,
      Pointer<Void> dartData,
      Pointer<Pointer<NativeFunction<_StreamCallbackNative>>> outProxyFn,
    );

/// Free a strdup'd string from the proxy callback.
typedef _ProxyFreeStringNative = Void Function(Pointer<Char> str);
typedef _ProxyFreeStringDart = void Function(Pointer<Char> str);

/// Per-conversation operations a session needs from the FFI layer.
///
/// [LiteRtLmConversationHandle] is the real implementation backed by a
/// native `LiteRtLmConversation*`. Tests inject a fake implementing this
/// interface so [FfiInferenceModelSession] orchestration (query buffering,
/// raw-response capture, Gemma 4 tool-call extraction) can be exercised on
/// the host VM with no native engine.
abstract class ConversationHandle {
  Stream<String> chat(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking,
  });

  Stream<String> chatRaw(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking,
  });

  void cancelGeneration();

  SessionMetrics getSessionMetrics();

  void close();
}

/// One conversation owned by a [LiteRtLmFfiClient]. Each call to
/// [LiteRtLmFfiClient.createConversationHandle] returns a fresh handle:
/// the engine pointer is shared across handles, the conversation pointer
/// is private to this handle.
///
/// This is what makes concurrent sessions possible — the LiteRT-LM C API
/// supports multiple `LiteRtLmConversation*` per engine; the handle owns
/// one and routes every per-conversation native call through the client's
/// private `_…On(conv, …)` methods.
///
/// Lifetime contract: the caller must call [close] when done. The owning
/// client closes any remaining handles on [LiteRtLmFfiClient.shutdown].
class LiteRtLmConversationHandle implements ConversationHandle {
  LiteRtLmConversationHandle._(this._client, this._conversation);

  final LiteRtLmFfiClient _client;
  Pointer<LiteRtLmConversation>? _conversation;

  bool get isClosed => _conversation == null;

  void _assertOpen() {
    if (_conversation == null) {
      throw StateError('Conversation handle is closed');
    }
  }

  @override
  Stream<String> chat(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    _assertOpen();
    return _client._chatOn(
      _conversation!,
      text,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      enableThinking: enableThinking,
    );
  }

  @override
  Stream<String> chatRaw(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    _assertOpen();
    return _client._chatRawOn(
      _conversation!,
      text,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      enableThinking: enableThinking,
    );
  }

  Future<String> sendMessage(String messageJson, {String? extraContext}) {
    _assertOpen();
    return _client._sendMessageOn(
      _conversation!,
      messageJson,
      extraContext: extraContext,
    );
  }

  Stream<String> sendMessageStreamRaw(
    String messageJson, {
    String? extraContext,
  }) {
    _assertOpen();
    return _client._sendMessageStreamRawOn(
      _conversation!,
      messageJson,
      extraContext: extraContext,
    );
  }

  @override
  void cancelGeneration() {
    if (_conversation == null) return;
    _client._cancelOn(_conversation!);
  }

  @override
  SessionMetrics getSessionMetrics() {
    if (_conversation == null) return SessionMetrics();
    return _client._getMetricsOn(_conversation!);
  }

  @override
  void close() {
    if (_conversation == null) return;
    _client._deleteConversation(_conversation!);
    _conversation = null;
    _client._handles.remove(this);
  }
}

/// Opens the LiteRT-LM shared library for the current platform.
///
/// Top-level so it can be called from a spawned isolate, which cannot capture
/// `this` or any other non-const closure state.
DynamicLibrary _openLiteRtLmLibrary() {
  if (Platform.isIOS) {
    return DynamicLibrary.open(
      '@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm',
    );
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.open('LiteRtLm.framework/LiteRtLm');
  }
  if (Platform.isLinux || Platform.isAndroid) {
    return DynamicLibrary.open('libLiteRtLm.so');
  }
  return DynamicLibrary.open('LiteRtLm.dll');
}

/// Calls native `litert_lm_conversation_create` on a spawned isolate.
///
/// For multimodal models this compiles the vision encoder's OpenCL kernels
/// (`clBuildProgram`), which costs ~8s on a mid-range mobile GPU. Recent
/// Flutter runs the Dart UI thread on Android's platform thread, so calling
/// this inline blocks input dispatch and the OS raises an
/// "Input dispatching timed out" ANR.
///
/// Native pointers are process-wide, so the conversation can be built on any
/// isolate and used from this one. This mirrors what `litert_lm_engine_create`
/// already does.
Future<int> _createConversationOffMainIsolate({
  required int engineAddr,
  required int configAddr,
}) {
  final isolateLogLevel = gemmaLogLevel;
  return Isolate.run(() {
    gemmaLogLevel = isolateLogLevel;
    final create = _openLiteRtLmLibrary()
        .lookupFunction<
          Pointer Function(Pointer, Pointer),
          Pointer Function(Pointer, Pointer)
        >('litert_lm_conversation_create');
    return create(
      Pointer.fromAddress(engineAddr),
      Pointer.fromAddress(configAddr),
    ).address;
  });
}

/// High-level Dart wrapper around the LiteRT-LM C API.
///
/// Provides a clean async interface over the native C functions,
/// managing memory and translating C callbacks into Dart Streams.
///
/// Conversation lifetime is owned by [LiteRtLmConversationHandle] —
/// the client holds the engine and tracks live handles for shutdown.
/// Legacy single-session methods ([createConversation], [chat],
/// [sendMessageStreamRaw], etc.) route through an internal
/// [_legacyHandle] for backward compatibility.
class LiteRtLmFfiClient {
  LiteRtLmBindings? _bindings;
  // Holding a reference prevents the proxy DynamicLibrary from being GC'd
  // while function pointers obtained via lookupFunction are still in use.
  // ignore: unused_field
  DynamicLibrary? _proxyLib;
  _ProxyCreateDart? _proxyCreate;
  _ProxyFreeStringDart? _proxyFreeString;
  Pointer<LiteRtLmEngine>? _engine;
  bool _isInitialized = false;
  String? _nativeLogPath;
  String? _backend;

  /// All live conversation handles created on this client. Closed in bulk
  /// by [shutdown]. Each handle removes itself on its own [close].
  final Set<LiteRtLmConversationHandle> _handles = {};

  /// Backing handle for the legacy single-conversation API
  /// ([createConversation] / [closeConversation] / [chat] / etc.). Kept so
  /// existing single-session call sites work unchanged while the new
  /// handle-based multi-session path is wired up.
  LiteRtLmConversationHandle? _legacyHandle;

  /// Serializes native send_message / send_message_stream calls across
  /// conversations. The LiteRT-LM C API is not documented as reentrant on
  /// one engine — two conversations generating at once could race inside
  /// liblitert_lm. The mutex makes concurrent sessions safe (each waits
  /// its turn); it is uncontended when only one session is active, so the
  /// single-session fast path pays only an acquire/release on an empty
  /// lock. Cancel does NOT take the lock — it must interrupt an in-flight
  /// streaming call.
  final Mutex _nativeMutex = Mutex();

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
        gemmaLog('[LiteRtLmFfi/native] log file missing: $p');
        return;
      }
      final content = f.readAsStringSync();
      if (content.isEmpty) {
        gemmaLog('[LiteRtLmFfi/native] (no new native log output)');
        return;
      }
      gemmaLog(
        '[LiteRtLmFfi/native] === BEGIN native log ($p, ${content.length} bytes) ===',
      );
      const chunkSize = 800;
      for (var i = 0; i < content.length; i += chunkSize) {
        final end = (i + chunkSize < content.length)
            ? i + chunkSize
            : content.length;
        gemmaLog(content.substring(i, end), level: GemmaLogLevel.verbose);
      }
      gemmaLog('[LiteRtLmFfi/native] === END native log ===');
      // Truncate so the next dump only shows new output. If truncation fails
      // (read-only fs etc.), next dump just re-prints — non-fatal.
      try {
        f.writeAsStringSync('');
      } catch (_) {}
    } catch (e) {
      gemmaLog('[LiteRtLmFfi/native] failed to read $p: $e');
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
    gemmaLog('[LiteRtLmFfi] Loading native libraries...');
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
        '@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm',
      );
      proxyLib = DynamicLibrary.open(
        '@executable_path/Frameworks/StreamProxy.framework/StreamProxy',
      );
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
      final loadGlobal = proxyLib
          .lookupFunction<
            Pointer Function(Pointer<Utf8>),
            Pointer Function(Pointer<Utf8>)
          >('stream_proxy_load_global');
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
      final loadGlobal = proxyLib
          .lookupFunction<
            Pointer Function(Pointer<Utf8>),
            Pointer Function(Pointer<Utf8>)
          >('stream_proxy_load_global');
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
      final loadGlobal = proxyLib
          .lookupFunction<
            Pointer Function(Pointer<Utf8>),
            Pointer Function(Pointer<Utf8>)
          >('stream_proxy_load_global');
      final pathPtr = 'libLiteRtLm.so'.toNativeUtf8();
      final handle = loadGlobal(pathPtr);
      calloc.free(pathPtr);
      if (handle == nullptr) {
        // The most common cause we've seen is Android API < 30 (#265):
        // upstream `libLiteRtLm.so` is built against Bionic 11+ libc and
        // hard-references `pthread_cond_clockwait` / `sem_clockwait`,
        // which don't exist on API 29 and below. Use a MediaPipe `.task`
        // model instead, or bump `minSdkVersion` to 30.
        throw Exception(
          'Failed to load libLiteRtLm.so with RTLD_GLOBAL. '
          'On Android, this commonly indicates API < 30: `.litertlm` models '
          'require Android 11+ (minSdkVersion 30). For older devices use a '
          'MediaPipe `.task` model instead. See '
          'https://github.com/DenisovAV/flutter_gemma/issues/265',
        );
      }
      lib = DynamicLibrary.open('libLiteRtLm.so'); // Now symbols are global
    } else {
      throw UnsupportedError(
        'Platform not supported for FFI: ${Platform.operatingSystem}',
      );
    }

    _bindings = LiteRtLmBindings(lib);
    _proxyLib = proxyLib;
    _proxyCreate = proxyLib
        .lookupFunction<_ProxyCreateNative, _ProxyCreateDart>(
          'stream_proxy_create',
        );
    _proxyFreeString = proxyLib
        .lookupFunction<_ProxyFreeStringNative, _ProxyFreeStringDart>(
          'stream_proxy_free_string',
        );

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
      final redirect = proxyLib
          .lookupFunction<
            Int32 Function(Pointer<Utf8>),
            int Function(Pointer<Utf8>)
          >('stream_proxy_redirect_stderr');
      final pathPtr = _nativeLogPath!.toNativeUtf8();
      final rc = redirect(pathPtr);
      calloc.free(pathPtr);
      if (rc != 0) {
        // Log capture is best-effort but its failure makes _dumpNativeLog
        // useless. Surface it instead of silently continuing.
        gemmaLog(
          '[LiteRtLmFfi] WARNING: stderr redirect failed (rc=$rc) — '
          'native log dumps will be empty',
        );
        _nativeLogPath = null;
      } else {
        gemmaLog('[LiteRtLmFfi] stderr redirected to $_nativeLogPath');
      }
    }

    gemmaLog(
      '[LiteRtLmFfi/perf] _ensureBindings total: ${loadSw.elapsedMilliseconds}ms',
    );
    gemmaLog('[LiteRtLmFfi] Libraries loaded');
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
    gemmaLog('[LiteRtLmFfi/perf] _ensureBindings: ${bindingsMs}ms');
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
      gemmaLog(
        '[LiteRtLmFfi/perf] settings_create: ${initSw.elapsedMilliseconds - settingsCreateStart}ms',
      );

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
          settings,
          enableSpeculativeDecoding,
        );
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
          settings,
          dirPtr.cast(),
        );
        calloc.free(dirPtr);
        b.litert_lm_engine_settings_set_use_hw_masking_for_npu(settings, false);
        gemmaLog(
          '[LiteRtLmFfi] NPU Windows: dispatch_lib_dir=$exeDir, use_hw_masking_for_npu=false',
        );
      }

      // Android NPU: point LiteRT at the app's nativeLibraryDir so it can
      // dlopen libLiteRtDispatch_Qualcomm.so from there. On Android, Native
      // Assets unpacks all bundled .so files into nativeLibraryDir at install
      // time; without this setting LiteRT searches system paths and fails.
      if (Platform.isAndroid && backend == 'npu') {
        const bundledChannel = MethodChannel('flutter_gemma_bundled');
        final nativeLibDir = await bundledChannel.invokeMethod<String>(
          'getNativeLibraryDir',
        );
        if (nativeLibDir == null) {
          throw StateError(
            '[LiteRtLmFfi] NPU Android: getNativeLibraryDir returned null — '
            'plugin channel not registered; cannot locate '
            'libLiteRtDispatch_Qualcomm.so.',
          );
        }
        final dirPtr = nativeLibDir.toNativeUtf8();
        b.litert_lm_engine_settings_set_litert_dispatch_lib_dir(
          settings,
          dirPtr.cast(),
        );
        calloc.free(dirPtr);
        gemmaLog('[LiteRtLmFfi] NPU Android: dispatch_lib_dir=$nativeLibDir');
      }

      // Create engine in a background isolate to avoid blocking UI.
      // Pass settings pointer as int address (Pointer can't cross isolates).
      gemmaLog(
        '[LiteRtLmFfi] Creating engine from $modelPath (backend=$backend, maxTokens=$maxTokens) ...',
      );
      gemmaLog(
        '[LiteRtLmFfi/perf] === START litert_lm_engine_create (native — model load + accelerator init + KV cache prefill) ===',
      );
      final settingsAddr = settings.address;
      final sw = Stopwatch()..start();
      // Snapshot the log level so the spawned isolate (a fresh copy of the
      // per-isolate top-level `gemmaLogLevel`, default info) honours the
      // caller's setting instead of leaking perf logs at the default level.
      final isolateLogLevel = gemmaLogLevel;
      final engineAddr = await Isolate.run(() {
        gemmaLogLevel = isolateLogLevel;
        final isolateSw = Stopwatch()..start();
        final lib = Platform.isIOS
            ? DynamicLibrary.open(
                '@executable_path/Frameworks/LiteRtLm.framework/LiteRtLm',
              )
            : Platform.isMacOS
            ? DynamicLibrary.open('LiteRtLm.framework/LiteRtLm')
            : (Platform.isLinux || Platform.isAndroid)
            ? DynamicLibrary.open('libLiteRtLm.so')
            : DynamicLibrary.open('LiteRtLm.dll');
        gemmaLog(
          '[LiteRtLmFfi/perf]   isolate: DynamicLibrary.open: ${isolateSw.elapsedMilliseconds}ms',
          level: GemmaLogLevel.verbose,
        );
        final lookupStart = isolateSw.elapsedMilliseconds;
        final create = lib
            .lookupFunction<
              Pointer Function(Pointer),
              Pointer Function(Pointer)
            >('litert_lm_engine_create');
        gemmaLog(
          '[LiteRtLmFfi/perf]   isolate: lookupFunction: ${isolateSw.elapsedMilliseconds - lookupStart}ms',
          level: GemmaLogLevel.verbose,
        );
        final createStart = isolateSw.elapsedMilliseconds;
        final ptr = create(Pointer.fromAddress(settingsAddr)).address;
        gemmaLog(
          '[LiteRtLmFfi/perf]   isolate: native litert_lm_engine_create: ${isolateSw.elapsedMilliseconds - createStart}ms',
          level: GemmaLogLevel.verbose,
        );
        return ptr;
      });
      _engine = Pointer<LiteRtLmEngine>.fromAddress(engineAddr);
      sw.stop();
      gemmaLog(
        '[LiteRtLmFfi/perf] === END litert_lm_engine_create: ${sw.elapsedMilliseconds}ms (includes isolate spawn ~50-200ms) ===',
      );
      gemmaLog(
        '[LiteRtLmFfi] litert_lm_engine_create took ${sw.elapsedMilliseconds}ms',
      );
      b.litert_lm_engine_settings_delete(settings);

      if (_engine == null || _engine == nullptr) {
        _dumpNativeLog();
        throw Exception(
          'Failed to create engine. Model may be invalid: $modelPath',
        );
      }

      _isInitialized = true;
      gemmaLog(
        '[LiteRtLmFfi/perf] initialize() total: ${initSw.elapsedMilliseconds}ms',
      );
      gemmaLog('[LiteRtLmFfi] Engine initialized successfully');

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

  /// Create a new conversation handle with optional system message and
  /// tools. The engine allows only ONE live conversation at a time
  /// (upstream LiteRT-LM #966), so the caller must delete any prior
  /// conversation before creating a new one — this is how virtual-session
  /// multiplexing rebuilds context. The caller owns the handle and must
  /// call [LiteRtLmConversationHandle.close].
  ///
  /// [messagesJson] optionally seeds the conversation with prior turns
  /// (a JSON array of `{role, content}` objects). Used by the virtual-
  /// session multiplexer to replay a session's history into a fresh
  /// conversation. When null the conversation starts empty (legacy
  /// behaviour).
  Future<LiteRtLmConversationHandle> createConversationHandle({
    String? systemMessage,
    String? toolsJson,
    String? messagesJson,
    double temperature = 0.8,
    int topK = 40,
    double? topP,
    int seed = 1,
    int? maxOutputTokens,
  }) async {
    final conv = await _createRawConversation(
      systemMessage: systemMessage,
      toolsJson: toolsJson,
      messagesJson: messagesJson,
      temperature: temperature,
      topK: topK,
      topP: topP,
      seed: seed,
      maxOutputTokens: maxOutputTokens,
    );
    gemmaLog('[LiteRtLmFfi] Conversation created');
    final handle = LiteRtLmConversationHandle._(this, conv);
    _handles.add(handle);
    return handle;
  }

  /// Create a raw native conversation pointer with the given config.
  ///
  /// Shared by [createConversationHandle] (which wraps it in a tracked
  /// [LiteRtLmConversationHandle]) and the virtual-session multiplexer
  /// ([startVirtualTurn]) which owns the pointer's lifecycle directly and
  /// does not register a handle. Lock-free — callers that need
  /// serialization (the multiplexer) hold [_nativeMutex] around it.
  Future<Pointer<LiteRtLmConversation>> _createRawConversation({
    String? systemMessage,
    String? toolsJson,
    String? messagesJson,
    double temperature = 0.8,
    int topK = 40,
    double? topP,
    int seed = 1,
    int? maxOutputTokens,
  }) async {
    _assertInitialized();
    final b = _bindings!;

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
        sessionConfig,
        samplerParams,
      );
      calloc.free(samplerParams);
    } else {
      gemmaLog(
        '[LiteRtLmFfi] NPU backend — sampler params '
        '(temperature, topK, topP, seed) ignored, engine uses '
        'internal greedy sampling.',
      );
    }

    // Optional per-session cap on how many tokens are *generated* (output),
    // independent of the engine's context window (maxTokens / KV-cache). This
    // is what callers usually want when they say "limit the response length".
    // Skipped on NPU for the same reason as sampler params: the NPU executor
    // only supports internal greedy sampling and rejects extra session config
    // upstream — setting it there risks engine_create/generation failures.
    if (maxOutputTokens != null) {
      if (_backend != 'npu') {
        b.litert_lm_session_config_set_max_output_tokens(
          sessionConfig,
          maxOutputTokens,
        );
      } else {
        gemmaLog(
          '[LiteRtLmFfi] NPU backend — maxOutputTokens ($maxOutputTokens) '
          'ignored (NPU executor uses internal greedy sampling).',
        );
      }
    }

    final systemPtr = systemMessage?.toNativeUtf8();
    final toolsPtr = toolsJson?.toNativeUtf8();
    final messagesPtr = messagesJson?.toNativeUtf8();

    final Pointer<LiteRtLmConversationConfig> convConfig = b
        .litert_lm_conversation_config_create(
          _engine!,
          sessionConfig,
          systemPtr?.cast() ?? nullptr,
          toolsPtr?.cast() ?? nullptr,
          messagesPtr?.cast() ?? nullptr,
          toolsJson != null,
        );

    b.litert_lm_session_config_delete(sessionConfig);
    if (systemPtr != null) calloc.free(systemPtr);
    if (toolsPtr != null) calloc.free(toolsPtr);
    if (messagesPtr != null) calloc.free(messagesPtr);

    if (convConfig == nullptr) {
      throw Exception(
        'litert_lm_conversation_config_create returned null '
        '(systemMessage=${systemMessage != null}, tools=${toolsJson != null}, '
        'temperature=$temperature, topK=$topK, topP=$topP)',
      );
    }

    final conv = Pointer<LiteRtLmConversation>.fromAddress(
      await _createConversationOffMainIsolate(
        engineAddr: _engine!.address,
        configAddr: convConfig.address,
      ),
    );

    b.litert_lm_conversation_config_delete(convConfig);

    if (conv == nullptr) {
      _dumpNativeLog();
      throw Exception('Failed to create conversation');
    }

    return conv;
  }

  /// Legacy single-conversation create. Closes the previous legacy
  /// conversation (if any) and opens a fresh one stored in [_legacyHandle].
  /// Kept for backward compat — new code should use
  /// [createConversationHandle] and own the handle directly.
  Future<void> createConversation({
    String? systemMessage,
    String? toolsJson,
    double temperature = 0.8,
    int topK = 40,
    double? topP,
    int seed = 1,
  }) async {
    _legacyHandle?.close();
    _legacyHandle = await createConversationHandle(
      systemMessage: systemMessage,
      toolsJson: toolsJson,
      temperature: temperature,
      topK: topK,
      topP: topP,
      seed: seed,
    );
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
      content.add({'type': 'audio', 'blob': base64Encode(audioBytes)});
    }
    content.add({'type': 'text', 'text': text});
    return jsonEncode({'role': 'user', 'content': content});
  }

  /// Serialize a turn history into the `messages_json` array the
  /// conversation config accepts as a preface. Each turn is
  /// `{role, content: [{type: 'text', text}]}`. Used by the virtual-session
  /// multiplexer to rebuild a session's full context (user + assistant
  /// turns) in one prefill when switching the single live conversation.
  ///
  /// Verified honored by the patched native (a `messages_json` preface with
  /// a prior user+assistant turn lets the model recall it).
  static String buildHistoryJson(List<({String role, String text})> turns) {
    return jsonEncode([
      for (final turn in turns)
        {
          'role': turn.role,
          'content': [
            {'type': 'text', 'text': turn.text},
          ],
        },
    ]);
  }

  /// Extract text from a LiteRT-LM JSON response chunk. Delegates to
  /// [SdkTextExtractor] — single source of truth shared with the web
  /// `@litert-lm/core` path so both engines map identical chunks to text
  /// the same way.
  static String extractTextFromResponse(String jsonStr) =>
      SdkTextExtractor.extractTextFromResponse(jsonStr);

  /// Send a message and get streaming response as plain text chunks on the
  /// given conversation. Supports multiple images via `imageBytes` list.
  Stream<String> _chatOn(
    Pointer<LiteRtLmConversation> conv,
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
    return _sendMessageStreamRawOn(
      conv,
      messageJson,
      extraContext: extraContext,
    ).map(extractTextFromResponse);
  }

  /// Same as [_chatOn] but yields raw SDK JSON chunks without
  /// `extractTextFromResponse` mapping. Required by Gemma 4 path so callers
  /// can read the structured `tool_calls` field via [extractToolCalls].
  Stream<String> _chatRawOn(
    Pointer<LiteRtLmConversation> conv,
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
    return _sendMessageStreamRawOn(
      conv,
      messageJson,
      extraContext: extraContext,
    );
  }

  /// Legacy: streaming chat on the implicit [_legacyHandle] conversation.
  Stream<String> chat(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    _assertConversation();
    return _legacyHandle!.chat(
      text,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      enableThinking: enableThinking,
    );
  }

  /// Legacy: raw streaming chat on the implicit [_legacyHandle] conversation.
  Stream<String> chatRaw(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) {
    _assertConversation();
    return _legacyHandle!.chatRaw(
      text,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      enableThinking: enableThinking,
    );
  }

  /// Send a raw JSON message on the given conversation and get a streaming
  /// response. Holds [_nativeMutex] for the whole generation so concurrent
  /// conversations don't race inside liblitert_lm; releases on completion or
  /// error.
  Stream<String> _sendMessageStreamRawOn(
    Pointer<LiteRtLmConversation> conv,
    String messageJson, {
    String? extraContext,
  }) async* {
    await _nativeMutex.acquire();
    try {
      yield* _doSendMessageStreamRawOn(
        conv,
        messageJson,
        extraContext: extraContext,
      );
    } finally {
      _nativeMutex.release();
    }
  }

  /// The single native conversation currently materialized for the
  /// virtual-session multiplexer. The LiteRT-LM engine allows only ONE live
  /// conversation at a time (upstream #966), so virtual sessions take turns:
  /// each turn tears this down and rebuilds it seeded with the active
  /// session's history. null when no virtual turn is in flight.
  Pointer<LiteRtLmConversation>? _virtualConv;

  /// Run one turn for a virtual session, holding [_nativeMutex] for the whole
  /// turn so no other virtual session can swap the live conversation out from
  /// under it.
  ///
  /// The turn is: tear down the previously-active virtual conversation (if
  /// any), create a fresh one seeded with [historyJson] (a `messages_json`
  /// preface that replays this session's prior user+assistant turns — proven
  /// honored by the patched native), then stream the response for
  /// [messageJson]. The conversation is left live after the stream so a
  /// follow-up turn on the SAME session can reuse it without a rebuild; only a
  /// turn on a DIFFERENT session pays the teardown+replay cost.
  ///
  /// [conversationToken] identifies the virtual session. When it equals the
  /// token that built [_virtualConv], the existing live conversation is
  /// reused (cheap same-session follow-up). Otherwise it's rebuilt.
  /// True while a virtual turn holds [_nativeMutex] and is actively streaming.
  /// Lets [releaseVirtualConversation] (a session closing mid-generation) defer
  /// the native teardown instead of deleting the pointer out from under the
  /// live stream (use-after-free).
  bool _virtualTurnInFlight = false;

  /// Token of a session that asked to release the live conversation while a
  /// turn was in flight. The teardown is deferred to the turn's cleanup.
  Object? _pendingReleaseToken;

  Stream<String> startVirtualTurn({
    required Object conversationToken,
    required String messageJson,
    required List<({String role, String text})> history,
    String? systemMessage,
    String? toolsJson,
    double temperature = 0.8,
    int topK = 40,
    double? topP,
    int seed = 1,
    String? extraContext,
    int? maxOutputTokens,
  }) {
    // StreamController (not async*) so the mutex release is tied to the
    // controller lifecycle — it fires on done, error, AND consumer cancel /
    // abandon. An async* generator's finally only runs when the consumer
    // drains the stream, so an abandoned stream would hold the mutex forever
    // and deadlock every other session.
    final controller = StreamController<String>();
    var mutexHeld = false;
    StreamSubscription<String>? inner;

    Future<void> releaseAndCleanup() async {
      _virtualTurnInFlight = false;
      // Honor a teardown that a closing session deferred while we held the lock.
      if (_pendingReleaseToken != null) {
        final pending = _pendingReleaseToken;
        _pendingReleaseToken = null;
        if (_virtualActiveToken == pending) {
          final conv = _virtualConv;
          if (conv != null) {
            _deleteConversation(conv);
            _virtualConv = null;
            _virtualActiveToken = null;
          }
        }
      }
      if (mutexHeld) {
        mutexHeld = false;
        _nativeMutex.release();
      }
    }

    controller.onListen = () async {
      try {
        await _nativeMutex.acquire();
        mutexHeld = true;
        _virtualTurnInFlight = true;
        if (_virtualActiveToken != conversationToken || _virtualConv == null) {
          // Switching sessions (or first turn): drop the old live conversation
          // and rebuild one replaying this session's history as a preface.
          final old = _virtualConv;
          if (old != null) {
            _deleteConversation(old);
            _virtualConv = null;
          }
          final historyJson = history.isEmpty
              ? null
              : buildHistoryJson(history);
          _virtualConv = await _createRawConversation(
            systemMessage: systemMessage,
            toolsJson: toolsJson,
            messagesJson: historyJson,
            temperature: temperature,
            topK: topK,
            topP: topP,
            seed: seed,
            maxOutputTokens: maxOutputTokens,
          );
          _virtualActiveToken = conversationToken;
        }
        inner =
            _doSendMessageStreamRawOn(
              _virtualConv!,
              messageJson,
              extraContext: extraContext,
            ).listen(
              controller.add,
              onError: controller.addError,
              onDone: () async {
                await releaseAndCleanup();
                if (!controller.isClosed) await controller.close();
              },
              cancelOnError: false,
            );
      } catch (e, st) {
        controller.addError(e, st);
        await releaseAndCleanup();
        if (!controller.isClosed) await controller.close();
      }
    };

    // Fires when the consumer cancels / abandons the stream — guarantees the
    // mutex is released even if generation never completed.
    controller.onCancel = () async {
      await inner?.cancel();
      await releaseAndCleanup();
    };

    return controller.stream;
  }

  /// Token of the virtual session whose history is currently materialized in
  /// [_virtualConv]. Used to skip the teardown+replay when the next turn is on
  /// the same session.
  Object? _virtualActiveToken;

  /// Cancel an in-flight virtual turn for [conversationToken]. Mirrors
  /// [_cancelOn] but targets the shared live virtual conversation. Does NOT
  /// take the mutex (it must interrupt a generation that already holds it).
  ///
  /// No-op unless [conversationToken] owns the currently-live conversation —
  /// otherwise one session's `stopGeneration()` would cancel another session's
  /// in-flight generation (the single conversation is shared).
  void cancelVirtualTurn(Object conversationToken) {
    if (_virtualActiveToken != conversationToken) return;
    final conv = _virtualConv;
    if (conv != null) _cancelOn(conv);
  }

  /// Tear down the live virtual conversation if it belongs to
  /// [conversationToken]. Called when a virtual session closes so its native
  /// conversation doesn't linger. If a different session is active, this is a
  /// no-op — that session's conversation must stay live.
  ///
  /// If a turn is in flight, the teardown is DEFERRED to the turn's cleanup —
  /// deleting the pointer now would be a use-after-free. We also cancel the
  /// in-flight generation so the turn finishes promptly and the deferred
  /// teardown runs.
  void releaseVirtualConversation(Object conversationToken) {
    if (_virtualActiveToken != conversationToken) return;
    if (_virtualTurnInFlight) {
      _pendingReleaseToken = conversationToken;
      final conv = _virtualConv;
      if (conv != null) _cancelOn(conv);
      return;
    }
    final conv = _virtualConv;
    if (conv != null) {
      _deleteConversation(conv);
      _virtualConv = null;
      _virtualActiveToken = null;
    }
  }

  Stream<String> _doSendMessageStreamRawOn(
    Pointer<LiteRtLmConversation> conv,
    String messageJson, {
    String? extraContext,
  }) {
    _assertInitialized();
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
    callable = NativeCallable<_StreamCallbackNative>.listener((
      Pointer<Void> data,
      Pointer<Char> chunk,
      int isFinal,
      Pointer<Char> errorMsg,
    ) {
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
    });

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
        'native libLiteRtLm.dylib initialization failure',
      );
    }

    final result = b.litert_lm_conversation_send_message_stream(
      conv,
      messagePtr.cast(),
      extraPtr == nullptr ? nullptr : extraPtr.cast(),
      optionalArgs,
      proxyFn.cast(),
      proxyData,
    );

    b.litert_lm_conversation_optional_args_delete(optionalArgs);

    if (result != 0) {
      controller.addError(
        Exception('Failed to start streaming (code: $result)'),
      );
      controller.close();
      callable.close();
      calloc.free(messagePtr);
      if (extraPtr != nullptr) calloc.free(extraPtr);
    }

    // Consumer abandoned the stream (subscription.cancel) without calling
    // stopGeneration(). Tell native to stop sampling so the GPU isn't left
    // generating an orphaned response: otherwise the next close()/inference
    // can stall on a still-busy shared GPU conversation — observed on
    // Windows Intel iGPU as a hang on session.close() that cascades the whole
    // gate (macOS/Linux mask it by finishing the orphaned generation fast).
    // The native cancel surfaces as a CANCELLED error in the callback above,
    // which closes the controller cleanly. Idempotent on an already-finished
    // generation, so it's safe even if the stream completed concurrently.
    controller.onCancel = () => _cancelOn(conv);

    return controller.stream;
  }

  /// Legacy: streaming raw on the implicit [_legacyHandle] conversation.
  Stream<String> sendMessageStreamRaw(
    String messageJson, {
    String? extraContext,
  }) {
    _assertConversation();
    return _legacyHandle!.sendMessageStreamRaw(
      messageJson,
      extraContext: extraContext,
    );
  }

  /// Send a text message on the given conversation and get the full response
  /// (sync C API, non-blocking Dart). Serialized via [_nativeMutex] so it
  /// can't run concurrently with another conversation's generation.
  Future<String> _sendMessageOn(
    Pointer<LiteRtLmConversation> conv,
    String messageJson, {
    String? extraContext,
  }) {
    return _nativeMutex.protect(() async {
      _assertInitialized();
      final b = _bindings!;

      final messagePtr = messageJson.toNativeUtf8();
      final extraPtr = extraContext != null
          ? extraContext.toNativeUtf8()
          : nullptr;

      // v0.12.0 send_message requires a non-null LiteRtLmConversationOptionalArgs*.
      final optionalArgs = b.litert_lm_conversation_optional_args_create();
      if (optionalArgs == nullptr) {
        calloc.free(messagePtr);
        if (extraPtr != nullptr) calloc.free(extraPtr);
        throw StateError(
          'litert_lm_conversation_optional_args_create returned null — '
          'native libLiteRtLm.dylib initialization failure',
        );
      }

      try {
        final response = b.litert_lm_conversation_send_message(
          conv,
          messagePtr.cast(),
          extraPtr == nullptr ? nullptr : extraPtr.cast(),
          optionalArgs,
        );

        if (response == nullptr) {
          throw Exception('send_message returned null');
        }

        final strPtr = b.litert_lm_json_response_get_string(response);
        final result = strPtr == nullptr
            ? ''
            : strPtr.cast<Utf8>().toDartString();
        b.litert_lm_json_response_delete(response);
        return result;
      } finally {
        b.litert_lm_conversation_optional_args_delete(optionalArgs);
        calloc.free(messagePtr);
        if (extraPtr != nullptr) calloc.free(extraPtr);
      }
    });
  }

  /// Legacy: sync send on the implicit [_legacyHandle] conversation.
  Future<String> sendMessage(String messageJson, {String? extraContext}) {
    _assertConversation();
    return _legacyHandle!.sendMessage(messageJson, extraContext: extraContext);
  }

  /// Cancel ongoing generation on the given conversation.
  void _cancelOn(Pointer<LiteRtLmConversation> conv) {
    if (_bindings != null) {
      _bindings!.litert_lm_conversation_cancel_process(conv);
      gemmaLog('[LiteRtLmFfi] Generation cancelled');
    }
  }

  /// Legacy: cancel on the implicit [_legacyHandle] conversation.
  void cancelGeneration() {
    _legacyHandle?.cancelGeneration();
  }

  /// Delete a conversation pointer. Called by
  /// [LiteRtLmConversationHandle.close].
  void _deleteConversation(Pointer<LiteRtLmConversation> conv) {
    if (_bindings != null) {
      _bindings!.litert_lm_conversation_delete(conv);
      gemmaLog('[LiteRtLmFfi] Conversation closed');
    }
  }

  /// Legacy: close the implicit [_legacyHandle] conversation.
  void closeConversation() {
    _legacyHandle?.close();
    _legacyHandle = null;
  }

  /// Shutdown the engine and release all resources. Closes every live
  /// conversation handle first (legacy + any opened directly).
  void shutdown() {
    // Copy because close() mutates _handles.
    for (final h in _handles.toList()) {
      h.close();
    }
    _handles.clear();
    _legacyHandle = null;

    // Tear down the shared virtual-session conversation too.
    final vc = _virtualConv;
    if (vc != null) {
      _deleteConversation(vc);
      _virtualConv = null;
      _virtualActiveToken = null;
    }

    if (_engine != null && _engine != nullptr && _bindings != null) {
      _bindings!.litert_lm_engine_delete(_engine!);
      _engine = null;
      gemmaLog('[LiteRtLmFfi] Engine deleted');
    }

    _isInitialized = false;
    _backend = null;
  }

  /// Get session metrics from the given conversation including token usage.
  /// Returns empty SessionMetrics if benchmark unavailable.
  SessionMetrics _getMetricsOn(Pointer<LiteRtLmConversation> conv) {
    if (_bindings == null) {
      return SessionMetrics();
    }

    final benchmarkInfo = _bindings!.litert_lm_conversation_get_benchmark_info(
      conv,
    );
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
              benchmarkInfo,
              i,
            );
      }

      for (var i = 0; i < numDecodeTurns; i++) {
        outputTokens += _bindings!
            .litert_lm_benchmark_info_get_decode_token_count_at(
              benchmarkInfo,
              i,
            );
      }

      // Get timing info if available
      final timeToFirstToken = _bindings!
          .litert_lm_benchmark_info_get_time_to_first_token(benchmarkInfo);
      final initTime = _bindings!
          .litert_lm_benchmark_info_get_total_init_time_in_second(
            benchmarkInfo,
          );

      // Calculate average tokens per second from last decode turn if available
      double? tokensPerSecond;
      if (numDecodeTurns > 0) {
        tokensPerSecond = _bindings!
            .litert_lm_benchmark_info_get_decode_tokens_per_sec_at(
              benchmarkInfo,
              numDecodeTurns - 1,
            );
        if (tokensPerSecond <= 0) tokensPerSecond = null;
      }

      // Cleanup benchmark info
      _bindings!.litert_lm_benchmark_info_delete(benchmarkInfo);

      return SessionMetrics(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: inputTokens + outputTokens,
        timeToFirstTokenMs: timeToFirstToken > 0
            ? timeToFirstToken * 1000
            : null,
        tokensPerSecond: tokensPerSecond,
        initTimeMs: initTime > 0 ? initTime * 1000 : null,
      );
    } catch (e) {
      gemmaLog('[LiteRtLmFfiClient] Error getting metrics: $e');
      _bindings!.litert_lm_benchmark_info_delete(benchmarkInfo);
      return SessionMetrics();
    }
  }

  /// Legacy: metrics for the implicit [_legacyHandle] conversation.
  SessionMetrics getSessionMetrics() {
    final h = _legacyHandle;
    if (h == null) return SessionMetrics();
    return h.getSessionMetrics();
  }

  void _assertInitialized() {
    if (!_isInitialized || _engine == null || _engine == nullptr) {
      throw StateError('Engine not initialized. Call initialize() first.');
    }
  }

  void _assertConversation() {
    if (_legacyHandle == null || _legacyHandle!.isClosed) {
      throw StateError('No conversation. Call createConversation() first.');
    }
  }
}
