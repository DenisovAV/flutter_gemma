import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'llm_inference_web.dart';
import 'flutter_gemma_web_embedding_model.dart';

class FlutterGemmaWeb extends FlutterGemmaPlugin {
  FlutterGemmaWeb();

  static void registerWith(Registrar registrar) {
    FlutterGemmaPlugin.instance = FlutterGemmaWeb();
  }

  @override
  final WebModelManager modelManager = WebModelManager();

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  EmbeddingModel? get initializedEmbeddingModel => _initializedEmbeddingModel;

  InferenceModel? _initializedModel;
  EmbeddingModel? _initializedEmbeddingModel;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false, // Enabling image support
  }) {
    // TODO: Implement multimodal support for web
    if (supportImage || maxNumImages != null) {
      if (kDebugMode) {
        print('Warning: Image support is not yet implemented for web platform');
      }
    }

    final model = _initializedModel ??= WebInferenceModel(
      modelType: modelType,
      fileType: fileType,
      maxTokens: maxTokens,
      loraRanks: loraRanks,
      modelManager: modelManager,
      supportImage: supportImage, // Passing the flag
      maxNumImages: maxNumImages,
      onClose: () {
        _initializedModel = null;
      },
    );
    return Future.value(model);
  }

  // === EmbeddingModel Methods - Web Implementation ===

  @override
  Future<EmbeddingModel> createEmbeddingModel({
    required String modelPath,
    required String tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    final model = _initializedEmbeddingModel ??= WebEmbeddingModel(
      onClose: () {
        _initializedEmbeddingModel = null;
      },
    );
    return Future.value(model);
  }

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
  }) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<VectorStoreStats> getVectorStoreStats() async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<void> clearVectorStore() async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }
}

class WebInferenceModel extends InferenceModel {
  final VoidCallback onClose;
  @override
  final int maxTokens;

  final ModelType modelType;
  @override
  final ModelFileType fileType;
  final List<int>? loraRanks;
  final WebModelManager modelManager;
  final bool supportImage; // Enabling image support
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
    required this.modelManager,
    this.supportImage = false,
    this.maxNumImages,
  });

  @override
  Future<InferenceModelSession> createSession({
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Enabling vision modality support
  }) async {
    // TODO: Implement vision modality for web
    if (enableVisionModality == true) {
      if (kDebugMode) {
        print('Warning: Vision modality is not yet implemented for web platform');
      }
    }

    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      final fileset = await FilesetResolver.forGenAiTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm'.toJS).toDart;

      final loraPathToUse = loraPath ?? modelManager._loraPath;
      final hasLoraParams = loraPathToUse != null && loraRanks != null;

      final config = LlmInferenceOptions(
        baseOptions: LlmInferenceBaseOptions(modelAssetPath: modelManager._path),
        maxTokens: maxTokens,
        randomSeed: randomSeed,
        topK: topK,
        temperature: temperature,
        topP: topP,
        supportedLoraRanks: !hasLoraParams ? null : Int32List.fromList(loraRanks!).toJS,
        loraPath: !hasLoraParams ? null : loraPathToUse,
      );

      final llmInference = await LlmInference.createFromOptions(fileset, config).toDart;

      final session = this.session = WebModelSession(
        modelType: modelType,
        fileType: fileType,
        llmInference: llmInference,
        supportImage: supportImage, // Enabling image support
        onClose: onClose,
      );
      completer.complete(session);
      return session;
    } catch (e) {
      throw Exception("Failed to create session: $e");
    }
  }

  @override
  Future<void> close() async {
    await session?.close();
    session = null;
    onClose();
  }
}

class WebModelSession extends InferenceModelSession {
  final ModelType modelType;
  final ModelFileType fileType;
  final LlmInference llmInference;
  final VoidCallback onClose;
  final bool supportImage; // Enabling image support
  StreamController<String>? _controller;
  final List<String> _queryChunks = [];

  WebModelSession({
    required this.llmInference,
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
  });

  @override
  Future<int> sizeInTokens(String text) async {
    final size = llmInference.sizeInTokens(text.toJS);
    return size.toDartInt;
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    final finalPrompt = message.transformToChatPrompt(type: modelType, fileType: fileType);

    // Checks for image support (as in the mobile platforms)
    if (message.hasImage && message.imageBytes != null) {
      // TODO: Implement image processing for web
      throw Exception('Web does not support image processing');
    }

    _queryChunks.add(finalPrompt);
  }

  @override
  Future<String> getResponse() async {
    final String fullPrompt = _queryChunks.join("");
    final response = (await llmInference.generateResponse(fullPrompt.toJS, null).toDart).toDart;
    // Don't add response back to queryChunks - that's handled by InferenceChat
    return response;
  }

  @override
  Stream<String> getResponseAsync() {
    _controller = StreamController<String>();

    final String fullPrompt = _queryChunks.join("");

    llmInference.generateResponse(
      fullPrompt.toJS,
      ((JSString partialJs, JSAny completeRaw) {
        final complete = completeRaw.parseBool();
        final partial = partialJs.toDart;

        _controller?.add(partial);
        if (complete) {
          // Don't add response back to queryChunks - that's handled by InferenceChat
          _controller?.close();
          _controller = null;
        }
      }).toJS,
    );

    return _controller!.stream;
  }

  @override
  Future<void> stopGeneration() async {
    throw UnimplementedError('Stop generation is not supported on Web platform yet');
  }

  @override
  Future<void> close() async {
    _queryChunks.clear();
    _controller?.close();
    _controller = null;
    onClose();
  }
}

class WebModelManager extends ModelFileManager {
  bool _isInitialized = false;
  final Map<String, bool> _installedModels = {};
  final Map<String, String> _modelPaths = {}; // ModelSpec.name -> URL
  final Map<String, String> _loraPaths = {}; // ModelSpec.name -> LoRA URL
  final Map<String, Completer<bool>> _loadCompleters = {}; // ModelSpec.name -> Completer

  /// Initializes the web model manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('WebModelManager initialized');
  }

  @override
  Future<bool> isModelInstalled(ModelSpec spec) async {
    await _ensureInitialized();
    // For web, check if model path is set and loading is completed
    final hasPath = _modelPaths.containsKey(spec.name);
    final completer = _loadCompleters[spec.name];
    final isLoaded = completer?.isCompleted == true;
    return hasPath && isLoaded;
  }

  @override
  Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
    await _ensureInitialized();

    final completer = _loadCompleters[spec.name];
    if (completer != null && !completer.isCompleted) {
      throw Exception('Model ${spec.name} is already loading');
    }

    debugPrint('WebModelManager: Starting download for ${spec.name}');

    // Set up the completer and paths
    _loadCompleters[spec.name] = Completer<bool>();

    if (spec is InferenceModelSpec) {
      _modelPaths[spec.name] = spec.modelUrl;
      if (spec.loraUrl != null) {
        _loraPaths[spec.name] = spec.loraUrl!;
      }
    } else if (spec is EmbeddingModelSpec) {
      _modelPaths[spec.name] = spec.modelUrl;
      // For embedding models, we could store tokenizer URL separately if needed
    }

    // Progressive download simulation that matches old behavior
    yield* Stream<int>.periodic(
      const Duration(milliseconds: 10),
      (count) => count + 1,
    ).take(100).map((progress) {
      if (progress == 100 && !_loadCompleters[spec.name]!.isCompleted) {
        _loadCompleters[spec.name]!.complete(true);
        _installedModels[spec.name] = true;
      }

      return DownloadProgress(
        currentFileIndex: 0,
        totalFiles: spec.files.length,
        currentFileProgress: progress,
        currentFileName: spec.files.isNotEmpty ? spec.files.first.filename : 'model.bin',
      );
    }).asBroadcastStream();

    debugPrint('WebModelManager: Download completed for ${spec.name}');
  }

  @override
  Future<void> downloadModel(ModelSpec spec, {String? token}) async {
    await _ensureInitialized();
    // Use the stream version but don't yield progress
    await for (final _ in downloadModelWithProgress(spec, token: token)) {
      // Just consume the stream
    }
  }

  @override
  Future<void> deleteModel(ModelSpec spec) async {
    await _ensureInitialized();

    // Clear all data for this model
    _modelPaths.remove(spec.name);
    _loraPaths.remove(spec.name);
    _loadCompleters.remove(spec.name);
    _installedModels.remove(spec.name);

    debugPrint('WebModelManager: Model ${spec.name} deleted');
  }

  @override
  Future<List<String>> getInstalledModels(ModelManagementType type) async {
    await _ensureInitialized();

    // Return installed model names based on type
    // For web, we can't easily distinguish types, so return all installed
    return _installedModels.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();
  }

  @override
  Future<bool> isAnyModelInstalled(ModelManagementType type) async {
    await _ensureInitialized();
    return _installedModels.values.any((installed) => installed);
  }

  @override
  Future<void> performCleanup() async {
    await _ensureInitialized();
    debugPrint('WebModelManager: Cleanup not needed on web');
  }

  @override
  Future<bool> validateModel(ModelSpec spec) async {
    await _ensureInitialized();
    return _installedModels[spec.name] ?? false;
  }

  @override
  Future<Map<String, String>?> getModelFilePaths(ModelSpec spec) async {
    await _ensureInitialized();

    if (!await isModelInstalled(spec)) {
      return null;
    }

    final paths = <String, String>{};
    final modelPath = _modelPaths[spec.name];
    final loraPath = _loraPaths[spec.name];

    if (modelPath != null) {
      paths['model'] = modelPath;
    }
    if (loraPath != null) {
      paths['lora'] = loraPath;
    }

    return paths.isNotEmpty ? paths : null;
  }

  @override
  Future<Map<String, int>> getStorageStats() async {
    await _ensureInitialized();

    final installedCount = _installedModels.values.where((installed) => installed).length;

    return {
      'protectedFiles': installedCount,
      'totalSizeBytes': 0, // Unknown for web URLs
      'totalSizeMB': 0,
      'inferenceModels': installedCount, // Can't distinguish types easily
      'embeddingModels': 0,
    };
  }

  /// Ensures a model is ready for use, handling all necessary operations
  @override
  Future<void> ensureModelReady(String filename, String url) async {
    await _ensureInitialized();

    // For web, just set the model path - equivalent to old behavior
    _path = url;

    // Create a spec and ensure it's ready
    final spec = InferenceModelSpec(
      name: filename,
      modelUrl: url,
    );

    // Check if already installed, if not - prepare for loading
    if (!await isModelInstalled(spec)) {
      // Set up the model for loading
      _modelPaths[spec.name] = url;
      _loadCompleters[spec.name] = Completer<bool>()..complete(true);
      _installedModels[spec.name] = true;
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Creates an inference model specification from parameters
  static InferenceModelSpec createInferenceSpec({
    required String name,
    required String modelUrl,
    String? loraUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) {
    return InferenceModelSpec(
      name: name,
      modelUrl: modelUrl,
      loraUrl: loraUrl,
      replacePolicy: replacePolicy,
    );
  }

  /// Creates an embedding model specification from parameters
  static EmbeddingModelSpec createEmbeddingSpec({
    required String name,
    required String modelUrl,
    required String tokenizerUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) {
    return EmbeddingModelSpec(
      name: name,
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
      replacePolicy: replacePolicy,
    );
  }

  // Legacy compatibility - for old WebInferenceModel if needed
  String? _path;
  String? _loraPath;
  InferenceModelSpec? _currentActiveModel;

  // === Legacy Asset Loading Methods Implementation ===

  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError("Asset model loading is not supported in release builds");
    }

    await _ensureInitialized();

    final spec = InferenceModelSpec(
      name: path.split('/').last.replaceAll('.bin', '').replaceAll('.task', ''),
      modelUrl: 'asset://$path',
      loraUrl: loraPath != null ? 'asset://$loraPath' : null,
    );

    await ensureModelReady(spec.name, spec.modelUrl);
    _currentActiveModel = spec;
  }

  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) async* {
    if (kReleaseMode) {
      throw UnsupportedError("Asset model loading is not supported in release builds");
    }

    await _ensureInitialized();

    // For web assets, we simulate progress
    for (int progress = 0; progress <= 100; progress += 10) {
      yield progress;
      if (progress < 100) {
        await Future.delayed(Duration(milliseconds: 50));
      }
    }

    await installModelFromAsset(path, loraPath: loraPath);
  }

  // === Legacy Direct Path Methods Implementation ===

  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    await _ensureInitialized();

    // For web, treat as URL
    _path = path;
    _loraPath = loraPath;

    final spec = InferenceModelSpec(
      name: path.split('/').last.replaceAll('.bin', '').replaceAll('.task', ''),
      modelUrl: path.startsWith('http') ? path : 'file://$path',
      loraUrl: loraPath != null ? (loraPath.startsWith('http') ? loraPath : 'file://$loraPath') : null,
    );

    await ensureModelReady(spec.name, spec.modelUrl);
    _currentActiveModel = spec;
  }

  @override
  Future<void> clearModelCache() async {
    await _ensureInitialized();

    _path = null;
    _loraPath = null;
    _currentActiveModel = null;
    _installedModels.clear();
    _modelPaths.clear();
    _loraPaths.clear();
    _loadCompleters.clear();

    debugPrint('WebModelManager: Model cache cleared');
  }

  // === Legacy LoRA Management Methods Implementation ===

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _ensureInitialized();

    if (_currentActiveModel == null) {
      throw Exception('No active model to apply LoRA weights to. Use setModelPath first.');
    }

    _loraPath = path;

    final updatedSpec = InferenceModelSpec(
      name: _currentActiveModel!.name,
      modelUrl: _currentActiveModel!.modelUrl,
      loraUrl: path.startsWith('http') ? path : 'file://$path',
      replacePolicy: _currentActiveModel!.replacePolicy,
    );

    // Update internal state
    _loraPaths[updatedSpec.name] = path;
    _currentActiveModel = updatedSpec;
  }

  @override
  Future<void> deleteLoraWeights() async {
    await _ensureInitialized();

    if (_currentActiveModel == null) {
      throw Exception('No active model to remove LoRA weights from');
    }

    _loraPath = null;

    final updatedSpec = InferenceModelSpec(
      name: _currentActiveModel!.name,
      modelUrl: _currentActiveModel!.modelUrl,
      loraUrl: null, // Remove LoRA
      replacePolicy: _currentActiveModel!.replacePolicy,
    );

    // Update internal state
    _loraPaths.remove(updatedSpec.name);
    _currentActiveModel = updatedSpec;
  }

  // === Legacy Model Management Implementation ===

  @override
  Future<void> deleteCurrentModel() async {
    await _ensureInitialized();

    if (_currentActiveModel != null) {
      await deleteModel(_currentActiveModel!);
      _currentActiveModel = null;
      _path = null;
      _loraPath = null;
    }
  }
}
