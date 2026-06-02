import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/registry/engine_registry.dart';
import 'package:flutter_gemma/core/registry/default_engines.dart';
import 'package:flutter_gemma/core/registry/embedding_registry.dart';
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/parsing/sdk_response_parser.dart';
import 'package:flutter_gemma/core/parsing/sdk_text_extractor.dart';
// Conditional import: same pattern WebDownloadService uses so the opfsService
// field type matches statically (both sides of the resolver agree on the type).
import 'package:flutter_gemma/core/infrastructure/web_opfs_interop_stub.dart'
    if (dart.library.js_interop) 'package:flutter_gemma/core/infrastructure/web_opfs_service.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_download_service.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'litert_lm_web.dart';
import 'llm_inference_web.dart';
import 'web_image_format.dart';

part '../core/model_management/managers/web_model_manager.dart';
part 'web_model_source.dart';
part 'litert_lm_web_inference.dart';

/// Base class for prompt parts (text, image, audio)
abstract class PromptPart {}

/// Text prompt part
class TextPromptPart extends PromptPart {
  final String text;
  TextPromptPart(this.text);
}

/// Image prompt part with data URL
class ImagePromptPart extends PromptPart {
  final String dataUrl;
  ImagePromptPart(this.dataUrl);

  /// Create ImagePromptPart from Uint8List bytes
  factory ImagePromptPart.fromBytes(Uint8List bytes) {
    final base64String = base64Encode(bytes);
    final mimeType = detectImageMimeType(bytes);
    final dataUrl = 'data:$mimeType;base64,$base64String';
    return ImagePromptPart(dataUrl);
  }
}

/// Audio prompt part with raw audio bytes
/// For Gemma 3n E4B models - supports PCM audio (16kHz, 16-bit, mono)
class AudioPromptPart extends PromptPart {
  final Uint8List audioBytes;
  AudioPromptPart(this.audioBytes);
}

class FlutterGemmaWeb extends FlutterGemmaPlugin {
  FlutterGemmaWeb();

  static void registerWith(Registrar registrar) {
    FlutterGemmaPlugin.instance = FlutterGemmaWeb();
  }

  // WebModelManager singleton
  static WebModelManager? _webManager;

  @override
  ModelFileManager get modelManager {
    // Use WebModelManager
    _webManager ??= WebModelManager();
    return _webManager!;
  }

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  EmbeddingModel? get initializedEmbeddingModel => _initializedEmbeddingModel;

  InferenceModel? _initializedModel;
  EmbeddingModel? _initializedEmbeddingModel;

  /// One-shot guard for registering CORE's web default engines (MediaPipe +
  /// web LiteRT-LM, both of which live in core until extract #4). Must NOT gate
  /// on `EngineRegistry.registered.isEmpty`: a consumer that passes ANY engine
  /// via `FlutterGemma.initialize(inferenceEngines: ...)` (e.g. the native
  /// `LiteRtLmEngine`, whose web export is a no-op stub) would make the registry
  /// non-empty and suppress core's defaults entirely. This per-instance flag
  /// registers the core web defaults exactly once, regardless of what the
  /// consumer opted into.
  bool _webDefaultsRegistered = false;

  /// Last resolved embedding paths — replaces the previous package-type
  /// downcast (`_initializedEmbeddingModel as WebEmbeddingModel`) now that the
  /// LiteRT.js embedding runtime lives in flutter_gemma_embeddings. Mirrors the
  /// desktop `_lastInferenceParams` pattern: core owns lifecycle + change
  /// detection without depending on the package's concrete model type.
  ({String? modelPath, String? tokenizerPath})? _lastEmbeddingPaths;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false, // Enabling image support
    bool supportAudio = false, // Enabling audio support (Gemma 3n E4B)
    bool? enableSpeculativeDecoding, // Ignored on web (MediaPipe path).
    int? maxConcurrentSessions,
  }) async {
    // TODO: Implement multimodal support for web
    if (supportImage || maxNumImages != null) {
      if (kDebugMode) {
        debugPrint(
            'Warning: Image support is not yet implemented for web platform');
      }
    }

    // Check if model already exists with different parameters. Two web engine
    // types coexist now (MediaPipe `.task` and LiteRT-LM `.litertlm`), so the
    // cached singleton can be either — type-check, then compare params.
    if (_initializedModel != null) {
      final existing = _initializedModel!;
      bool parametersChanged;
      if (existing is WebInferenceModel) {
        parametersChanged = existing.modelType != modelType ||
            existing.fileType != fileType ||
            existing.maxTokens != maxTokens ||
            existing.supportImage != supportImage ||
            existing.supportAudio != supportAudio ||
            (existing.maxNumImages ?? 0) != (maxNumImages ?? 0);
      } else if (existing is LiteRtLmWebInferenceModel) {
        parametersChanged = existing.modelType != modelType ||
            existing.fileType != fileType ||
            existing.maxTokens != maxTokens;
      } else {
        // Unknown engine type — always replace.
        parametersChanged = true;
      }
      if (parametersChanged) {
        if (kDebugMode) {
          debugPrint(
              '[FlutterGemmaWeb] Model parameters changed, closing existing model');
        }
        await existing.close();
        _initializedModel = null;
      }
    }

    if (_initializedModel != null) {
      return _initializedModel!;
    }

    // Engine selection routes through [EngineRegistry] (probe-chain), mirroring
    // the mobile/desktop refactor: .task → MediaPipe (WebInferenceModel),
    // .litertlm → LiteRT-LM JS via @litert-lm/core (LiteRtLmWebInferenceModel).
    // Both share one [WebModelSourceResolver] — the storage-mode branch
    // (Blob URL vs OPFS ReadableStream) lives there, not here. Web has no
    // resolved file path/cache dir (paths are lazy via the resolver), so the
    // build closures ignore `modelPath`/`cacheDir`.
    final webManager = modelManager as WebModelManager;
    final sourceResolver = WebModelSourceResolver(webManager);

    // These build closures are registered ONCE into the global EngineRegistry
    // (lazy), so they must read EXCLUSIVELY from their (spec, config) params —
    // never the enclosing call's locals, which would go stale on the 2nd+
    // createModel call. (`sourceResolver` is fine to capture: it's rebuilt from
    // the same webManager every call and carries no per-call model params.)
    Future<InferenceModel> buildLiteRtLm(InferenceModelSpec spec,
        RuntimeConfig config, String _, String? __) async {
      return _initializedModel = LiteRtLmWebInferenceModel(
        modelType: spec.modelType,
        maxTokens: config.maxTokens,
        sourceResolver: sourceResolver,
        maxConcurrentSessions: config.maxConcurrentSessions,
        onClose: () {
          _initializedModel = null;
        },
      );
    }

    Future<InferenceModel> buildMediaPipe(InferenceModelSpec spec,
        RuntimeConfig config, String _, String? __) async {
      return _initializedModel = WebInferenceModel(
        modelType: spec.modelType,
        fileType: spec.fileType,
        maxTokens: config.maxTokens,
        loraRanks: config.loraRanks,
        sourceResolver: sourceResolver,
        supportImage: config.supportImage, // Passing the flag
        supportAudio: config.supportAudio, // Passing the audio flag
        maxNumImages: config.maxNumImages,
        maxConcurrentSessions: config.maxConcurrentSessions,
        onClose: () {
          _initializedModel = null;
        },
      );
    }

    if (!_webDefaultsRegistered) {
      _webDefaultsRegistered = true;
      EngineRegistry.instance.registerAll([
        DefaultMediaPipeEngine(buildMediaPipe),
        DefaultLiteRtLmEngine(buildLiteRtLm),
      ]);
    }

    // Web selection has always been by `fileType` alone; build a minimal spec
    // carrying it for the probe (web does not require an active model to be set
    // before createModel, so we don't depend on webManager.activeInferenceModel).
    final spec = InferenceModelSpec(
      name: 'web-active',
      modelSource: AssetSource('models/active.bin'),
      modelType: modelType,
      fileType: fileType,
    );
    final config = RuntimeConfig(
      maxTokens: maxTokens,
      modelPath: '',
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
    final model = await engine.createModel(spec, config);
    return model;
  }

  // === EmbeddingModel Methods - Web Implementation ===

  @override
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Modern API: Use active embedding model if paths not provided
    if (modelPath == null || tokenizerPath == null) {
      final manager = modelManager as WebModelManager;
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

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      if (kDebugMode) {
        debugPrint(
            'Using active embedding model: $modelPath, tokenizer: $tokenizerPath');
      }
    }

    // Check if model already exists with different parameters. The LiteRT.js
    // embedding runtime now lives in flutter_gemma_embeddings, so core can no
    // longer downcast to the package's WebEmbeddingModel to read its paths —
    // it compares against the last resolved paths it cached itself.
    if (_initializedEmbeddingModel != null) {
      final p = _lastEmbeddingPaths;
      final modelChanged = p == null ||
          p.modelPath != modelPath ||
          p.tokenizerPath != tokenizerPath;

      if (modelChanged) {
        if (kDebugMode) {
          debugPrint(
              '[FlutterGemmaWeb] Embedding model paths changed, closing existing model');
        }
        await _initializedEmbeddingModel?.close();
        _initializedEmbeddingModel = null;
        _lastEmbeddingPaths = null;
      }
    }

    if (_initializedEmbeddingModel != null) {
      return _initializedEmbeddingModel!;
    }

    // The LiteRT.js embedding runtime moved to flutter_gemma_embeddings; core
    // resolves paths (preamble above) + owns the singleton lifecycle, then
    // dispatches construction through the EmbeddingRegistry. The backend reads
    // ONLY config.modelPath/config.tokenizerPath — it ignores the spec for path
    // resolution. Web selects by the sole registered backend (WebGPU LiteRT.js).
    final activeEmb = (modelManager as WebModelManager).activeEmbeddingModel;
    final EmbeddingBackendProvider? backend = activeEmb is EmbeddingModelSpec
        ? EmbeddingRegistry.instance.findFor(activeEmb)
        : (EmbeddingRegistry.instance.registered.isNotEmpty
            ? EmbeddingRegistry.instance.registered.first
            : null);
    if (backend == null) {
      throw StateError(
        'No embedding backend registered. Add flutter_gemma_embeddings to '
        'pubspec.yaml and pass it in embeddingBackends: of '
        'FlutterGemma.initialize(...). Registered backends: '
        '${EmbeddingRegistry.instance.registered.map((b) => b.name).join(", ")}.',
      );
    }
    // modelPath/tokenizerPath are non-null here (resolved in the preamble or
    // passed by the caller). preferredBackend is ignored on web (LiteRT.js uses
    // WebGPU when available); maxTokens is unused by embeddings.
    final embConfig = RuntimeConfig(
      maxTokens: 0,
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      preferredBackend: preferredBackend,
    );
    // The backend's createModel(spec, config) requires a non-null spec but
    // resolves paths exclusively from config; synthesize one from the resolved
    // file paths when there's no active EmbeddingModelSpec.
    final model = await backend.createModel(
      activeEmb is EmbeddingModelSpec
          ? activeEmb
          : EmbeddingModelSpec(
              name: 'web-active-embedding',
              modelSource: ModelSource.file(modelPath),
              tokenizerSource: ModelSource.file(tokenizerPath),
            ),
      embConfig,
    );
    _initializedEmbeddingModel = model;
    _lastEmbeddingPaths = (modelPath: modelPath, tokenizerPath: tokenizerPath);
    model.addCloseListener(() {
      _initializedEmbeddingModel = null;
      _lastEmbeddingPaths = null;
    });
    return model;
  }

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
    if (_initializedEmbeddingModel == null) {
      throw StateError(
        'No embedding model is active. addDocument(content:) and '
        'searchSimilar(query:) auto-embed text, which requires an embedding '
        'model. Install and activate one with FlutterGemma.installEmbedder(...) '
        '(or modelManager.setActiveModel) before calling these methods — or '
        'pass a precomputed vector to addDocumentWithEmbedding(embedding:).',
      );
    }

    // Generate embedding and add document
    final embedding = await _initializedEmbeddingModel!.generateEmbedding(
      content,
      taskType: TaskType.retrievalDocument,
    );
    await ServiceRegistry.instance.vectorStoreRepository.addDocument(
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
    if (_initializedEmbeddingModel == null) {
      throw StateError(
        'No embedding model is active. addDocument(content:) and '
        'searchSimilar(query:) auto-embed text, which requires an embedding '
        'model. Install and activate one with FlutterGemma.installEmbedder(...) '
        '(or modelManager.setActiveModel) before calling these methods — or '
        'pass a precomputed vector to addDocumentWithEmbedding(embedding:).',
      );
    }

    // Generate query embedding and search
    final queryEmbedding =
        await _initializedEmbeddingModel!.generateEmbedding(query);
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

class WebInferenceModel extends InferenceModel with CloseNotifier {
  final VoidCallback onClose;
  bool _isClosed = false;
  @override
  final int maxTokens;

  final ModelType modelType;
  @override
  final ModelFileType fileType;
  @override
  PreferredBackend? get activeBackend => null;
  final List<int>? loraRanks;
  final WebModelSourceResolver sourceResolver;
  final bool supportImage; // Enabling image support
  final bool supportAudio; // Enabling audio support (Gemma 3n E4B)
  final int? maxNumImages;
  Completer<InferenceModelSession>? _initCompleter;
  @override
  InferenceModelSession? session;

  WebInferenceModel({
    required this.modelType,
    this.fileType = ModelFileType.task,
    required this.onClose,
    required this.maxTokens,
    this.loraRanks,
    required this.sourceResolver,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxNumImages,
    this.maxConcurrentSessions,
  });

  /// Cap on concurrent [openSession] sessions; null = unlimited. Accepted
  /// for API symmetry. The MediaPipe web `.task` path doesn't support
  /// concurrent sessions yet (openSession inherits the interface's
  /// UnsupportedError), so this is currently informational.
  final int? maxConcurrentSessions;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Enabling vision modality support
    bool? enableAudioModality, // Enabling audio modality support (Gemma 3n E4B)
    String? systemInstruction,
    bool enableThinking = false, // Not supported on Web (MediaPipe)
    List<Tool> tools =
        const [], // Tools wired through chat.dart prompt; SDK tools_json N/A on web
  }) async {
    // Thinking mode not supported on Web (MediaPipe has no extraContext/channels API)
    if (enableThinking) {
      if (kDebugMode) {
        debugPrint(
            'Warning: enableThinking is not supported on Web (MediaPipe). '
            'Use Android or Desktop with .litertlm models for Gemma 4 thinking mode.');
      }
    }

    // TODO: Implement vision modality for web
    if (enableVisionModality == true) {
      if (kDebugMode) {
        debugPrint(
            'Warning: Vision modality is not yet implemented for web platform');
      }
    }

    // Audio modality is handled via supportAudio flag in the model
    if (enableAudioModality == true && !supportAudio) {
      if (kDebugMode) {
        debugPrint(
            'Warning: Audio modality requested but supportAudio is false');
      }
    }

    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      // Shared resolver handles activeModel lookup + storage-mode branch.
      // Used identically by LiteRtLmWebInferenceModel.
      final resolved = await sourceResolver.resolveActiveInferenceModel();

      final fileset = await FilesetResolver.forGenAiTasks(
              'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27/wasm'
                  .toJS)
          .toDart;

      // LoRA path comes from the resolver alongside the model source.
      final loraPathToUse = loraPath ?? resolved.loraPath;
      final hasLoraParams = loraPathToUse != null && loraRanks != null;

      // MediaPipe consumes either modelAssetPath (Blob URL string) or
      // modelAssetBuffer (ReadableStreamDefaultReader, for OPFS streaming).
      final baseOptions = switch (resolved.model) {
        BlobUrlModelSource(:final url) =>
          LlmInferenceBaseOptions(modelAssetPath: url),
        OpfsStreamModelSource() => LlmInferenceBaseOptions(
            modelAssetBuffer:
                await (resolved.model as OpfsStreamModelSource).openReader()),
      };

      final config = LlmInferenceOptions(
          baseOptions: baseOptions,
          maxTokens: maxTokens,
          randomSeed: randomSeed,
          topK: topK,
          temperature: temperature,
          topP: topP,
          supportedLoraRanks:
              !hasLoraParams ? null : Int32List.fromList(loraRanks!).toJS,
          loraPath: !hasLoraParams ? null : loraPathToUse,
          maxNumImages: supportImage ? (maxNumImages ?? 1) : null);

      final llmInference =
          await LlmInference.createFromOptions(fileset, config).toDart;

      session = WebModelSession(
        modelType: modelType,
        fileType: fileType,
        llmInference: llmInference,
        supportImage: supportImage, // Enabling image support
        supportAudio: supportAudio, // Enabling audio support
        systemInstruction: systemInstruction,
        onClose: onClose,
      );

      completer.complete(session);
      return completer.future;
    } catch (e, st) {
      _initCompleter = null;
      completer.completeError(e, st);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await session?.close();
    session = null;
    _initCompleter = null;
    onClose();
    fireCloseListeners();
  }
}

class WebModelSession extends InferenceModelSession {
  final ModelType modelType;
  final ModelFileType fileType;
  final LlmInference llmInference;
  final VoidCallback onClose;
  final bool supportImage; // Enabling image support
  final bool supportAudio; // Enabling audio support (Gemma 3n E4B)
  StreamController<String>? _controller;
  final List<PromptPart> _promptParts = [];

  final String? systemInstruction;
  bool _systemInstructionSent = false;

  WebModelSession({
    required this.llmInference,
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
    this.supportAudio = false,
    this.systemInstruction,
  });

  @override
  Future<int> sizeInTokens(String text) async {
    final size = llmInference.sizeInTokens(text.toJS);
    return size.toDartInt;
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    if (kDebugMode) {
      debugPrint(
          '🟢 WebModelSession.addQueryChunk() called - hasImage: ${message.hasImage}, hasAudio: ${message.hasAudio}, supportImage: $supportImage, supportAudio: $supportAudio');
    }

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

    // Add image parts first, then audio, then text last.
    if (message.hasImage) {
      if (!supportImage) {
        if (kDebugMode) {
          debugPrint('🔴 Model does not support images - throwing exception');
        }
        throw ArgumentError('This model does not support images');
      }

      final images = message.images.isNotEmpty
          ? message.images
          : (message.imageBytes != null
              ? [message.imageBytes!]
              : const <Uint8List>[]);
      for (final imageBytes in images) {
        if (kDebugMode) {
          debugPrint('🟢 Processing image: ${imageBytes.length} bytes');
        }
        final imagePart = ImagePromptPart.fromBytes(imageBytes);
        _promptParts.add(imagePart);
        if (kDebugMode) {
          debugPrint(
              '🟢 Added image part with dataUrl length: ${imagePart.dataUrl.length}');
        }
      }
    }

    // Handle audio processing for web (Gemma 3n E4B)
    if (message.hasAudio && message.audioBytes != null) {
      if (kDebugMode) {
        debugPrint('🎵 Processing audio: ${message.audioBytes!.length} bytes');
      }
      if (!supportAudio) {
        if (kDebugMode) {
          debugPrint('🔴 Model does not support audio - throwing exception');
        }
        throw ArgumentError('This model does not support audio');
      }
      // Add audio part
      final audioPart = AudioPromptPart(message.audioBytes!);
      _promptParts.add(audioPart);
      if (kDebugMode) {
        debugPrint(
            '🎵 Added audio part with ${message.audioBytes!.length} bytes');
      }
    }

    // Add text part last so multimodal turns keep image/audio context first.
    _promptParts.add(TextPromptPart(finalPrompt));
    if (kDebugMode) {
      debugPrint(
          '🟢 Added text part: ${finalPrompt.substring(0, math.min(100, finalPrompt.length))}...');
    }

    if (kDebugMode) {
      debugPrint('🟢 Total prompt parts: ${_promptParts.length}');
    }
  }

  /// Convert PromptParts to JavaScript array for MediaPipe
  JSAny _createPromptArray() {
    if (kDebugMode) {
      debugPrint(
          '🔧 _createPromptArray: Starting with ${_promptParts.length} prompt parts');
    }

    if (_promptParts.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '📝 _createPromptArray: Empty prompt parts, returning empty string');
      }
      return ''.toJS; // Empty string fallback
    }

    // If only text parts, join them
    if (_promptParts.every((part) => part is TextPromptPart)) {
      final fullText =
          _promptParts.cast<TextPromptPart>().map((part) => part.text).join('');
      if (kDebugMode) {
        debugPrint(
            '📝 _createPromptArray: All text parts, returning string of length ${fullText.length}');
        debugPrint(
            '📝 _createPromptArray: Text preview: ${fullText.substring(0, math.min(100, fullText.length))}...');
      }
      return fullText.toJS;
    }

    // Multimodal: create array of parts following MediaPipe documentation format
    if (kDebugMode) {
      debugPrint(
          '🎯 _createPromptArray: Multimodal mode - creating array with proper format');
    }

    final jsArray = <JSAny>[];

    // Add conversation start token
    jsArray.add('<ctrl99>user\n'.toJS);

    for (int i = 0; i < _promptParts.length; i++) {
      final part = _promptParts[i];

      if (part is TextPromptPart) {
        if (kDebugMode) {
          debugPrint(
              '📝 _createPromptArray: Adding text part: "${part.text.substring(0, math.min(50, part.text.length))}..."');
        }
        jsArray.add(part.text.toJS);
      } else if (part is ImagePromptPart) {
        if (kDebugMode) {
          debugPrint(
              '🖼️ _createPromptArray: Adding image part with data URL length: ${part.dataUrl.length}');
          debugPrint(
              '🖼️ _createPromptArray: Image data URL prefix: ${part.dataUrl.substring(0, math.min(50, part.dataUrl.length))}...');
        }

        // Create proper image object for MediaPipe
        final imageObj = <String, String>{'imageSource': part.dataUrl}.jsify();
        if (kDebugMode) {
          debugPrint(
              '🖼️ _createPromptArray: Created image object with jsify()');
        }
        jsArray.add(imageObj as JSAny);
      } else if (part is AudioPromptPart) {
        if (kDebugMode) {
          debugPrint(
              '🎵 _createPromptArray: Adding audio part with ${part.audioBytes.length} bytes');
        }

        // Create proper audio object for MediaPipe
        // Audio is passed as raw PCM bytes (16kHz, 16-bit, mono)
        final audioObj = <String, Object>{
          'audioSource': part.audioBytes.buffer.asUint8List()
        }.jsify();
        if (kDebugMode) {
          debugPrint(
              '🎵 _createPromptArray: Created audio object with jsify()');
        }
        jsArray.add(audioObj as JSAny);
      } else {
        if (kDebugMode) {
          debugPrint(
              '❌ _createPromptArray: Unsupported prompt part type: ${part.runtimeType}');
        }
        throw Exception('Unsupported prompt part type: $part');
      }
    }

    // Add conversation end and model start tokens
    jsArray.add('<ctrl100>\n<ctrl99>model\n'.toJS);

    if (kDebugMode) {
      debugPrint(
          '✅ _createPromptArray: Created JS array with ${jsArray.length} elements (including control tokens)');
      debugPrint('🎯 _createPromptArray: Array structure ready for MediaPipe');
    }

    return jsArray.toJS;
  }

  @override
  Future<String> getResponse() async {
    if (kDebugMode) {
      debugPrint('🚀 getResponse: Starting response generation');
    }

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        debugPrint(
            '🎯 getResponse: Prompt array type: ${promptArray.runtimeType}');
        debugPrint('🎯 getResponse: Is JSString? ${promptArray is JSString}');
      }

      String response;

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          debugPrint(
              '📝 getResponse: Using generateResponse for text-only prompt');
        }
        response =
            (await llmInference.generateResponse(promptArray, null).toDart)
                .toDart;
      } else {
        if (kDebugMode) {
          debugPrint(
              '🖼️ getResponse: Using generateResponseMultimodal for multimodal prompt');
        }
        response = (await llmInference
                .generateResponseMultimodal(promptArray, null)
                .toDart)
            .toDart;
      }

      if (kDebugMode) {
        debugPrint(
            '✅ getResponse: Successfully generated response of length ${response.length}');
        debugPrint(
            '✅ getResponse: Response preview: ${response.substring(0, math.min(100, response.length))}...');
      }

      // Don't add response back to promptParts - that's handled by InferenceChat
      return response;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ getResponse: Exception caught: $e');
        debugPrint('❌ getResponse: Stack trace: $stackTrace');
      }
      _promptParts.clear();
      rethrow;
    }
  }

  @override
  Stream<String> getResponseAsync() {
    if (kDebugMode) {
      debugPrint('🌊 getResponseAsync: Starting async response generation');
    }

    // Close previous controller to prevent leak if called again before completion
    _controller?.close();
    _controller = StreamController<String>();

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        debugPrint(
            '🎯 getResponseAsync: Prompt array type: ${promptArray.runtimeType}');
        debugPrint(
            '🎯 getResponseAsync: Is JSString? ${promptArray is JSString}');
      }

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          debugPrint(
              '📝 getResponseAsync: Using generateResponse for text-only prompt');
        }
        llmInference.generateResponse(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                debugPrint(
                    '📝 getResponseAsync: Received partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  debugPrint('✅ getResponseAsync: Text response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ getResponseAsync: Error in text callback: $e');
              }
              _controller?.addError(e);
            }
          }).toJS,
        );
      } else {
        if (kDebugMode) {
          debugPrint(
              '🖼️ getResponseAsync: Using generateResponseMultimodal for multimodal prompt');
        }
        llmInference.generateResponseMultimodal(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                debugPrint(
                    '🖼️ getResponseAsync: Received multimodal partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  debugPrint(
                      '✅ getResponseAsync: Multimodal response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                    '❌ getResponseAsync: Error in multimodal callback: $e');
              }
              _controller?.addError(e);
            }
          }).toJS,
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ getResponseAsync: Exception during setup: $e');
        debugPrint('❌ getResponseAsync: Stack trace: $stackTrace');
      }
      _controller?.addError(e);
    }

    return _controller!.stream;
  }

  @override
  Future<void> stopGeneration() async {
    try {
      llmInference.cancelProcessing();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebModelSession] cancelProcessing error: $e');
      }
    } finally {
      _controller?.close();
      _controller = null;
      _promptParts.clear();
    }
  }

  @override
  SessionMetrics getSessionMetrics() {
    // Web MediaPipe implementation doesn't expose detailed token metrics.
    // Users can estimate using sizeInTokens() before/after generation.
    return SessionMetrics();
  }

  @override
  Future<void> close() async {
    // Cleanup MediaPipe LlmInference WASM resources (important for hot restart)
    // This prevents memory leaks and "memory access out of bounds" errors
    // Note: MediaPipe's close() will also release any OPFS stream readers internally
    try {
      llmInference.close();
      if (kDebugMode) {
        debugPrint('[WebModelSession] Cleaned up LlmInference resources');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebModelSession] Warning: Error closing LlmInference: $e');
      }
    }

    _promptParts.clear();
    _controller?.close();
    _controller = null;
    onClose();
  }
}
