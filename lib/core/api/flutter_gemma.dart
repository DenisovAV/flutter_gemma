import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/core/api/inference_installation_builder.dart';
import 'package:flutter_gemma/core/api/embedding_installation_builder.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/domain/web_storage_mode.dart';
import 'package:flutter_gemma/core/infrastructure/web_download_service_stub.dart'
    if (dart.library.js_interop) 'package:flutter_gemma/core/infrastructure/web_download_service.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Modern API facade for Flutter Gemma
///
/// Provides clean, type-safe API for model management and inference.
///
/// ## Initialization
///
/// Initialize once at app startup:
/// ```dart
/// void main() {
///   FlutterGemma.initialize(
///     huggingFaceToken: 'hf_...',     // Optional: for gated models
///     maxDownloadRetries: 10,         // Optional: default is 10
///   );
///   runApp(MyApp());
/// }
/// ```
///
/// ## Install Models
///
/// ```dart
/// // From network
/// final installation = await FlutterGemma.installModel(
///   modelType: ModelType.gemmaIt,
/// )
///   .fromNetwork('https://huggingface.co/.../model.bin')
///   .withProgress((progress) => print('Progress: $progress%'))
///   .install();
///
/// // From asset
/// await FlutterGemma.installModel(
///   modelType: ModelType.gemmaIt,
/// )
///   .fromAsset('models/gemma.bin')
///   .install();
///
/// // From bundled resource
/// await FlutterGemma.installModel(
///   modelType: ModelType.gemmaIt,
/// )
///   .fromBundled('gemma.bin')
///   .install();
///
/// // From external file
/// await FlutterGemma.installModel(
///   modelType: ModelType.gemmaIt,
/// )
///   .fromFile('/path/to/model.bin')
///   .install();
/// ```
///
/// ## Load Models
///
/// ```dart
/// // Get active model after installation
/// final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
/// final session = await model.createSession();
/// final response = await session.getResponse();
/// ```
class FlutterGemma {
  /// Initialize Flutter Gemma
  ///
  /// Call this once at app startup before using any other API.
  ///
  /// Parameters:
  /// - [huggingFaceToken]: Optional HuggingFace API token for authenticated downloads
  /// - [maxDownloadRetries]: Maximum retry attempts for transient errors (default: 10)
  ///   Note: Auth errors (401/403/404) always fail after 1 attempt
  /// - [webStorageMode]: Storage mode for web platform (default: WebStorageMode.cacheApi)
  ///   - cacheApi: Cache API with Blob URLs (for models <2GB)
  ///   - streaming: OPFS with streaming (for models >2GB like E4B, 7B, 27B)
  ///   - none: No caching (ephemeral, for development)
  ///   Note: This parameter only affects web platform, ignored on mobile
  /// - [enableWebCache]: DEPRECATED - Use webStorageMode instead
  ///   Will be removed in v0.13.0. Converts to webStorageMode internally.
  ///
  /// Example:
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///
  ///   // For small models (<2GB) - default
  ///   await FlutterGemma.initialize();
  ///
  ///   // For large models (>2GB)
  ///   await FlutterGemma.initialize(
  ///     webStorageMode: WebStorageMode.streaming,
  ///   );
  ///
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> initialize({
    String? huggingFaceToken,
    int maxDownloadRetries = 10,
    WebStorageMode webStorageMode = WebStorageMode.cacheApi,
    @Deprecated('Use webStorageMode instead. Will be removed in v0.13.0')
    bool? enableWebCache,
  }) async {
    // Migration: enableWebCache takes precedence if provided (for backward compatibility)
    final effectiveStorageMode = enableWebCache != null
        ? (enableWebCache ? WebStorageMode.cacheApi : WebStorageMode.none)
        : webStorageMode;

    await ServiceRegistry.initialize(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: maxDownloadRetries,
      webStorageMode: effectiveStorageMode,
    );
  }

  /// Start building an inference model installation
  ///
  /// Returns type-safe builder for installing inference models with optional LoRA weights.
  /// The model will be automatically set as the active inference model after installation.
  ///
  /// Parameters:
  /// - [modelType]: Model type (gemmaIt, deepSeek, qwen, etc.) - Required
  /// - [fileType]: File type (task or binary) - Defaults to task
  ///
  /// Example:
  /// ```dart
  /// // Install Gemma model
  /// await FlutterGemma.installModel(
  ///   modelType: ModelType.gemmaIt,
  /// )
  ///   .fromNetwork('https://example.com/model.task', token: 'hf_...')
  ///   .withProgress((p) => print('$p%'))
  ///   .install();
  ///
  /// // Install DeepSeek with LoRA weights
  /// await FlutterGemma.installModel(
  ///   modelType: ModelType.deepSeek,
  /// )
  ///   .fromNetwork('https://example.com/model.task')
  ///   .withLoraFromNetwork('https://example.com/lora.bin')
  ///   .install();
  /// ```
  static InferenceInstallationBuilder installModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
  }) {
    return InferenceInstallationBuilder(
      modelType: modelType,
      fileType: fileType,
    );
  }

  /// Start building an embedding model installation
  ///
  /// Returns type-safe builder for installing embedding models (requires model + tokenizer).
  /// The model will be automatically set as the active embedding model after installation.
  ///
  /// Example:
  /// ```dart
  /// await FlutterGemma.installEmbedder()
  ///   .modelFromNetwork('https://example.com/model.tflite', token: 'hf_...')
  ///   .tokenizerFromNetwork('https://example.com/tokenizer.model', token: 'hf_...')
  ///   .withModelProgress((p) => print('Model: $p%'))
  ///   .withTokenizerProgress((p) => print('Tokenizer: $p%'))
  ///   .install();
  /// ```
  static EmbeddingInstallationBuilder installEmbedder() {
    return EmbeddingInstallationBuilder();
  }

  /// Check if a model is installed
  ///
  /// Parameters:
  /// - [modelId]: Model filename (e.g., 'gemma-2b-it-cpu-int4.bin')
  static Future<bool> isModelInstalled(String modelId) async {
    final repository = ServiceRegistry.instance.modelRepository;
    return await repository.isInstalled(modelId);
  }

  /// List all installed models
  static Future<List<String>> listInstalledModels() async {
    final repository = ServiceRegistry.instance.modelRepository;
    final models = await repository.listInstalled();
    return models.map((m) => m.id).toList();
  }

  /// Get the active inference model as a ready-to-use InferenceModel
  ///
  /// Returns an InferenceModel configured with runtime parameters.
  /// The model type and file type come from the active InferenceModelSpec.
  ///
  /// Runtime parameters:
  /// - [maxTokens]: Maximum context size (default: 1024)
  /// - [preferredBackend]: CPU or GPU preference (optional)
  /// - [supportImage]: Enable multimodal image support (default: false)
  /// - [supportAudio]: Enable audio input support for Gemma 3n E4B (default: false)
  /// - [maxNumImages]: Maximum number of images if supportImage is true
  ///
  /// Throws:
  /// - [StateError] if no active inference model is set
  ///
  /// Example:
  /// ```dart
  /// // Install model first
  /// await FlutterGemma.installModel(
  ///   modelType: ModelType.gemmaIt,
  /// ).fromNetwork('https://example.com/model.task').install();
  ///
  /// // Create with short context
  /// final shortModel = await FlutterGemma.getActiveModel(
  ///   maxTokens: 512,
  /// );
  ///
  /// // Create with long context and GPU
  /// final longModel = await FlutterGemma.getActiveModel(
  ///   maxTokens: 4096,
  ///   preferredBackend: PreferredBackend.gpu,
  /// );
  ///
  /// // Create with audio support (Gemma 3n E4B only)
  /// final audioModel = await FlutterGemma.getActiveModel(
  ///   supportAudio: true,
  /// );
  /// ```
  static Future<InferenceModel> getActiveModel({
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    bool supportImage = false,
    bool supportAudio = false,
    int? maxNumImages,
  }) async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final activeSpec = manager.activeInferenceModel;

    if (activeSpec == null) {
      throw StateError(
        'No active inference model set. Use FlutterGemma.installModel() first.',
      );
    }

    if (activeSpec is! InferenceModelSpec) {
      throw StateError(
        'Active model is not an InferenceModelSpec. '
        'Expected InferenceModelSpec, got ${activeSpec.runtimeType}',
      );
    }

    // Create InferenceModel using identity from spec + runtime params
    return await FlutterGemmaPlugin.instance.createModel(
      modelType: activeSpec.modelType,
      fileType: activeSpec.fileType,
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
      supportImage: supportImage,
      supportAudio: supportAudio,
      maxNumImages: maxNumImages,
    );
  }

  /// Check if there's an active inference model
  ///
  /// Returns true if an inference model has been installed and set as active.
  ///
  /// Example:
  /// ```dart
  /// if (FlutterGemma.hasActiveModel()) {
  ///   final model = await FlutterGemma.getActiveModel();
  ///   // Use model...
  /// } else {
  ///   // Install model first
  /// }
  /// ```
  static bool hasActiveModel() {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    return manager.activeInferenceModel is InferenceModelSpec;
  }

  /// Get the active embedding model as a ready-to-use EmbeddingModel
  ///
  /// Returns an EmbeddingModel configured with runtime parameters.
  /// The model and tokenizer paths come from the active EmbeddingModelSpec.
  ///
  /// Runtime parameters:
  /// - [preferredBackend]: CPU or GPU preference (optional)
  ///
  /// Throws:
  /// - [StateError] if no active embedding model is set
  ///
  /// Example:
  /// ```dart
  /// // Install embedding model first
  /// await FlutterGemma.installEmbedder()
  ///   .modelFromNetwork('https://example.com/model.tflite')
  ///   .tokenizerFromNetwork('https://example.com/tokenizer.model')
  ///   .install();
  ///
  /// // Create with default backend
  /// final embeddingModel = await FlutterGemma.getActiveEmbedder();
  ///
  /// // Create with specific backend
  /// final cpuModel = await FlutterGemma.getActiveEmbedder(
  ///   preferredBackend: PreferredBackend.cpu,
  /// );
  /// ```
  static Future<EmbeddingModel> getActiveEmbedder({
    PreferredBackend? preferredBackend,
  }) async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final activeSpec = manager.activeEmbeddingModel;

    if (activeSpec == null) {
      throw StateError(
        'No active embedding model set. Use FlutterGemma.installEmbedder() first.',
      );
    }

    if (activeSpec is! EmbeddingModelSpec) {
      throw StateError(
        'Active model is not an EmbeddingModelSpec. '
        'Expected EmbeddingModelSpec, got ${activeSpec.runtimeType}',
      );
    }

    // Create EmbeddingModel using active spec (paths resolved automatically)
    return await FlutterGemmaPlugin.instance.createEmbeddingModel(
      preferredBackend: preferredBackend,
    );
  }

  /// Check if there's an active embedding model
  ///
  /// Returns true if an embedding model has been installed and set as active.
  ///
  /// Example:
  /// ```dart
  /// if (FlutterGemma.hasActiveEmbedder()) {
  ///   final model = await FlutterGemma.getActiveEmbedder();
  ///   // Use model...
  /// } else {
  ///   // Install model first
  /// }
  /// ```
  static bool hasActiveEmbedder() {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    return manager.activeEmbeddingModel is EmbeddingModelSpec;
  }

  /// Uninstall a model
  ///
  /// Removes model metadata and files (if not protected).
  ///
  /// Parameters:
  /// - [modelId]: Model filename to uninstall
  static Future<void> uninstallModel(String modelId) async {
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;
    final fileSystem = registry.fileSystemService;

    // Get model info
    final modelInfo = await repository.loadModel(modelId);
    if (modelInfo == null) {
      throw Exception('Model not found: $modelId');
    }

    // Delete metadata
    await repository.deleteModel(modelId);

    // Delete files (if not external/protected)
    if (modelInfo.source is! FileSource) {
      final targetPath = await fileSystem.getTargetPath(modelId);
      await fileSystem.deleteFile(targetPath);
    }
  }

  /// Check if OPFS streaming mode is supported by the current browser
  ///
  /// Returns true on web if OPFS is available, false otherwise.
  /// Always returns false on mobile platforms.
  ///
  /// OPFS (Origin Private File System) is required for streaming mode,
  /// which allows loading large models (>2GB) without hitting ArrayBuffer limits.
  ///
  /// Browser support:
  /// - Chrome 86+ ✅
  /// - Edge 86+ ✅
  /// - Safari 15.2+ ✅
  /// - Firefox: Not yet supported ❌
  ///
  /// Example:
  /// ```dart
  /// if (await FlutterGemma.isStreamingSupported()) {
  ///   await FlutterGemma.initialize(
  ///     webStorageMode: WebStorageMode.streaming,
  ///   );
  /// } else {
  ///   print('OPFS not available, using cacheApi mode');
  ///   await FlutterGemma.initialize(
  ///     webStorageMode: WebStorageMode.cacheApi,
  ///   );
  /// }
  /// ```
  static Future<bool> isStreamingSupported() async {
    // Streaming only supported on web platform
    if (!kIsWeb) {
      return false;
    }

    try {
      final registry = ServiceRegistry.instance;

      // Check if web storage mode is streaming
      if (registry.webStorageMode != WebStorageMode.streaming) {
        return false;
      }

      // Check if OPFS service is available
      final downloadService = registry.downloadService;
      if (downloadService is! WebDownloadService) {
        return false;
      }

      return downloadService.opfsService != null;
    } catch (e) {
      // ServiceRegistry not initialized or error checking
      return false;
    }
  }

  /// Reset ServiceRegistry (primarily for testing)
  static void reset() {
    ServiceRegistry.reset();
  }
}
