import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../flutter_gemma_interface.dart';
import '../model_file_manager_interface.dart';
import '../pigeon.g.dart';
import '../core/message.dart';
import '../core/model.dart';
import '../core/tool.dart';
import '../core/chat.dart';
import '../core/extensions.dart';

import 'grpc_client.dart';
import 'server_process_manager.dart';

// Import model management types from mobile (reuse for desktop)
import '../mobile/flutter_gemma_mobile.dart'
    show
        InferenceModelSpec,
        MobileModelManager;

part 'desktop_inference_model.dart';

/// Desktop implementation of FlutterGemma plugin
///
/// Uses gRPC to communicate with a local Kotlin/JVM server
/// running LiteRT-LM for model inference.
class FlutterGemmaDesktop extends FlutterGemmaPlugin {
  FlutterGemmaDesktop._();

  static FlutterGemmaDesktop? _instance;

  /// Get the singleton instance
  static FlutterGemmaDesktop get instance => _instance ??= FlutterGemmaDesktop._();

  /// Register this implementation as the plugin instance
  ///
  /// This is called automatically by Flutter for dartPluginClass.
  /// No parameters needed for desktop platforms.
  static void registerWith() {
    FlutterGemmaPlugin.instance = instance;
    debugPrint('[FlutterGemmaDesktop] Plugin registered for desktop platform');
  }

  // Reuse MobileModelManager for desktop (same filesystem behavior)
  late final MobileModelManager _modelManager = MobileModelManager();

  // Inference model singleton
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;
  InferenceModelSpec? _lastActiveInferenceSpec;

  // Embedding model (not supported in MVP)
  EmbeddingModel? _initializedEmbeddingModel;

  @override
  ModelFileManager get modelManager => _modelManager;

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  EmbeddingModel? get initializedEmbeddingModel => _initializedEmbeddingModel;

  /// Start the gRPC server if not running
  Future<void> _ensureServerRunning() async {
    final serverManager = ServerProcessManager.instance;
    if (!serverManager.isRunning) {
      await serverManager.start();
    }
  }

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
    bool supportAudio = false,
  }) async {
    // Check active model
    final activeModel = _modelManager.activeInferenceModel;
    if (activeModel == null) {
      throw StateError(
        'No active inference model set. Use `FlutterGemma.installModel()` or `modelManager.setActiveModel()` first',
      );
    }

    // Check if singleton exists and matches active model + runtime params
    if (_initCompleter != null &&
        _initializedModel != null &&
        _lastActiveInferenceSpec != null) {
      final currentSpec = _lastActiveInferenceSpec!;
      final requestedSpec = activeModel as InferenceModelSpec;
      final currentModel = _initializedModel as DesktopInferenceModel?;

      final modelChanged = currentSpec.name != requestedSpec.name;
      final paramsChanged = currentModel != null &&
          (currentModel.supportImage != supportImage ||
           currentModel.supportAudio != supportAudio ||
           currentModel.maxTokens != maxTokens);

      if (modelChanged || paramsChanged) {
        // Active model or runtime params changed - close old and create new
        debugPrint('Model recreation: modelChanged=$modelChanged, paramsChanged=$paramsChanged');
        await _initializedModel?.close();
        // Explicitly null these out (onClose callback also does this, but be safe)
        _initCompleter = null;
        _initializedModel = null;
        _lastActiveInferenceSpec = null;
      } else {
        // Same model and params - return existing
        debugPrint('Reusing existing model instance for ${requestedSpec.name}');
        return _initCompleter!.future;
      }
    }

    // Return existing completer if initialization in progress (re-check after potential close)
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }

    final completer = _initCompleter = Completer<InferenceModel>();

    try {
      // Verify model is installed
      final isInstalled = await _modelManager.isModelInstalled(activeModel);
      if (!isInstalled) {
        throw Exception('Active model is no longer installed');
      }

      // Get model file path
      final modelFilePaths = await _modelManager.getModelFilePaths(activeModel);
      if (modelFilePaths == null || modelFilePaths.isEmpty) {
        throw Exception('Model file paths not found');
      }

      final modelPath = modelFilePaths.values.first;
      debugPrint('[FlutterGemmaDesktop] Using model: $modelPath');

      // Start server and create gRPC client
      await _ensureServerRunning();

      final grpcClient = LiteRtLmClient();
      await grpcClient.connect();

      // Initialize model - server validates file existence
      // This avoids TOCTOU race condition (file could be deleted between check and use)
      try {
        await grpcClient.initialize(
          modelPath: modelPath,
          backend: preferredBackend == PreferredBackend.cpu ? 'cpu' : 'gpu',
          maxTokens: maxTokens,
          enableVision: supportImage,
          maxNumImages: supportImage ? (maxNumImages ?? 1) : 0,
          enableAudio: supportAudio,
        );
      } catch (e) {
        // Provide clearer error message for file-related issues
        final errorMsg = e.toString();
        if (errorMsg.contains('FileNotFoundException') ||
            errorMsg.contains('No such file') ||
            errorMsg.contains('not found')) {
          throw Exception('Model file not found or inaccessible: $modelPath');
        }
        rethrow;
      }

      // Create model instance
      final model = _initializedModel = DesktopInferenceModel(
        grpcClient: grpcClient,
        maxTokens: maxTokens,
        modelType: modelType,
        fileType: fileType,
        supportImage: supportImage,
        supportAudio: supportAudio,
        onClose: () {
          _initializedModel = null;
          _initCompleter = null;
          _lastActiveInferenceSpec = null;
        },
      );

      _lastActiveInferenceSpec = activeModel as InferenceModelSpec;

      completer.complete(model);
      return model;
    } catch (e, st) {
      completer.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  @override
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Embedding not supported in desktop MVP
    throw UnsupportedError(
      'Embedding models are not yet supported on desktop. '
      'This feature is planned for a future release.',
    );
  }

  // === RAG Methods (not supported in MVP) ===

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    throw UnsupportedError('VectorStore not yet supported on desktop');
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    throw UnsupportedError('VectorStore not yet supported on desktop');
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    throw UnsupportedError('VectorStore not yet supported on desktop');
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
  }) async {
    throw UnsupportedError('VectorStore not yet supported on desktop');
  }

  @override
  Future<VectorStoreStats> getVectorStoreStats() async {
    throw UnsupportedError('VectorStore not yet supported on desktop');
  }

  @override
  Future<void> clearVectorStore() async {
    throw UnsupportedError('VectorStore not yet supported on desktop');
  }
}

/// Check if current platform is desktop
bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}
