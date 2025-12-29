import 'package:flutter_gemma/core/extensions.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:background_downloader/background_downloader.dart';

import '../flutter_gemma.dart';
import '../core/di/service_registry.dart';
import '../core/domain/model_source.dart';
import '../core/services/model_repository.dart' as repo;
import '../core/model_management/constants/preferences_keys.dart';
import '../core/utils/file_name_utils.dart';

part 'flutter_gemma_mobile_inference_model.dart';
part 'flutter_gemma_mobile_embedding_model.dart';

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
  bool _isClosed = false;

  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;
  StreamSubscription? _eventSubscription;

  MobileInferenceModelSession({
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
  });

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Model is closed. Create a new instance to use it again');
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
    debugPrint('[MobileSession.addQueryChunk] modelType=$modelType, fileType=$fileType, msgType=${message.type}');
    final finalPrompt = message.transformToChatPrompt(type: modelType, fileType: fileType);
    debugPrint('[MobileSession.addQueryChunk] finalPrompt length=${finalPrompt.length}');
    await _platformService.addQueryChunk(finalPrompt);
    if (message.hasImage && message.imageBytes != null && supportImage) {
      await _addImage(message.imageBytes!);
    }
  }

  Future<void> _addImage(Uint8List imageBytes) async {
    _assertNotClosed();
    if (!supportImage) {
      throw ArgumentError('This model does not support images');
    }
    await _platformService.addImage(imageBytes);
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
            if (event is Map && event.containsKey('code') && event['code'] == "ERROR") {
              controller.addError(Exception(event['message'] ?? 'Unknown async error occurred'));
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
    if (_initCompleter != null && _initializedModel != null && _lastActiveInferenceSpec != null) {
      final currentSpec = _lastActiveInferenceSpec!;
      final requestedSpec = activeModel as InferenceModelSpec;

      if (currentSpec.name != requestedSpec.name) {
        // Active model changed - close old model and create new one
        debugPrint('⚠️  Active model changed: ${currentSpec.name} → ${requestedSpec.name}');
        debugPrint('🔄 Closing old model and creating new one...');
        await _initializedModel?.close();
        // onClose callback will reset _initializedModel and _initCompleter
        _lastActiveInferenceSpec = null;
      } else {
        // Same model - return existing singleton
        debugPrint('ℹ️  Reusing existing model instance for ${requestedSpec.name}');
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
        Exception('Model file paths not found. Use the `modelManager` to load the model first'),
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
      await _platformService.createModel(
        maxTokens: maxTokens,
        modelPath: modelPath,
        loraRanks: loraRanks ?? supportedLoraRanks,
        preferredBackend: preferredBackend,
        maxNumImages: supportImage ? (maxNumImages ?? 1) : null,
      );

      final model = _initializedModel = MobileInferenceModel(
        maxTokens: maxTokens,
        modelType: modelType,
        fileType: fileType,
        preferredBackend: preferredBackend,
        supportedLoraRanks: loraRanks ?? supportedLoraRanks,
        supportImage: supportImage,
        maxNumImages: maxNumImages,
        onClose: () {
          _initializedModel = null;
          _initCompleter = null;
          _lastActiveInferenceSpec = null;
        },
      );

      // Save the spec that was used to create this model
      _lastActiveInferenceSpec = activeModel as InferenceModelSpec;

      completer.complete(model);
      return model;
    } catch (e, st) {
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
      final activeModelPath = modelFilePaths[PreferencesKeys.embeddingModelFile];
      final activeTokenizerPath = modelFilePaths[PreferencesKeys.embeddingTokenizerFile];

      if (activeModelPath == null || activeTokenizerPath == null) {
        throw StateError('Could not find model or tokenizer path in active embedding model');
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
          debugPrint('ℹ️  Reusing existing embedding model instance for ${requestedSpec.name}');
          return _initEmbeddingCompleter!.future;
        }
      }

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      debugPrint('Using active embedding model: $modelPath, tokenizer: $tokenizerPath');
    } else {
      // Legacy API with explicit paths - check if singleton exists
      if (_initEmbeddingCompleter case Completer<EmbeddingModel> completer) {
        debugPrint('ℹ️  Reusing existing embedding model instance (Legacy API)');
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
      await _platformService.createEmbeddingModel(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        preferredBackend: preferredBackend,
      );

      final model = _initializedEmbeddingModel = MobileEmbeddingModel(
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
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  // === RAG Methods Implementation ===

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    await ServiceRegistry.instance.vectorStoreRepository.initialize(databasePath);
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
      throw StateError('EmbeddingModel not initialized. Call createEmbeddingModel first.');
    }
    final embedding = await initializedEmbeddingModel!.generateEmbedding(content);

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
  }) async {
    // Generate embedding for query
    if (initializedEmbeddingModel == null) {
      throw StateError('EmbeddingModel not initialized. Call createEmbeddingModel first.');
    }
    final queryEmbedding = await initializedEmbeddingModel!.generateEmbedding(query);

    // Search similar vectors
    return await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: topK,
      threshold: threshold,
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
}
