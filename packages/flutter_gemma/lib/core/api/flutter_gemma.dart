import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/core/api/inference_installation_builder.dart';
import 'package:flutter_gemma/core/api/embedding_installation_builder.dart';
import 'package:flutter_gemma/core/api/stt_installation_builder.dart';
import 'package:flutter_gemma/core/api/tts_installation_builder.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/domain/web_storage_mode.dart';
import 'package:flutter_gemma/core/infrastructure/web_download_service_stub.dart'
    if (dart.library.js_interop) 'package:flutter_gemma/core/infrastructure/web_download_service.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/registry/engine_registry.dart';
import 'package:flutter_gemma/core/registry/embedding_registry.dart';
import 'package:flutter_gemma/core/registry/stt_registry.dart';
import 'package:flutter_gemma/core/registry/tts_registry.dart';
import 'package:flutter_gemma/core/registry/skill_executor_registry.dart';
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/stt_backend_provider.dart';
import 'package:flutter_gemma/core/registry/tts_backend_provider.dart';
import 'package:flutter_gemma/core/registry/skill_executor_provider.dart';
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/core/services/vector_store_filter.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart';

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
  /// Controls flutter_gemma's internal log verbosity.
  ///
  /// Debug builds only -- release builds are always silent regardless of this
  /// value (no model output / prompts leak into logcat/syslog). Default
  /// [GemmaLogLevel.info]. Use [GemmaLogLevel.verbose] to see model output and
  /// prompts while debugging, or [GemmaLogLevel.none] to silence the plugin.
  ///
  /// Note: this is a process-global, per-isolate setting; set it once at
  /// startup. Background isolates snapshot the value at spawn time.
  static GemmaLogLevel get logLevel => gemmaLogLevel;
  static set logLevel(GemmaLogLevel value) => gemmaLogLevel = value;

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
  /// - [enableWebCache]: DEPRECATED - Use webStorageMode instead.
  ///   Converts to webStorageMode internally; scheduled for removal in 1.0.
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
    @Deprecated('Use webStorageMode instead. Scheduled for removal in 1.0.')
    bool? enableWebCache,
    // Opt-in registration. Engines/backends are FULLY opt-in: core registers
    // NONE by default. Pass the providers from the packages you use, e.g.
    // `LiteRtLmEngine()` (flutter_gemma_litertlm), `MediaPipeEngine()`
    // (flutter_gemma_mediapipe), `LiteRtEmbeddingBackend()`
    // (flutter_gemma_embeddings). If the lists are empty, the first
    // createModel / createEmbeddingModel throws a clear "add the engine
    // package" StateError. vectorStore null → ServiceRegistry's
    // UnconfiguredVectorStore sentinel (RAG is opt-in; it throws a clear "add a
    // RAG package" error on first use).
    List<InferenceEngineProvider> inferenceEngines = const [],
    List<EmbeddingBackendProvider> embeddingBackends = const [],
    List<SttBackendProvider> sttBackends = const [],
    List<TtsBackendProvider> ttsBackends = const [],
    // Opt-in agentic "skills" runtime, provided by the `flutter_gemma_agent`
    // package (each executor `implements SkillExecutorProvider`). Core holds
    // only this list + the probe-chain [SkillExecutorRegistry]; the concrete
    // `SkillExecutor` / `SkillResult` types live in the agent package so core
    // stays dependency-free (no webview_flutter / url_launcher). Empty default
    // is a no-op — existing apps are unaffected.
    List<SkillExecutorProvider> skillExecutors = const [],
    VectorStoreRepository? vectorStore,
    // Declares which metadata fields the configured [vectorStore] should make
    // filterable. Threaded to the store via `configure()` at registration,
    // BEFORE its `initialize()`, so it can promote the declared fields to typed
    // storage columns (sqlite/vec0) or top-level payload keys (qdrant). The
    // empty default keeps every store in its existing "filters are a safe
    // no-op" mode.
    FilterSchema filterSchema = const FilterSchema(),

    /// Optional host-provided broadcast of download task updates (mobile).
    ///
    /// On iOS/Android, events must be [TaskUpdate] values from
    /// `package:background_downloader` — the same shape as
    /// [FileDownloader.updates]. Ignored on web. When omitted,
    /// [SmartDownloader] uses its internal broadcast wrapper.
    Stream<Object>? downloadUpdatesStream,

    /// Optional custom model file storage (e.g. outside Documents).
    ///
    /// [FileSystemService] is defined in core but not exported from the
    /// public barrel; pass an implementation from your app or tests.
    FileSystemService? fileSystemService,
  }) async {
    // Migration: enableWebCache takes precedence if provided (for backward compatibility)
    final effectiveStorageMode = enableWebCache != null
        ? (enableWebCache ? WebStorageMode.cacheApi : WebStorageMode.none)
        : webStorageMode;

    await ServiceRegistry.initialize(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: maxDownloadRetries,
      webStorageMode: effectiveStorageMode,
      vectorStoreRepository: vectorStore,
      filterSchema: filterSchema,
      downloadUpdatesStream: downloadUpdatesStream,
      fileSystemService: fileSystemService,
    );

    if (inferenceEngines.isNotEmpty) {
      EngineRegistry.instance.registerAll(inferenceEngines);
    }
    if (embeddingBackends.isNotEmpty) {
      EmbeddingRegistry.instance.registerAll(embeddingBackends);
    }
    if (sttBackends.isNotEmpty) {
      SttRegistry.instance.registerAll(sttBackends);
    }
    if (ttsBackends.isNotEmpty) {
      TtsRegistry.instance.registerAll(ttsBackends);
    }
    if (skillExecutors.isNotEmpty) {
      SkillExecutorRegistry.instance.registerAll(skillExecutors);
    }

    // Single-flight model-manager init: restore the previously-active model
    // identity from storage before the app reads it (#227/#314). Awaited here
    // so the first getActiveModel/isModelInstalled after initialize() can't
    // race an in-flight restore. Restore failure degrades to no-active-model.
    await FlutterGemmaPlugin.instance.modelManager.ensureInitialized();
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

  /// Start building an STT (speech-to-text) model installation
  ///
  /// Returns a type-safe builder for installing STT models (requires model +
  /// tokenizer + [SttInstallationBuilder.ofType]). The model will be
  /// automatically set as the active STT model after installation.
  ///
  /// Example:
  /// ```dart
  /// await FlutterGemma.installStt()
  ///   .modelFromNetwork('https://example.com/model.tflite', token: 'hf_...')
  ///   .tokenizerFromNetwork('https://example.com/tokenizer.json', token: 'hf_...')
  ///   .ofType(SttModelType.moonshine)
  ///   .withModelProgress((p) => print('Model: $p%'))
  ///   .withTokenizerProgress((p) => print('Tokenizer: $p%'))
  ///   .install();
  /// ```
  static SttInstallationBuilder installStt() {
    return SttInstallationBuilder();
  }

  /// Start building a TTS (text-to-speech) model installation
  ///
  /// Returns a type-safe builder for installing TTS models (a bundle of
  /// files, see [TtsInstallationBuilder.ofType]). The model will be
  /// automatically set as the active TTS model after installation.
  ///
  /// Example:
  /// ```dart
  /// await FlutterGemma.installTts()
  ///   .fromNetwork('https://example.com/matcha/', token: 'hf_...')
  ///   .ofType(TtsModelType.matcha)
  ///   .withProgress((p) => print('$p%'))
  ///   .install();
  /// ```
  static TtsInstallationBuilder installTts() {
    return TtsInstallationBuilder();
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
    bool? enableSpeculativeDecoding,
    int? maxConcurrentSessions,
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
      enableSpeculativeDecoding: enableSpeculativeDecoding,
      maxConcurrentSessions: maxConcurrentSessions,
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

  /// Get the active STT model as a ready-to-use [SpeechRecognizer]
  ///
  /// Returns a [SpeechRecognizer] configured with runtime parameters. The
  /// model and tokenizer paths come from the active [SttModelSpec].
  ///
  /// Runtime parameters:
  /// - [preferredBackend]: CPU or GPU preference (optional)
  ///
  /// Throws:
  /// - [StateError] if no active STT model is set
  ///
  /// Example:
  /// ```dart
  /// // Install STT model first
  /// await FlutterGemma.installStt()
  ///   .modelFromNetwork('https://example.com/model.tflite')
  ///   .tokenizerFromNetwork('https://example.com/tokenizer.json')
  ///   .ofType(SttModelType.moonshine)
  ///   .install();
  ///
  /// // Create with default backend
  /// final recognizer = await FlutterGemma.getActiveStt();
  /// ```
  static Future<SpeechRecognizer> getActiveStt({
    PreferredBackend? preferredBackend,
  }) async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final activeSpec = manager.activeSttModel;

    if (activeSpec == null) {
      throw StateError(
        'No active STT model set. Use FlutterGemma.installStt() first.',
      );
    }

    if (activeSpec is! SttModelSpec) {
      throw StateError(
        'Active model is not an SttModelSpec. '
        'Expected SttModelSpec, got ${activeSpec.runtimeType}',
      );
    }

    // Create SpeechRecognizer using active spec (paths resolved automatically)
    return await FlutterGemmaPlugin.instance.createSttModel(
      preferredBackend: preferredBackend,
    );
  }

  /// Check if there's an active STT model
  ///
  /// Returns true if an STT model has been installed and set as active.
  static bool hasActiveStt() {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    return manager.activeSttModel is SttModelSpec;
  }

  /// Get the active TTS model as a ready-to-use [SpeechSynthesizer]
  ///
  /// Returns a [SpeechSynthesizer] configured with runtime parameters. The
  /// bundle paths come from the active [TtsModelSpec].
  ///
  /// Runtime parameters:
  /// - [preferredBackend]: CPU or GPU preference (optional)
  ///
  /// Throws:
  /// - [StateError] if no active TTS model is set
  ///
  /// Example:
  /// ```dart
  /// // Install TTS model first
  /// await FlutterGemma.installTts()
  ///   .fromNetwork('https://example.com/matcha/')
  ///   .ofType(TtsModelType.matcha)
  ///   .install();
  ///
  /// // Create with default backend
  /// final synthesizer = await FlutterGemma.getActiveTts();
  /// ```
  static Future<SpeechSynthesizer> getActiveTts({
    PreferredBackend? preferredBackend,
  }) async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final activeSpec = manager.activeTtsModel;

    if (activeSpec == null) {
      throw StateError(
        'No active TTS model set. Use FlutterGemma.installTts() first.',
      );
    }

    if (activeSpec is! TtsModelSpec) {
      throw StateError(
        'Active model is not a TtsModelSpec. '
        'Expected TtsModelSpec, got ${activeSpec.runtimeType}',
      );
    }

    // Create SpeechSynthesizer using active spec (paths resolved automatically)
    return await FlutterGemmaPlugin.instance.createTtsModel(
      preferredBackend: preferredBackend,
    );
  }

  /// Check if there's an active TTS model
  ///
  /// Returns true if a TTS model has been installed and set as active.
  static bool hasActiveTts() {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    return manager.activeTtsModel is TtsModelSpec;
  }

  /// The active inference model's identity (its [InferenceModelSpec]), or null
  /// if none is set. Cheap synchronous read — does NOT load the engine (use
  /// [getActiveModel] for that). `hasActiveModel() == (activeModelSpec != null)`.
  static InferenceModelSpec? get activeModelSpec {
    final spec = FlutterGemmaPlugin.instance.modelManager.activeInferenceModel;
    if (spec == null || spec is InferenceModelSpec) {
      return spec as InferenceModelSpec?;
    }
    gemmaLog(
      'activeModelSpec: active inference slot holds a ${spec.runtimeType}, '
      'not an InferenceModelSpec — returning null (invariant violation).',
    );
    return null;
  }

  /// The active embedding model's identity ([EmbeddingModelSpec]), or null.
  static EmbeddingModelSpec? get activeEmbedderSpec {
    final spec = FlutterGemmaPlugin.instance.modelManager.activeEmbeddingModel;
    if (spec == null || spec is EmbeddingModelSpec) {
      return spec as EmbeddingModelSpec?;
    }
    gemmaLog(
      'activeEmbedderSpec: active embedding slot holds a ${spec.runtimeType}, '
      'not an EmbeddingModelSpec — returning null (invariant violation).',
    );
    return null;
  }

  /// The active STT model's identity ([SttModelSpec]), or null.
  static SttModelSpec? get activeSttSpec {
    final spec = FlutterGemmaPlugin.instance.modelManager.activeSttModel;
    if (spec == null || spec is SttModelSpec) {
      return spec as SttModelSpec?;
    }
    gemmaLog(
      'activeSttSpec: active STT slot holds a ${spec.runtimeType}, '
      'not an SttModelSpec — returning null (invariant violation).',
    );
    return null;
  }

  /// The active TTS model's identity ([TtsModelSpec]), or null.
  static TtsModelSpec? get activeTtsSpec {
    final spec = FlutterGemmaPlugin.instance.modelManager.activeTtsModel;
    if (spec == null || spec is TtsModelSpec) {
      return spec as TtsModelSpec?;
    }
    gemmaLog(
      'activeTtsSpec: active TTS slot holds a ${spec.runtimeType}, '
      'not an TtsModelSpec — returning null (invariant violation).',
    );
    return null;
  }

  /// Absolute on-device read path for an installed model file, keyed by its
  /// [fileName] (the file's basename, e.g. `gemma-4-E2B-it.litertlm`). On web
  /// this resolves to a URL/OPFS handle, not a filesystem path. The path is
  /// computed, not stat-ed — it is returned even if nothing is installed there.
  static Future<String> getModelPath(String fileName) =>
      ServiceRegistry.instance.fileSystemService.getReadTargetPath(fileName);

  /// Clears the active inference identity (in-memory spec + persisted prefs).
  static Future<void> clearActiveInferenceIdentity() =>
      FlutterGemmaPlugin.instance.modelManager.clearActiveInferenceIdentity();

  /// Clears the active embedding identity (in-memory spec + persisted prefs).
  static Future<void> clearActiveEmbeddingIdentity() =>
      FlutterGemmaPlugin.instance.modelManager.clearActiveEmbeddingIdentity();

  /// Clears the active STT identity (in-memory spec + persisted prefs).
  static Future<void> clearActiveSttIdentity() =>
      FlutterGemmaPlugin.instance.modelManager.clearActiveSttIdentity();

  /// Clears the active TTS identity (in-memory spec + persisted prefs).
  static Future<void> clearActiveTtsIdentity() =>
      FlutterGemmaPlugin.instance.modelManager.clearActiveTtsIdentity();

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

    // Delete files first (if not external/protected) so a file-delete failure
    // leaves the metadata intact and the uninstall retryable — mirrors the
    // safe order used by uninstallEmbedder/Stt/Tts (delete then clear).
    if (modelInfo.source is! FileSource) {
      final targetPath = await fileSystem.getReadTargetPath(modelId);
      await fileSystem.deleteFile(targetPath);
    }

    // Delete metadata last.
    await repository.deleteModel(modelId);
  }

  /// Uninstall the active embedding model — deletes ALL its files (model +
  /// tokenizer) and clears the active-embedder identity. No-op if none active.
  static Future<void> uninstallEmbedder() async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final spec = manager.activeEmbeddingModel;
    if (spec == null) return;
    await manager.deleteModel(spec);
    await manager.clearActiveEmbeddingIdentity();
  }

  /// Uninstall the active STT model — deletes all its files and clears the
  /// active-STT identity. No-op if none active.
  static Future<void> uninstallStt() async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final spec = manager.activeSttModel;
    if (spec == null) return;
    await manager.deleteModel(spec);
    await manager.clearActiveSttIdentity();
  }

  /// Uninstall the active TTS model — deletes all its files and clears the
  /// active-TTS identity. No-op if none active.
  static Future<void> uninstallTts() async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final spec = manager.activeTtsModel;
    if (spec == null) return;
    await manager.deleteModel(spec);
    await manager.clearActiveTtsIdentity();
  }

  /// Delete orphaned files and stale metadata left by interrupted installs.
  static Future<void> performCleanup() =>
      FlutterGemmaPlugin.instance.modelManager.performCleanup();

  /// Current on-device storage usage across installed models.
  static Future<StorageStats> getStorageInfo() =>
      FlutterGemmaPlugin.instance.modelManager.getStorageInfo();

  /// Files on disk that have no matching installed-model metadata.
  static Future<List<OrphanedFileInfo>> getOrphanedFiles() =>
      FlutterGemmaPlugin.instance.modelManager.getOrphanedFiles();

  /// Delete orphaned files; returns the number of files removed.
  static Future<int> cleanupStorage() =>
      FlutterGemmaPlugin.instance.modelManager.cleanupStorage();

  /// Retrieval-augmented-generation (vector store) operations, namespaced.
  ///
  /// Opt-in: requires a RAG package (`flutter_gemma_rag_qdrant` /
  /// `flutter_gemma_rag_sqlite`) registered via
  /// `FlutterGemma.initialize(vectorStore: ...)`. Without one, every call
  /// throws a clear "add a RAG package" error.
  ///
  /// ```dart
  /// await FlutterGemma.rag.initialize('rag.db');
  /// await FlutterGemma.rag.addDocument(id: '1', content: 'hello');
  /// final hits = await FlutterGemma.rag.searchSimilar(query: 'hi');
  /// await FlutterGemma.rag.removeDocument(id: '1');
  /// ```
  static const GemmaRag rag = GemmaRag._();

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
  ///
  /// Nulls the DI singleton WITHOUT closing the active vector store. Prefer
  /// [dispose] when a real store is live (e.g. switching RAG backends at
  /// runtime) so its native handle is released; [reset] alone would leak it.
  static void reset() {
    ServiceRegistry.reset();
  }

  /// Closes the active vector store (releasing its native handle — qdrant-edge
  /// shard / sqlite connection) and then resets the DI singleton.
  ///
  /// Use this instead of [reset] when a configured vector store is live and you
  /// intend to re-[initialize] afterwards (e.g. swapping RAG backends). Safe to
  /// call when uninitialized (no-op). The installed embedder + active inference
  /// model survive — they live in the platform plugin instance + prefs, not the
  /// DI singleton.
  static Future<void> dispose() async {
    try {
      await ServiceRegistry.instance.dispose();
    } on StateError {
      // Not initialized — nothing to dispose.
    }
    ServiceRegistry.reset();
  }
}

/// RAG (retrieval-augmented generation) operations, reached via
/// [FlutterGemma.rag]. Thin, stateless delegator over the vector store;
/// opt-in (see [FlutterGemma.rag]). Modelled as a single const instance
/// purely to give the operations a `rag.` namespace on the facade — it holds
/// no state and is not itself a test seam. To fake RAG in tests, substitute
/// [FlutterGemmaPlugin.instance] (which every method here delegates to).
class GemmaRag {
  const GemmaRag._();

  /// Initialize the vector store database.
  Future<void> initialize(String databasePath) =>
      FlutterGemmaPlugin.instance.initializeVectorStore(databasePath);

  /// Add a document; its embedding is computed automatically (needs an active
  /// embedding model).
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) => FlutterGemmaPlugin.instance.addDocument(
    id: id,
    content: content,
    metadata: metadata,
  );

  /// Add a document with a precomputed embedding.
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) => FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: id,
    content: content,
    embedding: embedding,
    metadata: metadata,
  );

  /// Search for similar documents. [filter] constrains by declared payload
  /// fields (see [FlutterGemmaPlugin.searchSimilar]).
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
    Filter? filter,
  }) => FlutterGemmaPlugin.instance.searchSimilar(
    query: query,
    topK: topK,
    threshold: threshold,
    filter: filter,
  );

  /// Remove a single document by ID. No-op if the ID is absent.
  ///
  /// Call after [initialize]. Before the store is initialized, behavior is
  /// backend-specific (the SQLite store throws a `StateError`; the Qdrant
  /// store logs and no-ops) — don't rely on either.
  Future<void> removeDocument({required String id}) =>
      FlutterGemmaPlugin.instance.removeDocument(id: id);

  /// Vector store statistics.
  Future<VectorStoreStats> stats() =>
      FlutterGemmaPlugin.instance.getVectorStoreStats();

  /// Remove all documents from the vector store.
  Future<void> clear() => FlutterGemmaPlugin.instance.clearVectorStore();
}
