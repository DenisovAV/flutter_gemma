import 'package:flutter_gemma/core/extensions.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mutex/mutex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_downloader/background_downloader.dart';

import '../flutter_gemma.dart';
import '../core/di/service_registry.dart';
// Conditional imports: on web, swap FFI client + inference model for stubs that
// don't pull in dart:ffi (which can't be compiled to JS/Wasm). The web plugin
// (FlutterGemmaWeb) registers itself as FlutterGemmaPlugin.instance via
// registerWith() before any of this code can run, so the stubs' constructors
// (which throw UnsupportedError) are never reached on web.
import '../core/ffi/backend_preference.dart';
import '../core/ffi/litert_lm_client.dart'
    if (dart.library.js_interop) '../core/ffi/litert_lm_client_stub.dart';
import '../core/ffi/ffi_inference_model.dart'
    if (dart.library.js_interop) '../core/ffi/ffi_inference_model_stub.dart';
import '../core/litert/litert_embedding_model.dart'
    if (dart.library.js_interop) '../core/litert/litert_embedding_model_stub.dart';
import '../core/domain/model_source.dart';
import '../core/services/model_repository.dart' as repo;
import '../core/model_management/constants/preferences_keys.dart';
import '../core/utils/file_name_utils.dart';
import '../core/registry/engine_registry.dart';
import '../core/registry/default_engines.dart';
import '../core/registry/runtime_config.dart';

part 'flutter_gemma_mobile_inference_model.dart';

// New unified model management system
part '../core/model_management/types/model_spec.dart';
part '../core/model_management/types/inference_model_spec.dart';
part '../core/model_management/types/embedding_model_spec.dart';
part '../core/model_management/types/storage_info.dart';
part '../core/model_management/exceptions/model_exceptions.dart';
part '../core/model_management/utils/file_system_manager.dart';
part '../core/model_management/utils/resume_checker.dart';
part '../core/model_management/managers/mobile_model_manager.dart';

class MobileInferenceModelSession extends InferenceModelSession {
  final ModelType modelType;
  final ModelFileType fileType;
  final VoidCallback onClose;
  final bool supportImage;
  final bool supportAudio; // Enabling audio support (Gemma 3n E4B)
  bool _isClosed = false;

  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;
  StreamSubscription? _eventSubscription;

  final String? systemInstruction;
  bool _systemInstructionSent = false;

  bool get _isNativeSystemInstruction =>
      fileType == ModelFileType.litertlm &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  MobileInferenceModelSession({
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
    this.supportAudio = false,
    this.systemInstruction,
  });

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
          'Model is closed. Create a new instance to use it again');
    }
  }

  Future<void> _awaitLastResponse() async {
    if (_responseCompleter case Completer<void> completer) {
      await completer.future;
    }
  }

  @override
  Future<int> sizeInTokens(String text) => _platformService.sizeInTokens(text);

  @override
  Future<void> addQueryChunk(Message message) async {
    var messageToSend = message;
    if (message.isUser &&
        !_systemInstructionSent &&
        systemInstruction != null &&
        systemInstruction!.isNotEmpty &&
        !_isNativeSystemInstruction) {
      _systemInstructionSent = true;
      messageToSend = message.copyWith(
        text: '[System: ${systemInstruction!}]\n\n${message.text}',
      );
    }
    debugPrint(
        '[MobileSession.addQueryChunk] modelType=$modelType, fileType=$fileType, msgType=${message.type}');
    final finalPrompt = messageToSend.transformToChatPrompt(
        type: modelType, fileType: fileType);
    debugPrint(
        '[MobileSession.addQueryChunk] finalPrompt length=${finalPrompt.length}');
    if (message.hasImage && supportImage) {
      final images = message.images.isNotEmpty
          ? message.images
          : (message.imageBytes != null
              ? [message.imageBytes!]
              : const <Uint8List>[]);
      for (final image in images) {
        await _addImage(image);
      }
    }
    if (message.hasAudio && message.audioBytes != null && supportAudio) {
      await _addAudio(message.audioBytes!);
    }
    await _platformService.addQueryChunk(finalPrompt);
  }

  Future<void> _addImage(Uint8List imageBytes) async {
    _assertNotClosed();
    if (!supportImage) {
      throw ArgumentError('This model does not support images');
    }
    await _platformService.addImage(imageBytes);
  }

  Future<void> _addAudio(Uint8List audioBytes) async {
    _assertNotClosed();
    if (!supportAudio) {
      throw ArgumentError('This model does not support audio');
    }
    await _platformService.addAudio(audioBytes);
  }

  @override
  Future<String> getResponse({Message? message}) async {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      if (message != null) {
        await addQueryChunk(message);
      }
      return await _platformService.generateResponse();
    } finally {
      completer.complete();
    }
  }

  @override
  Stream<String> getResponseAsync({Message? message}) async* {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      final controller = _asyncResponseController = StreamController<String>();

      // Store subscription for proper cleanup
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        (event) {
          // Check if controller is still open before adding events
          if (!controller.isClosed) {
            if (event is Map && event.containsKey('sessionId')) {
              // Tagged event belongs to a concurrent openSession() session —
              // ignore it on the legacy singleton listener (it's demuxed by
              // MultiSessionMobileInferenceModelSession).
            } else if (event is Map &&
                event.containsKey('code') &&
                event['code'] == "ERROR") {
              controller.addError(Exception(
                  event['message'] ?? 'Unknown async error occurred'));
            } else if (event is Map && event.containsKey('partialResult')) {
              final partial = event['partialResult'] as String;
              controller.add(partial);
            } else {
              controller.addError(Exception('Unknown event type: $event'));
            }
          }
        },
        onError: (error, st) {
          if (!controller.isClosed) {
            controller.addError(error, st);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );

      if (message != null) {
        await addQueryChunk(message);
      }
      unawaited(_platformService.generateResponseAsync());

      yield* controller.stream;
    } finally {
      completer.complete();
      _asyncResponseController = null;
    }
  }

  @override
  Future<void> stopGeneration() async {
    try {
      await _platformService.stopGeneration();
    } catch (e) {
      if (e.toString().contains('stop_not_supported')) {
        throw PlatformException(
          code: 'stop_not_supported',
          message: 'Stop generation is not supported on this platform',
        );
      }
      rethrow;
    }
  }

  @override
  SessionMetrics getSessionMetrics() {
    // MediaPipe doesn't expose detailed token metrics via the current platform channel.
    // To get metrics on mobile, you would need to:
    // 1. Add a new platform method to fetch metrics from native side
    // 2. Or track tokens manually using sizeInTokens() before/after generation
    //
    // For now, return empty metrics. Users can estimate using:
    //   final inputTokens = await session.sizeInTokens(prompt);
    //   final outputTokens = await session.sizeInTokens(responseText);
    return SessionMetrics();
  }

  @override
  Future<void> close() async {
    _isClosed = true;

    // Cancel event subscription first to stop receiving events
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    // Try to stop generation if possible (ignore errors on unsupported platforms)
    try {
      await _platformService.stopGeneration();
    } on PlatformException catch (e) {
      // Ignore "not supported" errors, but rethrow others
      if (e.code != 'stop_not_supported') {
        if (kDebugMode) {
          debugPrint('Warning: Failed to stop generation: ${e.message}');
        }
      }
    } catch (e) {
      // Ignore other errors during cleanup
      if (kDebugMode) {
        debugPrint('Warning: Unexpected error during stop generation: $e');
      }
    }

    // Close controller after stopping subscription
    _asyncResponseController?.close();

    onClose();
    await _platformService.closeSession();
  }
}

/// A concurrent MediaPipe `.task` session opened via
/// [MobileInferenceModel.openSession]. Independent of the legacy singleton
/// [MobileInferenceModelSession]: it routes every call through the
/// session-scoped `*ForSession` pigeon methods keyed by [sessionId], so N of
/// these can be live at once (MediaPipe holds N real `LlmInferenceSession`).
///
/// Generation is serialized across all sessions by the model's shared
/// [_generationMutex] — concurrent contexts, serialized inference, identical
/// to the `.litertlm` FFI path. Because only one session generates at a time,
/// the single `flutter_gemma_stream` EventChannel is unambiguous; this session
/// demuxes by filtering events whose `sessionId` matches its own.
class MultiSessionMobileInferenceModelSession extends InferenceModelSession {
  final int sessionId;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;
  final String? systemInstruction;
  final Mutex generationMutex;
  final VoidCallback onClose;

  bool _isClosed = false;
  bool _systemInstructionSent = false;

  MultiSessionMobileInferenceModelSession({
    required this.sessionId,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required this.supportAudio,
    required this.generationMutex,
    required this.onClose,
    this.systemInstruction,
  });

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Session is closed');
    }
  }

  @override
  Future<int> sizeInTokens(String text) =>
      _platformService.sizeInTokensForSession(sessionId, text);

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();
    var messageToSend = message;
    if (message.isUser &&
        !_systemInstructionSent &&
        systemInstruction != null &&
        systemInstruction!.isNotEmpty) {
      _systemInstructionSent = true;
      messageToSend = message.copyWith(
        text: '[System: ${systemInstruction!}]\n\n${message.text}',
      );
    }
    final finalPrompt = messageToSend.transformToChatPrompt(
        type: modelType, fileType: fileType);
    if (message.hasImage && supportImage) {
      final images = message.images.isNotEmpty
          ? message.images
          : (message.imageBytes != null
              ? [message.imageBytes!]
              : const <Uint8List>[]);
      for (final image in images) {
        await _platformService.addImageToSession(sessionId, image);
      }
    }
    if (message.hasAudio && message.audioBytes != null && supportAudio) {
      await _platformService.addAudioToSession(sessionId, message.audioBytes!);
    }
    await _platformService.addQueryChunkToSession(sessionId, finalPrompt);
  }

  @override
  Future<String> getResponse({Message? message}) async {
    _assertNotClosed();
    if (message != null) await addQueryChunk(message);
    // Serialize generation across sessions (mobile can't afford parallel
    // generations; also keeps the shared event channel unambiguous).
    return generationMutex.protect(
      () => _platformService.generateResponseForSession(sessionId),
    );
  }

  @override
  Stream<String> getResponseAsync({Message? message}) {
    _assertNotClosed();

    // StreamController (not async*/yield*) so the mutex release is tied to the
    // controller lifecycle — it fires on done, error, AND consumer cancel /
    // abandon. With async*+yield* an abandoned stream would never run the
    // finally and would hold the generation mutex forever, deadlocking every
    // other session.
    final controller = StreamController<String>();
    StreamSubscription? subscription;
    var mutexHeld = false;
    var finished = false;

    Future<void> cleanup() async {
      if (finished) return;
      finished = true;
      await subscription?.cancel();
      if (mutexHeld) {
        mutexHeld = false;
        generationMutex.release();
      }
    }

    controller.onListen = () async {
      try {
        if (message != null) await addQueryChunk(message);
        await generationMutex.acquire();
        mutexHeld = true;
        subscription = eventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is! Map) return;
            // Only consume events tagged for THIS session.
            if (event['sessionId'] != sessionId) return;
            if (controller.isClosed) return;
            // Native emits generation errors as a TAGGED DATA event
            // {code: ERROR, sessionId, message} (not an EventChannel error,
            // which would be broadcast to every session and lose the id).
            if (event['code'] == 'ERROR') {
              controller.addError(Exception(
                  event['message'] ?? 'Unknown async error occurred'));
              cleanup();
              controller.close();
              return;
            }
            final partial = event['partialResult'] as String? ?? '';
            if (partial.isNotEmpty) controller.add(partial);
            // Tagged completion (native sends done:true with our sessionId
            // rather than closing the whole channel via endOfStream).
            if (event['done'] == true) {
              cleanup();
              controller.close();
            }
          },
          onError: (error, st) {
            if (!controller.isClosed) controller.addError(error, st);
            cleanup();
            if (!controller.isClosed) controller.close();
          },
        );
        unawaited(_platformService
            .generateResponseAsyncForSession(sessionId)
            .catchError((Object e, StackTrace st) {
          // A synchronous native failure (before any event) must surface and
          // release the mutex, not hang the controller.
          if (!controller.isClosed) controller.addError(e, st);
          cleanup();
          if (!controller.isClosed) controller.close();
        }));
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
        await cleanup();
        if (!controller.isClosed) await controller.close();
      }
    };

    // Consumer cancelled / abandoned the stream — release the mutex.
    controller.onCancel = () async {
      await cleanup();
    };

    return controller.stream;
  }

  @override
  Future<void> stopGeneration() async {
    await _platformService.stopGenerationForSession(sessionId);
  }

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    onClose();
    await _platformService.closeSessionId(sessionId);
  }
}

@visibleForTesting
const eventChannel = EventChannel('flutter_gemma_stream');

final _platformService = PlatformService();

class FlutterGemmaMobile extends FlutterGemmaPlugin {
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;
  InferenceModelSpec?
      _lastActiveInferenceSpec; // Track which spec was used to create _initializedModel

  Completer<EmbeddingModel>? _initEmbeddingCompleter;
  EmbeddingModel? _initializedEmbeddingModel;
  EmbeddingModelSpec?
      _lastActiveEmbeddingSpec; // Track which spec was used to create _initializedEmbeddingModel

  // Made public for example app integration
  late final MobileModelManager _unifiedManager = MobileModelManager();

  @override
  MobileModelManager get modelManager => _unifiedManager;

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  EmbeddingModel? get initializedEmbeddingModel => _initializedEmbeddingModel;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
    bool supportAudio = false, // Enabling audio support (Gemma 3n E4B)
    bool? enableSpeculativeDecoding,
    int? maxConcurrentSessions,
  }) async {
    // Check if model is ready through unified system
    final manager = _unifiedManager;
    final activeModel = manager.activeInferenceModel;

    // No active inference model - user must set one first
    if (activeModel == null) {
      throw StateError(
          'No active inference model set. Use `FlutterGemma.installModel()` or `modelManager.setActiveModel()` to set a model first');
    }

    // Check if singleton exists and matches the active model
    if (_initCompleter != null &&
        _initializedModel != null &&
        _lastActiveInferenceSpec != null) {
      final currentSpec = _lastActiveInferenceSpec!;
      final requestedSpec = activeModel as InferenceModelSpec;

      if (currentSpec.name != requestedSpec.name) {
        // Active model changed - close old model and create new one
        debugPrint(
            '⚠️  Active model changed: ${currentSpec.name} → ${requestedSpec.name}');
        debugPrint('🔄 Closing old model and creating new one...');
        await _initializedModel?.close();
        // onClose callback will reset _initializedModel and _initCompleter
        _lastActiveInferenceSpec = null;
      } else {
        // Same model - return existing singleton
        debugPrint(
            'ℹ️  Reusing existing model instance for ${requestedSpec.name}');
        return _initCompleter!.future;
      }
    }

    // If singleton doesn't exist or was just closed, create new one
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }

    final completer = _initCompleter = Completer<InferenceModel>();

    // Verify the active model is still installed
    final isModelInstalled = await manager.isModelInstalled(activeModel);
    if (!isModelInstalled) {
      completer.completeError(
        Exception(
            'Active model is no longer installed. Use the `modelManager` to load the model first'),
      );
      return completer.future;
    }

    // Get the actual model file path through unified system
    final modelFilePaths = await manager.getModelFilePaths(activeModel);
    if (modelFilePaths == null || modelFilePaths.isEmpty) {
      completer.completeError(
        Exception(
            'Model file paths not found. Use the `modelManager` to load the model first'),
      );
      return completer.future;
    }

    final modelPath = modelFilePaths.values.first;
    final modelFile = File(modelPath);

    if (!await modelFile.exists()) {
      completer.completeError(
        Exception('Model file not found at path: ${modelFile.path}'),
      );
      return completer.future;
    }

    debugPrint('Using unified model file: $modelPath');

    try {
      // Engine selection routes through [EngineRegistry] (probe-chain). The
      // default engines below wrap the existing construction arms unchanged;
      // `callBuild` threads the resolved `modelPath`/`cacheDir` so each arm
      // body stays byte-identical to the pre-registry switch. The instance
      // still owns construction + singleton state.

      // LiteRT-LM (.litertlm) build — the former FFI arm. Reads EXCLUSIVELY from
      // its (spec, config, mPath, cacheDir) params, NEVER the enclosing call's
      // locals: these build methods are registered ONCE into the global
      // EngineRegistry (lazy), so a captured local would go stale on the 2nd+
      // createModel call. The mobile-only guard is implicit (this plugin only
      // loads on iOS/Android), matching the previous Platform.isIOS||isAndroid
      // condition.
      Future<InferenceModel> buildLiteRtLm(InferenceModelSpec spec,
          RuntimeConfig config, String mPath, String? cacheDir) async {
        debugPrint(
            '[FlutterGemmaMobile] Using FFI path for .litertlm on ${Platform.operatingSystem}');
        final ffiPathSw = Stopwatch()..start();
        final resolvedCacheDir =
            cacheDir ?? (await getApplicationSupportDirectory()).path;
        debugPrint(
            '[FlutterGemmaMobile/perf] getApplicationSupportDirectory: ${ffiPathSw.elapsedMilliseconds}ms');
        // NPU on Android `.litertlm` restored to 0.13.x parity. The Kotlin
        // LiteRtLmEngine path was dropped in 0.14.0 (commit 81025da); this
        // routes the same `Backend::NPU` enum value through LiteRT-LM's C
        // API. A Qualcomm QNN / Google Tensor / MediaTek dispatch lib must
        // be present on the device — without one, engine_create fails with
        // a dispatch error from LiteRT-LM. iOS .litertlm: upstream LiteRT-LM
        // disables NPU via LITERT_DISABLE_NPU at build time; engine_create
        // returns a clean Backend::NPU not supported error.
        final beforeInit = ffiPathSw.elapsedMilliseconds;
        final ffiRuntime = await _initializeFfiInferenceRuntime(
          modelPath: mPath,
          preferredBackend: config.preferredBackend,
          maxTokens: config.maxTokens,
          cacheDir: resolvedCacheDir,
          enableVision: config.supportImage,
          maxNumImages: config.supportImage ? (config.maxNumImages ?? 1) : 0,
          enableAudio: config.supportAudio,
          enableSpeculativeDecoding: config.enableSpeculativeDecoding,
        );
        debugPrint(
            '[FlutterGemmaMobile/perf] ffiClient.initialize total: ${ffiPathSw.elapsedMilliseconds - beforeInit}ms');
        debugPrint(
            '[FlutterGemmaMobile/perf] FFI model creation total: ${ffiPathSw.elapsedMilliseconds}ms');

        return _initializedModel = FfiInferenceModel(
          ffiClient: ffiRuntime.client,
          maxTokens: config.maxTokens,
          modelType: spec.modelType,
          activeBackend: ffiRuntime.activeBackend,
          fileType: spec.fileType,
          supportImage: config.supportImage,
          supportAudio: config.supportAudio,
          maxConcurrentSessions: config.maxConcurrentSessions,
          onClose: () {
            _initializedModel = null;
            _initCompleter = null;
            _lastActiveInferenceSpec = null;
          },
        );
      }

      // MediaPipe (.task/.bin) build — the former MediaPipe arm. Reads only from
      // its params (see note above); `config.loraRanks` carries the per-call
      // LoRA ranks, `supportedLoraRanks` is a stable instance default.
      Future<InferenceModel> buildMediaPipe(InferenceModelSpec spec,
          RuntimeConfig config, String mPath, String? cacheDir) async {
        await _platformService.createModel(
          maxTokens: config.maxTokens,
          modelPath: mPath,
          loraRanks: config.loraRanks ?? supportedLoraRanks,
          preferredBackend: config.preferredBackend,
          maxNumImages: config.supportImage ? (config.maxNumImages ?? 1) : null,
          supportAudio: config.supportAudio ? true : null,
        );

        return _initializedModel = MobileInferenceModel(
          maxTokens: config.maxTokens,
          modelType: spec.modelType,
          fileType: spec.fileType,
          preferredBackend: config.preferredBackend,
          activeBackend: null,
          supportedLoraRanks: config.loraRanks ?? supportedLoraRanks,
          supportImage: config.supportImage,
          supportAudio: config.supportAudio,
          maxNumImages: config.maxNumImages,
          maxConcurrentSessions: config.maxConcurrentSessions,
          onClose: () {
            _initializedModel = null;
            _initCompleter = null;
            _lastActiveInferenceSpec = null;
          },
        );
      }

      if (EngineRegistry.instance.registered.isEmpty) {
        EngineRegistry.instance.registerAll([
          DefaultMediaPipeEngine(buildMediaPipe),
          DefaultLiteRtLmEngine(buildLiteRtLm),
        ]);
      }

      final spec = activeModel as InferenceModelSpec;
      final config = RuntimeConfig(
        maxTokens: maxTokens,
        preferredBackend: preferredBackend,
        supportImage: supportImage,
        supportAudio: supportAudio,
        maxNumImages: maxNumImages,
        enableSpeculativeDecoding: enableSpeculativeDecoding,
        maxConcurrentSessions: maxConcurrentSessions,
        loraRanks: loraRanks,
      );
      final engine = EngineRegistry.instance.findFor(spec);
      if (engine == null) {
        throw StateError(
          'No inference engine can handle this model (ModelFileType.${spec.fileType.name}). '
          'Add the engine package to pubspec.yaml and pass it in inferenceEngines: '
          'of FlutterGemma.initialize(...). Registered engines: '
          '${EngineRegistry.instance.registered.map((e) => e.name).join(", ")}.',
        );
      }
      final model = engine is DefaultLiteRtLmEngine
          ? await engine.callBuild(spec, config, modelPath, null)
          : await (engine as DefaultMediaPipeEngine)
              .callBuild(spec, config, modelPath, null);

      // Save the spec that was used to create this model
      _lastActiveInferenceSpec = spec;

      completer.complete(model);
      return model;
    } catch (e, st) {
      // FIX #170: Reset state to allow retry with different model
      _initCompleter = null;
      _initializedModel = null;
      _lastActiveInferenceSpec = null;
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  @override
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Modern API: Use active embedding model if paths not provided
    if (modelPath == null || tokenizerPath == null) {
      final manager = _unifiedManager;
      final activeModel = manager.activeEmbeddingModel;

      // No active embedding model - user must set one first
      if (activeModel == null) {
        throw StateError(
            'No active embedding model set. Use `FlutterGemma.installEmbedder()` or `modelManager.setActiveModel()` to set a model first');
      }

      // Get the actual model file paths through unified system
      final modelFilePaths = await manager.getModelFilePaths(activeModel);
      if (modelFilePaths == null || modelFilePaths.isEmpty) {
        throw StateError(
            'Embedding model file paths not found. Use the `modelManager` to load the model first');
      }

      // Extract model and tokenizer paths from spec
      final activeModelPath =
          modelFilePaths[PreferencesKeys.embeddingModelFile];
      final activeTokenizerPath =
          modelFilePaths[PreferencesKeys.embeddingTokenizerFile];

      if (activeModelPath == null || activeTokenizerPath == null) {
        throw StateError(
            'Could not find model or tokenizer path in active embedding model');
      }

      // Check if singleton exists and matches the active model
      if (_initEmbeddingCompleter != null &&
          _initializedEmbeddingModel != null &&
          _lastActiveEmbeddingSpec != null) {
        final currentSpec = _lastActiveEmbeddingSpec!;
        final requestedSpec = activeModel as EmbeddingModelSpec;

        if (currentSpec.name != requestedSpec.name) {
          // Active model changed - close old model and create new one
          debugPrint(
              '⚠️  Active embedding model changed: ${currentSpec.name} → ${requestedSpec.name}');
          debugPrint('🔄 Closing old embedding model and creating new one...');
          await _initializedEmbeddingModel?.close();
          // onClose callback will reset _initializedEmbeddingModel and _initEmbeddingCompleter
          _lastActiveEmbeddingSpec = null;
        } else {
          // Same model - return existing singleton
          debugPrint(
              'ℹ️  Reusing existing embedding model instance for ${requestedSpec.name}');
          return _initEmbeddingCompleter!.future;
        }
      }

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      debugPrint(
          'Using active embedding model: $modelPath, tokenizer: $tokenizerPath');
    } else {
      // Legacy API with explicit paths - check if singleton exists
      if (_initEmbeddingCompleter case Completer<EmbeddingModel> completer) {
        debugPrint(
            'ℹ️  Reusing existing embedding model instance (Legacy API)');
        return completer.future;
      }
    }

    final completer = _initEmbeddingCompleter = Completer<EmbeddingModel>();

    // Verify the active model is still installed (for Modern API path)
    final manager = _unifiedManager;
    final activeModel = manager.activeEmbeddingModel;

    if (activeModel != null) {
      final isModelInstalled = await manager.isModelInstalled(activeModel);
      if (!isModelInstalled) {
        completer.completeError(
          Exception(
              'Active embedding model is no longer installed. Use the `modelManager` to load the model first'),
        );
        return completer.future;
      }
    }

    try {
      // 0.15.2: native embedding paths (Android Kotlin + iOS Swift) are
      // replaced by the shared Dart-FFI + LiteRT path used on Desktop.
      // No platform-channel hop, single implementation across all native
      // platforms — see `LitertEmbeddingModel`.
      final model =
          _initializedEmbeddingModel = await LitertEmbeddingModel.create(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        onClose: () {
          _initializedEmbeddingModel = null;
          _initEmbeddingCompleter = null;
          _lastActiveEmbeddingSpec = null;
        },
      );

      // Save the spec that was used to create this model (Modern API path only)
      if (activeModel != null) {
        _lastActiveEmbeddingSpec = activeModel as EmbeddingModelSpec;
      }

      completer.complete(model);
      return model;
    } catch (e, st) {
      // FIX #170: Reset state to allow retry with different model
      _initEmbeddingCompleter = null;
      _initializedEmbeddingModel = null;
      _lastActiveEmbeddingSpec = null;
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  // === RAG Methods Implementation ===

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    await ServiceRegistry.instance.vectorStoreRepository
        .initialize(databasePath);
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    await ServiceRegistry.instance.vectorStoreRepository.addDocument(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadata,
    );
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    // Generate embedding for content first
    if (initializedEmbeddingModel == null) {
      throw StateError(
        'Auto-embedding requested but no EmbeddingBackendProvider is registered. '
        'Add `flutter_gemma_embeddings` to pubspec.yaml and pass '
        '`embeddingBackends: [LiteRtEmbeddingBackend()]` to FlutterGemma.initialize(...), '
        'or call addDocumentWithEmbedding(embedding:) with a precomputed vector.',
      );
    }
    final embedding = await initializedEmbeddingModel!.generateEmbedding(
      content,
      taskType: TaskType.retrievalDocument,
    );

    // Add document with computed embedding
    await addDocumentWithEmbedding(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadata,
    );
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
    Filter? filter,
  }) async {
    // Generate embedding for query
    if (initializedEmbeddingModel == null) {
      throw StateError(
        'Auto-embedding requested but no EmbeddingBackendProvider is registered. '
        'Add `flutter_gemma_embeddings` to pubspec.yaml and pass '
        '`embeddingBackends: [LiteRtEmbeddingBackend()]` to FlutterGemma.initialize(...), '
        'or call addDocumentWithEmbedding(embedding:) with a precomputed vector.',
      );
    }
    final queryEmbedding =
        await initializedEmbeddingModel!.generateEmbedding(query);

    // Search similar vectors
    return await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: topK,
      threshold: threshold,
      filter: filter,
    );
  }

  @override
  Future<VectorStoreStats> getVectorStoreStats() async {
    return await ServiceRegistry.instance.vectorStoreRepository.getStats();
  }

  @override
  Future<void> clearVectorStore() async {
    await ServiceRegistry.instance.vectorStoreRepository.clear();
  }

  @override
  bool get enableHnsw =>
      ServiceRegistry.instance.vectorStoreRepository.enableHnsw;

  @override
  set enableHnsw(bool value) {
    ServiceRegistry.instance.vectorStoreRepository.enableHnsw = value;
  }
}

Future<({LiteRtLmFfiClient client, PreferredBackend activeBackend})>
    _initializeFfiInferenceRuntime({
  required String modelPath,
  required PreferredBackend? preferredBackend,
  required int maxTokens,
  required String cacheDir,
  required bool enableVision,
  required int maxNumImages,
  required bool enableAudio,
  required bool? enableSpeculativeDecoding,
}) async {
  return initializeFfiRuntime(
    preferredBackend: preferredBackend,
    logTag: '[FlutterGemmaMobile]',
    createClient: LiteRtLmFfiClient.new,
    initializeClient: (client, backend) async {
      await client.initialize(
        modelPath: modelPath,
        backend: ffiBackendWireName(backend),
        maxTokens: maxTokens,
        cacheDir: cacheDir,
        enableVision: enableVision,
        maxNumImages: maxNumImages,
        enableAudio: enableAudio,
        enableSpeculativeDecoding: enableSpeculativeDecoding,
      );
    },
    shutdownClient: (client) => client.shutdown(),
  );
}
