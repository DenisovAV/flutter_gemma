import 'dart:async';
import 'package:flutter_gemma/core/utils/gemma_log.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/registry/engine_registry.dart';
import 'package:flutter_gemma/core/registry/embedding_registry.dart';
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'package:flutter_gemma/core/model_management/managers/web_model_manager.dart';

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
        gemmaLog(
          'Warning: Image support is not yet implemented for web platform',
        );
      }
    }

    // A cached singleton may exist from a prior createModel call. Core no longer
    // imports any concrete web inference-model type (the MediaPipe web model
    // moved to flutter_gemma_mediapipe; LiteRT-LM's lives in
    // flutter_gemma_litertlm), so it can't introspect the model's params —
    // any existing model is always closed + replaced.
    if (_initializedModel != null) {
      if (kDebugMode) {
        gemmaLog(
          '[FlutterGemmaWeb] Replacing existing model, closing it first',
        );
      }
      await _initializedModel!.close();
      _initializedModel = null;
    }

    // Engine selection routes through [EngineRegistry] (probe-chain), mirroring
    // the mobile/desktop refactor: .task → MediaPipe, .litertlm → LiteRT-LM.
    // Both web engines now live in their own packages (flutter_gemma_mediapipe /
    // flutter_gemma_litertlm), supplied via
    // FlutterGemma.initialize(inferenceEngines: ...). Web registers NO default;
    // each engine builds its own WebModelSourceResolver internally. Web has no
    // resolved file path/cache dir (paths are lazy via the resolver), so the
    // RuntimeConfig's modelPath is empty.

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

    // Core owns the singleton lifecycle: track it + reset on close. The
    // package-built model fires this via CloseNotifier (addCloseListener).
    _initializedModel = model;
    model.addCloseListener(() {
      _initializedModel = null;
    });
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
          'No active embedding model set. Use `FlutterGemma.installEmbedder()` or `modelManager.setActiveModel()` to set a model first',
        );
      }

      // Get the actual model file paths through unified system
      final modelFilePaths = await manager.getModelFilePaths(activeModel);
      if (modelFilePaths == null || modelFilePaths.isEmpty) {
        throw StateError(
          'Embedding model file paths not found. Use the `modelManager` to load the model first',
        );
      }

      // Extract model and tokenizer paths from spec
      final activeModelPath =
          modelFilePaths[PreferencesKeys.embeddingModelFile];
      final activeTokenizerPath =
          modelFilePaths[PreferencesKeys.embeddingTokenizerFile];

      if (activeModelPath == null || activeTokenizerPath == null) {
        throw StateError(
          'Could not find model or tokenizer path in active embedding model',
        );
      }

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      if (kDebugMode) {
        gemmaLog(
          'Using active embedding model: $modelPath, tokenizer: $tokenizerPath',
        );
      }
    }

    // Check if model already exists with different parameters. The LiteRT.js
    // embedding runtime now lives in flutter_gemma_embeddings, so core can no
    // longer downcast to the package's WebEmbeddingModel to read its paths —
    // it compares against the last resolved paths it cached itself.
    if (_initializedEmbeddingModel != null) {
      final p = _lastEmbeddingPaths;
      final modelChanged =
          p == null ||
          p.modelPath != modelPath ||
          p.tokenizerPath != tokenizerPath;

      if (modelChanged) {
        if (kDebugMode) {
          gemmaLog(
            '[FlutterGemmaWeb] Embedding model paths changed, closing existing model',
          );
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
    await ServiceRegistry.instance.vectorStoreRepository.initialize(
      databasePath,
    );
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
    final queryEmbedding = await _initializedEmbeddingModel!.generateEmbedding(
      query,
    );
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
