import 'package:flutter_gemma/core/api/model_installation_builder.dart';
import 'package:flutter_gemma/core/api/inference_installation_builder.dart';
import 'package:flutter_gemma/core/api/embedding_installation_builder.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';

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
/// final installation = await FlutterGemma.installModel()
///   .fromNetwork('https://huggingface.co/.../model.bin')
///   .withProgress((progress) => print('Progress: $progress%'))
///   .install();
///
/// // From asset
/// await FlutterGemma.installModel()
///   .fromAsset('models/gemma.bin')
///   .install();
///
/// // From bundled resource
/// await FlutterGemma.installModel()
///   .fromBundled('gemma.bin')
///   .install();
///
/// // From external file
/// await FlutterGemma.installModel()
///   .fromFile('/path/to/model.bin')
///   .install();
/// ```
///
/// ## Load Models (Phase 5)
///
/// ```dart
/// // TODO: Phase 5 - integrate with InferenceModel
/// // final model = await installation.loadForInference();
/// // final response = await model.generateResponse('Hello!');
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
  static void initialize({
    String? huggingFaceToken,
    int maxDownloadRetries = 10,
  }) {
    ServiceRegistry.initialize(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: maxDownloadRetries,
    );
  }

  /// Start building an inference model installation
  ///
  /// Returns type-safe builder for installing inference models with optional LoRA weights.
  /// The model will be automatically set as the active inference model after installation.
  ///
  /// Example:
  /// ```dart
  /// await FlutterGemma.installInferenceModel()
  ///   .fromNetwork('https://example.com/model.task', token: 'hf_...')
  ///   .withProgress((p) => print('$p%'))
  ///   .install();
  ///
  /// // With LoRA weights
  /// await FlutterGemma.installInferenceModel()
  ///   .fromNetwork('https://example.com/model.task')
  ///   .withLoraFromNetwork('https://example.com/lora.bin')
  ///   .install();
  /// ```
  static InferenceInstallationBuilder installInferenceModel() {
    return InferenceInstallationBuilder();
  }

  /// Start building an embedding model installation
  ///
  /// Returns type-safe builder for installing embedding models (requires model + tokenizer).
  /// The model will be automatically set as the active embedding model after installation.
  ///
  /// Example:
  /// ```dart
  /// await FlutterGemma.installEmbeddingModel()
  ///   .modelFromNetwork('https://example.com/model.tflite', token: 'hf_...')
  ///   .tokenizerFromNetwork('https://example.com/tokenizer.model', token: 'hf_...')
  ///   .withModelProgress((p) => print('Model: $p%'))
  ///   .withTokenizerProgress((p) => print('Tokenizer: $p%'))
  ///   .install();
  /// ```
  static EmbeddingInstallationBuilder installEmbeddingModel() {
    return EmbeddingInstallationBuilder();
  }

  /// Start building a model installation (deprecated)
  ///
  /// Use [installInferenceModel] or [installEmbeddingModel] instead for type-safe API.
  ///
  /// Example:
  /// ```dart
  /// await FlutterGemma.installModel()
  ///   .fromNetwork('https://example.com/model.bin')
  ///   .withProgress((p) => print(p))
  ///   .install();
  /// ```
  @Deprecated('Use installInferenceModel() or installEmbeddingModel() for type-safe API')
  static ModelInstallationBuilder installModel() {
    return ModelInstallationBuilder();
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

  /// Reset ServiceRegistry (primarily for testing)
  static void reset() {
    ServiceRegistry.reset();
  }
}
