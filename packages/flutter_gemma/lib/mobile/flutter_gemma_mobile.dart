import 'dart:async';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // MethodChannel — used by file_system_manager.dart part
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_downloader/background_downloader.dart';

import '../flutter_gemma.dart';
import '../core/di/service_registry.dart';
import '../core/domain/model_source.dart';
import '../core/services/model_repository.dart' as repo;
import '../core/model_management/constants/preferences_keys.dart';
import '../core/utils/file_name_utils.dart';
import '../core/registry/engine_registry.dart';
import '../core/registry/embedding_registry.dart';
import '../core/registry/embedding_backend_provider.dart';
import '../core/registry/runtime_config.dart';
import '../core/model_management/model_specs.dart';
// Re-export the spec value types so existing importers of this library (tests,
// example, and any external code that imported the mobile lib directly) keep
// seeing InferenceModelSpec/EmbeddingModelSpec/etc. — they used to be `part`s
// here, now they live in model_specs.dart. Safe for wasm: this library is only
// on the io graph (web uses the conditional default stub).
export '../core/model_management/model_specs.dart';

// New unified model management system. The spec/exception value types live in
// the dart:io-free `model_specs.dart` library (extracted for dart2wasm/web
// compat); the implementation parts below stay here (they use dart:io).
part '../core/model_management/utils/file_system_manager.dart';
part '../core/model_management/utils/resume_checker.dart';
part '../core/model_management/managers/mobile_model_manager.dart';

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
        'No active inference model set. Use `FlutterGemma.installModel()` or `modelManager.setActiveModel()` to set a model first',
      );
    }

    // Check if singleton exists and matches the active model
    if (_initCompleter != null &&
        _initializedModel != null &&
        _lastActiveInferenceSpec != null) {
      final currentSpec = _lastActiveInferenceSpec!;
      final requestedSpec = activeModel as InferenceModelSpec;

      if (currentSpec.name != requestedSpec.name) {
        // Active model changed - close old model and create new one
        gemmaLog(
          '⚠️  Active model changed: ${currentSpec.name} → ${requestedSpec.name}',
        );
        gemmaLog('🔄 Closing old model and creating new one...');
        await _initializedModel?.close();
        // close-listener will reset _initializedModel and _initCompleter
        _lastActiveInferenceSpec = null;
      } else {
        // Same model - return existing singleton
        gemmaLog(
          'ℹ️  Reusing existing model instance for ${requestedSpec.name}',
        );
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
          'Active model is no longer installed. Use the `modelManager` to load the model first',
        ),
      );
      return completer.future;
    }

    // Get the actual model file path through unified system
    final modelFilePaths = await manager.getModelFilePaths(activeModel);
    if (modelFilePaths == null || modelFilePaths.isEmpty) {
      completer.completeError(
        Exception(
          'Model file paths not found. Use the `modelManager` to load the model first',
        ),
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

    gemmaLog('Using unified model file: $modelPath');

    try {
      // Engine selection routes ENTIRELY through [EngineRegistry] (probe-chain).
      // Core registers NO default engine: both MediaPipe (.task/.bin, from
      // flutter_gemma_mediapipe) and LiteRT-LM (.litertlm, from
      // flutter_gemma_litertlm) are fully opt-in via
      // FlutterGemma.initialize(inferenceEngines: [...]). Core only resolves the
      // model path (preamble above) + owns the singleton lifecycle centrally
      // (track + reset on close); the selected engine builds the model.

      final spec = activeModel as InferenceModelSpec;
      final config = RuntimeConfig(
        maxTokens: maxTokens,
        modelPath: modelPath,
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
        _initCompleter = null;
        _lastActiveInferenceSpec = null;
      });

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

      // Check if singleton exists and matches the active model
      if (_initEmbeddingCompleter != null &&
          _initializedEmbeddingModel != null &&
          _lastActiveEmbeddingSpec != null) {
        final currentSpec = _lastActiveEmbeddingSpec!;
        final requestedSpec = activeModel as EmbeddingModelSpec;

        if (currentSpec.name != requestedSpec.name) {
          // Active model changed - close old model and create new one
          gemmaLog(
            '⚠️  Active embedding model changed: ${currentSpec.name} → ${requestedSpec.name}',
          );
          gemmaLog('🔄 Closing old embedding model and creating new one...');
          await _initializedEmbeddingModel?.close();
          // close-listener will reset _initializedEmbeddingModel and _initEmbeddingCompleter
          _lastActiveEmbeddingSpec = null;
        } else {
          // Same model - return existing singleton
          gemmaLog(
            'ℹ️  Reusing existing embedding model instance for ${requestedSpec.name}',
          );
          return _initEmbeddingCompleter!.future;
        }
      }

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      gemmaLog(
        'Using active embedding model: $modelPath, tokenizer: $tokenizerPath',
      );
    } else {
      // Legacy API with explicit paths - check if singleton exists
      if (_initEmbeddingCompleter case Completer<EmbeddingModel> completer) {
        gemmaLog('ℹ️  Reusing existing embedding model instance (Legacy API)');
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
            'Active embedding model is no longer installed. Use the `modelManager` to load the model first',
          ),
        );
        return completer.future;
      }
    }

    try {
      // The LiteRT embedding runtime moved to flutter_gemma_embeddings; core
      // resolves paths (preamble above) + owns the singleton lifecycle, then
      // dispatches construction through the EmbeddingRegistry. The backend
      // reads ONLY config.modelPath/config.tokenizerPath — it ignores the spec
      // arg for path resolution (see LiteRtEmbeddingBackend.createModel).
      final activeSpec =
          activeModel as EmbeddingModelSpec?; // null on legacy explicit-paths
      final EmbeddingBackendProvider? backend = activeSpec != null
          ? EmbeddingRegistry.instance.findFor(activeSpec)
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
      // passed by the legacy API). maxTokens is unused by embeddings.
      final embConfig = RuntimeConfig(
        maxTokens: 0,
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        preferredBackend: preferredBackend,
      );
      // The backend's createModel(spec, config) signature requires a non-null
      // spec, but it resolves paths exclusively from config. On the legacy
      // explicit-paths path there is no active spec, so synthesize one from the
      // resolved file paths (FileSource, mobile/desktop only — web swaps in its
      // own plugin) purely to satisfy the signature.
      final specForBackend =
          activeSpec ??
          EmbeddingModelSpec(
            name: 'legacy:${path.basename(modelPath)}',
            modelSource: ModelSource.file(modelPath),
            tokenizerSource: ModelSource.file(tokenizerPath),
          );
      final model = await backend.createModel(specForBackend, embConfig);

      // Core owns the singleton lifecycle: track it + reset on close. The
      // package-built model fires this via CloseNotifier (addCloseListener).
      _initializedEmbeddingModel = model;
      model.addCloseListener(() {
        _initializedEmbeddingModel = null;
        _initEmbeddingCompleter = null;
        _lastActiveEmbeddingSpec = null;
      });

      // Save the spec that was used to create this model (Modern API path only)
      if (activeSpec != null) {
        _lastActiveEmbeddingSpec = activeSpec;
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
    // Generate embedding for content first
    if (initializedEmbeddingModel == null) {
      throw StateError(
        'No embedding model is active. addDocument(content:) and '
        'searchSimilar(query:) auto-embed text, which requires an embedding '
        'model. Install and activate one with FlutterGemma.installEmbedder(...) '
        '(or modelManager.setActiveModel) before calling these methods — or '
        'pass a precomputed vector to addDocumentWithEmbedding(embedding:).',
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
        'No embedding model is active. addDocument(content:) and '
        'searchSimilar(query:) auto-embed text, which requires an embedding '
        'model. Install and activate one with FlutterGemma.installEmbedder(...) '
        '(or modelManager.setActiveModel) before calling these methods — or '
        'pass a precomputed vector to addDocumentWithEmbedding(embedding:).',
      );
    }
    final queryEmbedding = await initializedEmbeddingModel!.generateEmbedding(
      query,
    );

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
