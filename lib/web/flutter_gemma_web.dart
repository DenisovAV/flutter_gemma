import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'llm_inference_web.dart';
import 'flutter_gemma_web_embedding_model.dart';

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
    final mimeType = _detectImageFormat(bytes);
    final dataUrl = 'data:$mimeType;base64,$base64String';
    return ImagePromptPart(dataUrl);
  }

  /// Detect image format from header bytes
  static String _detectImageFormat(Uint8List bytes) {
    if (bytes.length < 4) return 'image/png'; // default fallback

    // JPEG magic number: FF D8 FF
    if (_matchesSignature(bytes, [0xFF, 0xD8, 0xFF])) {
      return 'image/jpeg';
    }

    // PNG magic number: 89 50 4E 47
    if (_matchesSignature(bytes, [0x89, 0x50, 0x4E, 0x47])) {
      return 'image/png';
    }

    // WebP magic number: RIFF at start, WEBP at offset 8
    if (bytes.length >= 12 &&
        _matchesSignature(bytes, [0x52, 0x49, 0x46, 0x46]) &&
        _matchesSignature(bytes.sublist(8), [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }

    return 'image/png'; // default fallback
  }

  /// Check if bytes match a signature at the beginning
  static bool _matchesSignature(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (int i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }
}

class FlutterGemmaWeb extends FlutterGemmaPlugin {
  FlutterGemmaWeb();

  static void registerWith(Registrar registrar) {
    FlutterGemmaPlugin.instance = FlutterGemmaWeb();
  }

  // Use WebModelManager singleton (will be replaced with platform-agnostic manager in future phases)
  static WebModelManager? _webManager;

  @override
  ModelFileManager get modelManager {
    // Use WebModelManager for now (Phase 6 will migrate to fully unified approach)
    _webManager ??= WebModelManager();
    return _webManager!;
  }

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
        debugPrint('Warning: Image support is not yet implemented for web platform');
      }
    }

    final model = _initializedModel ??= WebInferenceModel(
      modelType: modelType,
      fileType: fileType,
      maxTokens: maxTokens,
      loraRanks: loraRanks,
      modelManager: modelManager as WebModelManager, // Use the same instance from FlutterGemmaPlugin.instance
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
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Modern API: Use active embedding model if paths not provided
    if (modelPath == null || tokenizerPath == null) {
      // Web: Embedding models not fully supported yet, but keep API consistent
      if (modelManager.activeEmbeddingModel == null) {
        throw Exception('No active embedding model set. Use `FlutterGemma.installEmbedder()` or `modelManager.setActiveModel()` to set a model first');
      }

      // TODO: Implement full embedding model support on web
      throw UnimplementedError('Embedding models are not fully supported on web platform yet');
    }

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
        debugPrint('Warning: Vision modality is not yet implemented for web platform');
      }
    }

    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      // Use Modern API to get model path (same as mobile)
      final activeModel = modelManager.activeInferenceModel;
      if (activeModel == null) {
        throw Exception('No active inference model set');
      }

      final modelFilePaths = await modelManager.getModelFilePaths(activeModel);
      if (modelFilePaths == null || modelFilePaths.isEmpty) {
        throw Exception('Model file paths not found');
      }

      // Get model path from Modern API
      final modelPath = modelFilePaths[PreferencesKeys.installedModelFileName];
      if (modelPath == null) {
        throw Exception('Model path not found in file paths');
      }

      final fileset = await FilesetResolver.forGenAiTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@latest/wasm'.toJS).toDart;

      // Get LoRA path if available
      final loraPathToUse = loraPath ?? modelFilePaths[PreferencesKeys.installedLoraFileName];
      final hasLoraParams = loraPathToUse != null && loraRanks != null;

      final config = LlmInferenceOptions(
        baseOptions: LlmInferenceBaseOptions(modelAssetPath: modelPath),
        maxTokens: maxTokens,
        randomSeed: randomSeed,
        topK: topK,
        temperature: temperature,
        topP: topP,
        supportedLoraRanks: !hasLoraParams ? null : Int32List.fromList(loraRanks!).toJS,
        loraPath: !hasLoraParams ? null : loraPathToUse,
        maxNumImages: supportImage ? (maxNumImages ?? 1) : null
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
  final List<PromptPart> _promptParts = [];

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
    if (kDebugMode) {
      debugPrint('🟢 WebModelSession.addQueryChunk() called - hasImage: ${message.hasImage}, supportImage: $supportImage');
    }

    final finalPrompt = message.transformToChatPrompt(type: modelType, fileType: fileType);

    // Add text part
    _promptParts.add(TextPromptPart(finalPrompt));
    if (kDebugMode) {
      debugPrint('🟢 Added text part: ${finalPrompt.substring(0, math.min(100, finalPrompt.length))}...');
    }

    // Handle image processing for web
    if (message.hasImage && message.imageBytes != null) {
      if (kDebugMode) {
        debugPrint('🟢 Processing image: ${message.imageBytes!.length} bytes');
      }
      if (!supportImage) {
        if (kDebugMode) {
          debugPrint('🔴 Model does not support images - throwing exception');
        }
        throw Exception('This model does not support images');
      }
      // Add image part
      final imagePart = ImagePromptPart.fromBytes(message.imageBytes!);
      _promptParts.add(imagePart);
      if (kDebugMode) {
        debugPrint('🟢 Added image part with dataUrl length: ${imagePart.dataUrl.length}');
      }
    }

    if (kDebugMode) {
      debugPrint('🟢 Total prompt parts: ${_promptParts.length}');
    }
  }

  /// Convert PromptParts to JavaScript array for MediaPipe
  JSAny _createPromptArray() {
    if (kDebugMode) {
      debugPrint('🔧 _createPromptArray: Starting with ${_promptParts.length} prompt parts');
    }

    if (_promptParts.isEmpty) {
      if (kDebugMode) {
        debugPrint('📝 _createPromptArray: Empty prompt parts, returning empty string');
      }
      return ''.toJS; // Empty string fallback
    }

    // If only text parts, join them
    if (_promptParts.every((part) => part is TextPromptPart)) {
      final fullText = _promptParts
          .cast<TextPromptPart>()
          .map((part) => part.text)
          .join('');
      if (kDebugMode) {
        debugPrint('📝 _createPromptArray: All text parts, returning string of length ${fullText.length}');
        debugPrint('📝 _createPromptArray: Text preview: ${fullText.substring(0, math.min(100, fullText.length))}...');
      }
      return fullText.toJS;
    }

    // Multimodal: create array of parts following MediaPipe documentation format
    if (kDebugMode) {
      debugPrint('🎯 _createPromptArray: Multimodal mode - creating array with proper format');
    }

    final jsArray = <JSAny>[];

    // Add conversation start token
    jsArray.add('<ctrl99>user\n'.toJS);

    for (int i = 0; i < _promptParts.length; i++) {
      final part = _promptParts[i];

      if (part is TextPromptPart) {
        if (kDebugMode) {
          debugPrint('📝 _createPromptArray: Adding text part: "${part.text.substring(0, math.min(50, part.text.length))}..."');
        }
        jsArray.add(part.text.toJS);
      } else if (part is ImagePromptPart) {
        if (kDebugMode) {
          debugPrint('🖼️ _createPromptArray: Adding image part with data URL length: ${part.dataUrl.length}');
          debugPrint('🖼️ _createPromptArray: Image data URL prefix: ${part.dataUrl.substring(0, math.min(50, part.dataUrl.length))}...');
        }

        // Create proper image object for MediaPipe
        final imageObj = <String, String>{'imageSource': part.dataUrl}.jsify();
        if (kDebugMode) {
          debugPrint('🖼️ _createPromptArray: Created image object with jsify()');
        }
        jsArray.add(imageObj as JSAny);
      } else {
        if (kDebugMode) {
          debugPrint('❌ _createPromptArray: Unsupported prompt part type: ${part.runtimeType}');
        }
        throw Exception('Unsupported prompt part type: $part');
      }
    }

    // Add conversation end and model start tokens
    jsArray.add('<ctrl100>\n<ctrl99>model\n'.toJS);

    if (kDebugMode) {
      debugPrint('✅ _createPromptArray: Created JS array with ${jsArray.length} elements (including control tokens)');
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
        debugPrint('🎯 getResponse: Prompt array type: ${promptArray.runtimeType}');
        debugPrint('🎯 getResponse: Is JSString? ${promptArray is JSString}');
      }

      String response;

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          debugPrint('📝 getResponse: Using generateResponse for text-only prompt');
        }
        response = (await llmInference.generateResponse(promptArray, null).toDart).toDart;
      } else {
        if (kDebugMode) {
          debugPrint('🖼️ getResponse: Using generateResponseMultimodal for multimodal prompt');
        }
        response = (await llmInference.generateResponseMultimodal(promptArray, null).toDart).toDart;
      }

      if (kDebugMode) {
        debugPrint('✅ getResponse: Successfully generated response of length ${response.length}');
        debugPrint('✅ getResponse: Response preview: ${response.substring(0, math.min(100, response.length))}...');
      }

      // Don't add response back to promptParts - that's handled by InferenceChat
      return response;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ getResponse: Exception caught: $e');
        debugPrint('❌ getResponse: Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  @override
  Stream<String> getResponseAsync() {
    if (kDebugMode) {
      debugPrint('🌊 getResponseAsync: Starting async response generation');
    }

    _controller = StreamController<String>();

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        debugPrint('🎯 getResponseAsync: Prompt array type: ${promptArray.runtimeType}');
        debugPrint('🎯 getResponseAsync: Is JSString? ${promptArray is JSString}');
      }

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          debugPrint('📝 getResponseAsync: Using generateResponse for text-only prompt');
        }
        llmInference.generateResponse(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                debugPrint('📝 getResponseAsync: Received partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
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
          debugPrint('🖼️ getResponseAsync: Using generateResponseMultimodal for multimodal prompt');
        }
        llmInference.generateResponseMultimodal(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                debugPrint('🖼️ getResponseAsync: Received multimodal partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  debugPrint('✅ getResponseAsync: Multimodal response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ getResponseAsync: Error in multimodal callback: $e');
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
    throw UnimplementedError('Stop generation is not supported on Web platform yet');
  }

  @override
  Future<void> close() async {
    _promptParts.clear();
    _controller?.close();
    _controller = null;
    onClose();
  }
}

/// Web Model Manager - Modern API Facade Pattern
///
/// Phase 5 Complete: This class now delegates all model management to the
/// Modern API (ServiceRegistry + Handlers + Repository) instead of manually
/// managing state. All methods are thin facades over the Modern API.
///
/// Architecture:
/// - OLD: Manual state maps (_installedModels, _modelPaths, etc.)
/// - NEW: Delegates to ServiceRegistry.instance → handlers → repository
///
/// Benefits:
/// - Single source of truth (repository)
/// - No code duplication
/// - Platform-agnostic (same pattern as MobileModelManager)
/// - Easier to maintain and test
class WebModelManager extends ModelFileManager {
  bool _isInitialized = false;

  /// Initializes the web model manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('WebModelManager initialized');
  }

  /// Checks if a model is installed
  ///
  /// Phase 5.3: Delegates to Modern API (ModelRepository) instead of
  /// checking manual state (_modelPaths, _loadCompleters).
  @override
  Future<bool> isModelInstalled(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Check if all files in the spec are installed
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        return false;
      }
    }

    return true;
  }

  @override
  Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
    await _ensureInitialized();

    debugPrint('WebModelManager: Starting download for ${spec.name}');

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;
    final totalFiles = spec.files.length;

    for (int i = 0; i < totalFiles; i++) {
      final file = spec.files[i];

      // Emit file start progress
      yield DownloadProgress(
        currentFileIndex: i,
        totalFiles: totalFiles,
        currentFileProgress: 0,
        currentFileName: file.filename,
      );

      // Get handler for this file's source
      final handler = handlerRegistry.getHandler(file.source);
      if (handler == null) {
        throw ModelStorageException(
          'No handler for ${file.source.runtimeType}',
          null,
          'downloadModelWithProgress',
        );
      }

      // For NetworkSource with token, update the source
      ModelSource sourceToInstall = file.source;
      if (sourceToInstall is NetworkSource && token != null) {
        sourceToInstall = NetworkSource(sourceToInstall.url, authToken: token);
      }

      // Download via Modern API handler with progress
      // All handlers implement installWithProgress (handlers that don't support
      // true progress will emit 100% immediately)
      await for (final progress in handler.installWithProgress(sourceToInstall)) {
        yield DownloadProgress(
          currentFileIndex: i,
          totalFiles: totalFiles,
          currentFileProgress: progress,
          currentFileName: file.filename,
        );
      }
    }

    // Set as active after successful download
    setActiveModel(spec);

    // Emit final progress
    yield DownloadProgress(
      currentFileIndex: totalFiles,
      totalFiles: totalFiles,
      currentFileProgress: 100,
      currentFileName: 'Complete',
    );

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

  /// Deletes a model
  ///
  /// Phase 5.5: Delegates to Modern API (ModelRepository) instead of
  /// manually removing from state maps.
  @override
  Future<void> deleteModel(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Delete all files in the spec from repository
    for (final file in spec.files) {
      await repository.deleteModel(file.filename);
    }

    debugPrint('WebModelManager: Model ${spec.name} deleted');
  }

  /// Gets list of installed model filenames
  ///
  /// Phase 5.5: Delegates to Modern API (ModelRepository) instead of
  /// querying _installedModels map.
  @override
  Future<List<String>> getInstalledModels(ModelManagementType type) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Get all installed models from repository
    final allInstalled = await repository.listInstalled();

    // Filter by type
    final filtered = allInstalled.where((m) {
      if (type == ModelManagementType.inference) {
        return m.type == repo.ModelType.inference;
      } else {
        return m.type == repo.ModelType.embedding;
      }
    }).toList();

    // Return filenames
    return filtered.map((m) => m.id).toList();
  }

  /// Checks if any model is installed
  ///
  /// Phase 5.5: Delegates to Modern API (ModelRepository) instead of
  /// checking _installedModels map.
  @override
  Future<bool> isAnyModelInstalled(ModelManagementType type) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Get all installed models from repository
    final allInstalled = await repository.listInstalled();

    if (type == ModelManagementType.inference) {
      return allInstalled.any((m) => m.type == repo.ModelType.inference);
    } else {
      return allInstalled.any((m) => m.type == repo.ModelType.embedding);
    }
  }

  @override
  Future<void> performCleanup() async {
    await _ensureInitialized();
    debugPrint('WebModelManager: Cleanup not needed on web');
  }

  /// Validates if a model is properly installed
  ///
  /// Phase 5.3: Delegates to Modern API (isModelInstalled) instead of
  /// checking manual _installedModels map.
  @override
  Future<bool> validateModel(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    // validateModel is essentially the same as isModelInstalled on web
    return await isModelInstalled(spec);
  }

  @override
  Future<Map<String, String>?> getModelFilePaths(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;
    final fileSystem = registry.fileSystemService as WebFileSystemService;

    // Check installation via repository
    bool allFilesInstalled = true;
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        allFilesInstalled = false;
        break;
      }
    }

    if (!allFilesInstalled) {
      return null;
    }

    final filePaths = <String, String>{};

    for (final file in spec.files) {
      // Get URL from WebFileSystemService based on source type
      final String path;

      if (file.source is NetworkSource) {
        // Web: Get registered URL
        path = fileSystem.getUrl(file.filename) ?? (file.source as NetworkSource).url;
      } else if (file.source is BundledSource) {
        // Web: Bundled resources
        path = await fileSystem.getBundledResourcePath((file.source as BundledSource).resourceName);
      } else if (file.source is AssetSource) {
        // Web: Asset path
        path = (file.source as AssetSource).normalizedPath;
      } else if (file.source is FileSource) {
        // Web: External URL or registered path
        final fileSource = file.source as FileSource;
        path = fileSystem.getUrl(file.filename) ?? fileSource.path;
      } else {
        // Fallback: use getTargetPath
        path = await fileSystem.getTargetPath(file.filename);
      }

      filePaths[file.prefsKey] = path;
    }

    return filePaths.isNotEmpty ? filePaths : null;
  }

  /// Gets storage statistics for installed models
  ///
  /// Phase 5.3: Delegates to Modern API (ModelRepository) instead of
  /// checking manual _installedModels map.
  @override
  Future<Map<String, int>> getStorageStats() async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Get all installed models from repository
    final allInstalled = await repository.listInstalled();
    final installedCount = allInstalled.length;

    // Count by type
    final inferenceCount = allInstalled.where((m) => m.type == repo.ModelType.inference).length;
    final embeddingCount = allInstalled.where((m) => m.type == repo.ModelType.embedding).length;

    return {
      'protectedFiles': installedCount,
      'totalSizeBytes': 0, // Unknown for web URLs (no local file system)
      'totalSizeMB': 0,
      'inferenceModels': inferenceCount,
      'embeddingModels': embeddingCount,
    };
  }

  /// Modern API: Ensures a model spec is ready for use
  ///
  /// Phase 5.1: This method now delegates to ServiceRegistry (Modern API)
  /// instead of manually managing state. All installation is handled by
  /// source handlers through the ServiceRegistry pattern.
  @override
  Future<void> ensureModelReadyFromSpec(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to ServiceRegistry (Modern API)
    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;
    final repository = registry.modelRepository;

    // Check if already installed via repository
    bool allFilesInstalled = true;
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        allFilesInstalled = false;
        break;
      }
    }

    if (!allFilesInstalled) {
      // Install via Modern API handlers
      for (final file in spec.files) {
        final handler = handlerRegistry.getHandler(file.source);
        if (handler == null) {
          throw ModelStorageException(
            'No handler for ${file.source.runtimeType}',
            null,
            'ensureModelReadyFromSpec',
          );
        }
        await handler.install(file.source);
      }
    }

    setActiveModel(spec);
  }

  /// Legacy API: Ensures a model is ready for use, handling all necessary operations
  ///
  /// Phase 5.5: Thin facade over ensureModelReadyFromSpec (Modern API)
  @Deprecated('Use ensureModelReadyFromSpec with ModelSource instead')
  @override
  Future<void> ensureModelReady(String filename, String url) async {
    await _ensureInitialized();

    // Create a spec and delegate to Modern API
    final spec = InferenceModelSpec.fromLegacyUrl(
      name: filename,
      modelUrl: url,
    );

    // Delegate to Modern API (no manual state management needed)
    await ensureModelReadyFromSpec(spec);
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
    return InferenceModelSpec.fromLegacyUrl(
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
    return EmbeddingModelSpec.fromLegacyUrl(
      name: name,
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
      replacePolicy: replacePolicy,
    );
  }

  /// Creates a bundled inference model specification (for production builds)
  ///
  /// Use this for models packaged in web/assets/models/
  ///
  /// Example:
  /// ```dart
  /// final spec = WebModelManager.createBundledInferenceSpec(
  ///   resourceName: 'gemma3-270m-it-q8.task',
  /// );
  /// await manager.ensureModelReadyFromSpec(spec);
  /// ```
  static InferenceModelSpec createBundledInferenceSpec({
    required String resourceName,
    String? loraResourceName,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
    ModelType modelType = ModelType.general,
    ModelFileType fileType = ModelFileType.task,
  }) {
    final name = resourceName.split('.').first;

    return InferenceModelSpec(
      name: name,
      modelSource: BundledSource(resourceName),
      loraSource: loraResourceName != null ? BundledSource(loraResourceName) : null,
      replacePolicy: replacePolicy,
      modelType: modelType,
      fileType: fileType,
    );
  }

  /// Creates a bundled embedding model specification (for production builds)
  ///
  /// Use this for embedding models packaged in web/assets/models/
  ///
  /// Example:
  /// ```dart
  /// final spec = WebModelManager.createBundledEmbeddingSpec(
  ///   modelResourceName: 'embeddinggemma-300M.tflite',
  ///   tokenizerResourceName: 'sentencepiece.model',
  /// );
  /// await manager.ensureModelReadyFromSpec(spec);
  /// ```
  static EmbeddingModelSpec createBundledEmbeddingSpec({
    required String modelResourceName,
    required String tokenizerResourceName,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) {
    final name = modelResourceName.split('.').first;

    return EmbeddingModelSpec(
      name: name,
      modelSource: BundledSource(modelResourceName),
      tokenizerSource: BundledSource(tokenizerResourceName),
      replacePolicy: replacePolicy,
    );
  }

  // Active models (modern API)
  ModelSpec? _activeInferenceModel;
  ModelSpec? _activeEmbeddingModel;

  /// Gets the currently active inference model specification
  @override
  ModelSpec? get activeInferenceModel => _activeInferenceModel;

  /// Gets the currently active embedding model specification
  @override
  ModelSpec? get activeEmbeddingModel => _activeEmbeddingModel;

  /// Gets the currently active model specification (backward compatibility)
  @Deprecated('Use activeInferenceModel or activeEmbeddingModel instead')
  ModelSpec? get currentActiveModel => _activeInferenceModel ?? _activeEmbeddingModel;

  // === Legacy Asset Loading Methods Implementation ===

  /// Installs model from Flutter asset (debug mode only)
  ///
  /// ⚠️ DEPRECATED: Use FlutterGemma.installModel().fromAsset() instead
  ///
  /// This method provides backward compatibility but delegates to Modern API.
  ///
  /// Migration:
  /// ```dart
  /// // OLD:
  /// await manager.installModelFromAsset('assets/models/gemma.task');
  ///
  /// // NEW:
  /// await FlutterGemma.installModel()
  ///   .fromAsset('assets/models/gemma.task')
  ///   .install();
  /// ```
  @Deprecated('Use FlutterGemma.installModel().fromAsset() instead')
  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError(
        "Asset model loading is not supported in release builds. "
        "Use fromNetwork() or fromBundled() instead."
      );
    }

    await _ensureInitialized();

    // Convert legacy parameters to Modern API ModelSpec
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(path.split('/').last),
      modelSource: ModelSource.asset(path),
      loraSource: loraPath != null ? ModelSource.asset(loraPath) : null,
      modelType: ModelType.general,  // Default for legacy API
      fileType: ModelFileType.task,   // Default for legacy API
    );

    // Delegate to Modern API
    // This uses AssetSourceHandler which handles all the work
    await ensureModelReadyFromSpec(spec);
  }

  /// Installs model from Flutter asset with progress (debug mode only)
  ///
  /// ⚠️ DEPRECATED: Use FlutterGemma.installModel().fromAsset().installWithProgress() instead
  ///
  /// Migration:
  /// ```dart
  /// // OLD:
  /// await for (final progress in manager.installModelFromAssetWithProgress('assets/models/gemma.task')) {
  ///   debugPrint('Progress: $progress%');
  /// }
  ///
  /// // NEW:
  /// await for (final progress in FlutterGemma.installModel()
  ///     .fromAsset('assets/models/gemma.task')
  ///     .installWithProgress()) {
  ///   debugPrint('Progress: ${progress.currentFileProgress}%');
  /// }
  /// ```
  @Deprecated('Use FlutterGemma.installModel().fromAsset().installWithProgress() instead')
  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) async* {
    if (kReleaseMode) {
      throw UnsupportedError(
        "Asset model loading is not supported in release builds. "
        "Use fromNetwork() or fromBundled() instead."
      );
    }

    await _ensureInitialized();

    // Convert legacy parameters to Modern API ModelSpec
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(path.split('/').last),
      modelSource: ModelSource.asset(path),
      loraSource: loraPath != null ? ModelSource.asset(loraPath) : null,
      modelType: ModelType.general,  // Default for legacy API
      fileType: ModelFileType.task,   // Default for legacy API
    );

    // Delegate to Modern API downloadModelWithProgress
    // This provides real progress tracking from handlers
    await for (final downloadProgress in downloadModelWithProgress(spec)) {
      yield downloadProgress.currentFileProgress;
    }
  }

  // === Legacy Direct Path Methods Implementation ===

  /// Sets model path for inference (web: URLs only)
  ///
  /// ⚠️ DEPRECATED: Use FlutterGemma.installModel().fromNetwork() instead
  ///
  /// This method provides backward compatibility but delegates to Modern API.
  ///
  /// Migration:
  /// ```dart
  /// // OLD:
  /// await manager.setModelPath('https://example.com/model.task');
  ///
  /// // NEW:
  /// await FlutterGemma.installModel()
  ///   .fromNetwork('https://example.com/model.task')
  ///   .install();
  /// ```
  @Deprecated('Use FlutterGemma.installModel().fromNetwork() instead')
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    await _ensureInitialized();

    // Create ModelSource based on path type
    final modelSource = path.startsWith('http')
        ? ModelSource.network(path)
        : ModelSource.file(path);

    final loraSource = loraPath != null
        ? (loraPath.startsWith('http')
            ? ModelSource.network(loraPath)
            : ModelSource.file(loraPath))
        : null;

    // Convert legacy parameters to Modern API ModelSpec
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(path.split('/').last),
      modelSource: modelSource,
      loraSource: loraSource,
      modelType: ModelType.general,  // Default for legacy API
      fileType: ModelFileType.task,   // Default for legacy API
    );

    // Delegate to Modern API
    await ensureModelReadyFromSpec(spec);
  }

  /// Clears model cache (legacy method)
  ///
  /// ⚠️ Note: In Modern API, model persistence is managed by ModelRepository.
  /// This method only clears active model references, not installed models.
  /// Use deleteModel() to remove installed models.
  @override
  Future<void> clearModelCache() async {
    await _ensureInitialized();

    // Clear active models
    _activeInferenceModel = null;
    _activeEmbeddingModel = null;

    debugPrint('WebModelManager: Model cache cleared (active models reset)');
  }

  // === Legacy LoRA Management Methods Implementation ===

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _ensureInitialized();

    if (_activeInferenceModel == null) {
      throw Exception('No active inference model to apply LoRA weights to. Use setModelPath first.');
    }

    final current = _activeInferenceModel as InferenceModelSpec;

    // Create LoRA source from path
    final loraSource = path.startsWith('http')
        ? ModelSource.network(path)
        : ModelSource.file(path);

    final updatedSpec = InferenceModelSpec(
      name: current.name,
      modelSource: current.modelSource,
      loraSource: loraSource,
      replacePolicy: current.replacePolicy,
      modelType: current.modelType,
      fileType: current.fileType,
    );

    // Update active model (no manual _loraPaths management needed)
    setActiveModel(updatedSpec);
  }

  @override
  Future<void> deleteLoraWeights() async {
    await _ensureInitialized();

    if (_activeInferenceModel == null) {
      throw Exception('No active inference model to remove LoRA weights from');
    }

    final current = _activeInferenceModel as InferenceModelSpec;

    final updatedSpec = InferenceModelSpec(
      name: current.name,
      modelSource: current.modelSource,
      loraSource: null, // Remove LoRA
      replacePolicy: current.replacePolicy,
      modelType: current.modelType,
      fileType: current.fileType,
    );

    // Update active model (no manual _loraPaths management needed)
    setActiveModel(updatedSpec);
  }

  // === Legacy Model Management Implementation ===

  @override
  Future<void> deleteCurrentModel() async {
    await _ensureInitialized();

    // Delete active inference model if exists
    if (_activeInferenceModel != null) {
      await deleteModel(_activeInferenceModel!);
      _activeInferenceModel = null;
    }

    // Delete active embedding model if exists
    if (_activeEmbeddingModel != null) {
      await deleteModel(_activeEmbeddingModel!);
      _activeEmbeddingModel = null;
    }
  }

  @override
  void setActiveModel(ModelSpec spec) {
    if (spec is InferenceModelSpec) {
      _activeInferenceModel = spec;
      debugPrint('✅ Set active inference model: ${spec.name}');
    } else if (spec is EmbeddingModelSpec) {
      _activeEmbeddingModel = spec;
      debugPrint('✅ Set active embedding model: ${spec.name}');
    } else {
      throw ArgumentError('Unknown ModelSpec type: ${spec.runtimeType}');
    }
  }

  // === Storage Management Implementation ===

  @override
  Future<StorageStats> getStorageInfo() async {
    await _ensureInitialized();
    // Web platform doesn't have file system access, return empty stats
    return const StorageStats(
      totalFiles: 0,
      totalSizeBytes: 0,
      orphanedFiles: [],
    );
  }

  @override
  Future<List<OrphanedFileInfo>> getOrphanedFiles() async {
    await _ensureInitialized();
    // Web platform doesn't have file system access, no orphaned files
    return [];
  }

  @override
  Future<int> cleanupStorage() async {
    await _ensureInitialized();
    // Web platform doesn't have file system access, nothing to cleanup
    debugPrint('WebModelManager: cleanupStorage() is a no-op on web');
    return 0;
  }
}
