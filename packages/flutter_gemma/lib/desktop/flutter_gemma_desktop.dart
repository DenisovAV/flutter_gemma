import 'dart:async';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:flutter_gemma/core/services/vector_store_filter.dart';

import '../flutter_gemma_interface.dart';
import '../model_file_manager_interface.dart';
import '../core/domain/platform_types.dart';

import '../core/model.dart';
import '../core/di/service_registry.dart';
import '../core/domain/model_source.dart';
import '../core/registry/engine_registry.dart';
import '../core/registry/embedding_registry.dart';
import '../core/registry/embedding_backend_provider.dart';
import '../core/registry/stt_registry.dart';
import '../core/registry/stt_backend_provider.dart';
import '../core/registry/tts_registry.dart';
import '../core/registry/runtime_config.dart';

// Model spec types come from the dart:io-free specs library; the manager
// implementation comes from the mobile library (desktop reuses it).
import '../core/model_management/model_specs.dart'
    show
        EmbeddingModelSpec,
        InferenceModelSpec,
        SttModelSpec,
        SttModelType,
        TtsModelSpec;
import '../mobile/flutter_gemma_mobile.dart' show MobileModelManager;

import '../core/model_management/constants/preferences_keys.dart';

/// Normalizes a `createTtsModel`/`getActiveTts` `language` argument for the
/// same-model reuse guard's store/compare — defaults `null` to `'english'`
/// (mirrors `LiteRtTtsBackend.createModel`'s `config.language ?? 'english'`)
/// and lowercases so `null`, `'english'`, and `'English'` all compare equal
/// (they build the SAME synthesizer either way — `Qwen3Prompt.build` already
/// lowercases the language it's given). Without this, storing/comparing the
/// raw argument tripped a spurious `StateError` for effectively-identical
/// requests (e.g. `getActiveTts()` then `getActiveTts(language: 'english')`).
/// Duplicated from `flutter_gemma_mobile.dart` (same shape, separate shell).
String _normalizeTtsLanguage(String? language) =>
    (language ?? 'english').toLowerCase();

/// Desktop implementation of FlutterGemma plugin
///
/// Uses dart:ffi to communicate directly with LiteRT-LM C API
/// via libLiteRtLm.dylib/so/dll for model inference.
class FlutterGemmaDesktop extends FlutterGemmaPlugin {
  FlutterGemmaDesktop._();

  static FlutterGemmaDesktop? _instance;

  /// Get the singleton instance
  static FlutterGemmaDesktop get instance =>
      _instance ??= FlutterGemmaDesktop._();

  /// Register this implementation as the plugin instance
  ///
  /// This is called automatically by Flutter for dartPluginClass.
  /// No parameters needed for desktop platforms.
  static void registerWith() {
    FlutterGemmaPlugin.instance = instance;
    gemmaLog('[FlutterGemmaDesktop] Plugin registered for desktop platform');
  }

  // Reuse MobileModelManager for desktop (same filesystem behavior)
  late final MobileModelManager _modelManager = MobileModelManager();

  // Inference model singleton
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;
  InferenceModelSpec? _lastActiveInferenceSpec;
  ({bool supportImage, bool supportAudio, int maxTokens})? _lastInferenceParams;

  // Embedding model
  Completer<EmbeddingModel>? _initEmbeddingCompleter;
  EmbeddingModel? _initializedEmbeddingModel;
  String? _lastActiveEmbeddingModelName;

  // STT model
  Completer<SpeechRecognizer>? _initSttCompleter;
  SpeechRecognizer? _initializedSttModel;
  String? _lastActiveSttModelName;

  // TTS model
  Completer<SpeechSynthesizer>? _initTtsCompleter;
  SpeechSynthesizer? _initializedTtsModel;
  TtsModelSpec?
  _lastActiveTtsSpec; // Track which spec was used to create _initializedTtsModel
  // The `language` the active singleton was built with, NORMALIZED
  // ([_normalizeTtsLanguage] — defaulted + lowercased) so a same-effective-
  // language request compared raw-to-raw (e.g. null vs. 'english', or
  // 'English' vs. 'english') doesn't spuriously trip the guard below.
  // Reusing the singleton for a genuinely DIFFERENT language would silently
  // emit wrong-language audio with no error — see the same-model branch in
  // createTtsModel below.
  String? _lastActiveTtsLanguage;

  @override
  ModelFileManager get modelManager => _modelManager;

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
    PreferredBackend? preferredVisionBackend,
    PreferredBackend? preferredAudioBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
    bool supportAudio = false,
    bool? enableSpeculativeDecoding,
    int? maxConcurrentSessions,
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

      final modelChanged = currentSpec.name != requestedSpec.name;
      final p = _lastInferenceParams;
      final paramsChanged =
          p != null &&
          (p.supportImage != supportImage ||
              p.supportAudio != supportAudio ||
              p.maxTokens != maxTokens);

      if (modelChanged || paramsChanged) {
        gemmaLog(
          'Model recreation: modelChanged=$modelChanged, paramsChanged=$paramsChanged',
        );
        await _initializedModel?.close();
        _initCompleter = null;
        _initializedModel = null;
        _lastActiveInferenceSpec = null;
        _lastInferenceParams = null;
      } else {
        gemmaLog('Reusing existing model instance for ${requestedSpec.name}');
        return _initCompleter!.future;
      }
    }

    // Return existing completer if initialization in progress
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }

    final completer = _initCompleter = Completer<InferenceModel>();

    try {
      final specForGates = activeModel as InferenceModelSpec;
      final isBuiltIn = specForGates.fileType == ModelFileType.builtIn;

      String modelPath = '';
      if (!isBuiltIn) {
        // Verify model is installed
        final isInstalled = await _modelManager.isModelInstalled(activeModel);
        if (!isInstalled) {
          throw Exception('Active model is no longer installed');
        }

        // Get model file path
        final modelFilePaths = await _modelManager.getModelFilePaths(
          activeModel,
        );
        if (modelFilePaths == null || modelFilePaths.isEmpty) {
          throw Exception('Model file paths not found');
        }

        modelPath = modelFilePaths.values.first;
        gemmaLog('[FlutterGemmaDesktop] Using model: $modelPath');
      } else {
        gemmaLog(
          '[FlutterGemmaDesktop] Built-in model ${specForGates.name}: '
          'skipping file/installed checks (no on-disk file)',
        );
      }

      // Core resolves the model path + owns the singleton lifecycle, then
      // dispatches construction polymorphically through the EngineRegistry.
      // Desktop registers NO default engine — the LiteRtLmEngine is supplied
      // via FlutterGemma.initialize(inferenceEngines:). If the registry is
      // empty (or no engine canHandle the spec), the findFor==null StateError
      // below fires. Desktop is litertlm-only; a `.task` request would simply
      // find no matching engine.
      final spec = specForGates;
      final config = RuntimeConfig(
        maxTokens: maxTokens,
        modelPath: modelPath,
        preferredBackend: preferredBackend,
        preferredVisionBackend: preferredVisionBackend,
        preferredAudioBackend: preferredAudioBackend,
        supportImage: supportImage,
        supportAudio: supportAudio,
        maxNumImages: maxNumImages,
        enableSpeculativeDecoding: enableSpeculativeDecoding,
        maxConcurrentSessions: maxConcurrentSessions,
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
      _lastInferenceParams = (
        supportImage: supportImage,
        supportAudio: supportAudio,
        maxTokens: maxTokens,
      );
      model.addCloseListener(() {
        _initializedModel = null;
        _initCompleter = null;
        _lastActiveInferenceSpec = null;
        _lastInferenceParams = null;
      });

      _lastActiveInferenceSpec = spec;
      completer.complete(model);
      return model;
    } catch (e, st) {
      completer.completeError(e, st);
      _initCompleter = null;
      _initializedModel = null;
      _lastActiveInferenceSpec = null;
      _lastInferenceParams = null;
      // Return the error-completed completer future (not rethrow) so exactly one
      // Future is in flight — a bare rethrow orphans completer.future. See #394.
      return completer.future;
    }
  }

  @override
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Check if active embedding model changed
    final currentActiveModel = _modelManager.activeEmbeddingModel;
    if (_initEmbeddingCompleter != null &&
        _initializedEmbeddingModel != null &&
        _lastActiveEmbeddingModelName != null) {
      final modelChanged =
          currentActiveModel == null ||
          currentActiveModel.name != _lastActiveEmbeddingModelName;
      if (modelChanged) {
        await _initializedEmbeddingModel?.close();
        _initEmbeddingCompleter = null;
        _initializedEmbeddingModel = null;
        _lastActiveEmbeddingModelName = null;
      } else {
        return _initEmbeddingCompleter!.future;
      }
    }

    // Return existing if initialization in progress
    if (_initEmbeddingCompleter case Completer<EmbeddingModel> completer) {
      return completer.future;
    }

    final completer = _initEmbeddingCompleter = Completer<EmbeddingModel>();

    try {
      // Resolve model and tokenizer paths from active embedding model
      if (modelPath == null || tokenizerPath == null) {
        final activeModel = _modelManager.activeEmbeddingModel;
        if (activeModel == null) {
          throw StateError(
            'No active embedding model set. '
            'Use `FlutterGemma.installEmbedder()` first.',
          );
        }

        final filePaths = await _modelManager.getModelFilePaths(activeModel);
        if (filePaths == null || filePaths.isEmpty) {
          throw StateError('Embedding model file paths not found');
        }

        modelPath ??= filePaths[PreferencesKeys.embeddingModelFile];
        tokenizerPath ??= filePaths[PreferencesKeys.embeddingTokenizerFile];
      }

      if (modelPath == null) {
        throw StateError('Embedding model path is required');
      }

      gemmaLog('[FlutterGemmaDesktop] Loading embedding model: $modelPath');

      if (tokenizerPath == null) {
        throw StateError('Tokenizer path is required for desktop embeddings');
      }
      if (preferredBackend == PreferredBackend.npu) {
        throw UnsupportedError(
          'PreferredBackend.npu is only supported on Android with .litertlm '
          'models; not available for desktop embeddings.',
        );
      }

      // The LiteRT embedding runtime moved to flutter_gemma_embeddings; core
      // resolves paths (preamble above) + owns the singleton lifecycle, then
      // dispatches construction through the EmbeddingRegistry. The backend
      // reads ONLY config.modelPath/config.tokenizerPath — it ignores the spec
      // arg for path resolution.
      final activeSpec = currentActiveModel is EmbeddingModelSpec
          ? currentActiveModel
          : null;
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
      // modelPath/tokenizerPath are non-null here (resolved in the preamble).
      // maxTokens is unused by embeddings.
      final embConfig = RuntimeConfig(
        maxTokens: 0,
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        preferredBackend: preferredBackend,
      );
      // The backend's createModel(spec, config) signature requires a non-null
      // spec, but it resolves paths exclusively from config. On the legacy
      // explicit-paths path there is no active spec, so synthesize one from the
      // resolved file paths (FileSource) purely to satisfy the signature.
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
        _lastActiveEmbeddingModelName = null;
      });

      _lastActiveEmbeddingModelName = currentActiveModel?.name;
      completer.complete(model);
      return model;
    } catch (e, st) {
      completer.completeError(e, st);
      _initEmbeddingCompleter = null;
      _initializedEmbeddingModel = null;
      _lastActiveEmbeddingModelName = null;
      // Return the error-completed completer future (not rethrow) so exactly one
      // Future is in flight — a bare rethrow orphans completer.future. See #394.
      return completer.future;
    }
  }

  @override
  Future<SpeechRecognizer> createSttModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Check if active STT model changed
    final currentActiveModel = _modelManager.activeSttModel;
    if (_initSttCompleter != null &&
        _initializedSttModel != null &&
        _lastActiveSttModelName != null) {
      final modelChanged =
          currentActiveModel == null ||
          currentActiveModel.name != _lastActiveSttModelName;
      if (modelChanged) {
        await _initializedSttModel?.close();
        _initSttCompleter = null;
        _initializedSttModel = null;
        _lastActiveSttModelName = null;
      } else {
        return _initSttCompleter!.future;
      }
    }

    // Return existing if initialization in progress
    if (_initSttCompleter case Completer<SpeechRecognizer> completer) {
      return completer.future;
    }

    final completer = _initSttCompleter = Completer<SpeechRecognizer>();

    try {
      // Resolve model and tokenizer paths from active STT model
      if (modelPath == null || tokenizerPath == null) {
        final activeModel = _modelManager.activeSttModel;
        if (activeModel == null) {
          throw StateError(
            'No active STT model set. '
            'Use `FlutterGemma.installStt()` first.',
          );
        }

        final filePaths = await _modelManager.getModelFilePaths(activeModel);
        if (filePaths == null || filePaths.isEmpty) {
          throw StateError('STT model file paths not found');
        }

        modelPath ??= filePaths[PreferencesKeys.sttModelFile];
        tokenizerPath ??= filePaths[PreferencesKeys.sttTokenizerFile];
      }

      if (modelPath == null) {
        throw StateError('STT model path is required');
      }

      gemmaLog('[FlutterGemmaDesktop] Loading STT model: $modelPath');

      if (tokenizerPath == null) {
        throw StateError('Tokenizer path is required for desktop STT');
      }

      // Dispatches construction through the SttRegistry (probe-chain, mirrors
      // EmbeddingRegistry). The backend reads spec.sttModelType to select its
      // runtime profile, and ONLY config.modelPath/config.tokenizerPath for
      // path resolution.
      final activeSpec = currentActiveModel is SttModelSpec
          ? currentActiveModel
          : null;
      final SttBackendProvider? backend = activeSpec != null
          ? SttRegistry.instance.findFor(activeSpec)
          : (SttRegistry.instance.registered.isNotEmpty
                ? SttRegistry.instance.registered.first
                : null);
      if (backend == null) {
        throw StateError(
          'No STT backend registered. Add flutter_gemma_speech to '
          'pubspec.yaml and pass it in sttBackends: of '
          'FlutterGemma.initialize(...). Registered backends: '
          '${SttRegistry.instance.registered.map((b) => b.name).join(", ")}.',
        );
      }
      // modelPath/tokenizerPath are non-null here (resolved in the preamble).
      // maxTokens is unused by STT.
      final sttConfig = RuntimeConfig(
        maxTokens: 0,
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        preferredBackend: preferredBackend,
      );
      // The backend's createModel(spec, config) signature requires a non-null
      // spec, but it resolves paths exclusively from config. On the legacy
      // explicit-paths path there is no active spec, so synthesize one from the
      // resolved file paths (FileSource) purely to satisfy the signature.
      // sttModelType defaults to moonshine — the only shipped profile — for
      // this legacy-path fallback.
      final specForBackend =
          activeSpec ??
          SttModelSpec(
            name: 'legacy:${path.basename(modelPath)}',
            modelSource: ModelSource.file(modelPath),
            tokenizerSource: ModelSource.file(tokenizerPath),
            sttModelType: SttModelType.moonshine,
          );
      final model = await backend.createModel(specForBackend, sttConfig);

      // Core owns the singleton lifecycle: track it + reset on close. The
      // package-built model fires this via CloseNotifier (addCloseListener).
      _initializedSttModel = model;
      model.addCloseListener(() {
        _initializedSttModel = null;
        _initSttCompleter = null;
        _lastActiveSttModelName = null;
      });

      _lastActiveSttModelName = currentActiveModel?.name;
      completer.complete(model);
      return model;
    } catch (e, st) {
      completer.completeError(e, st);
      _initSttCompleter = null;
      _initializedSttModel = null;
      _lastActiveSttModelName = null;
      // Return the error-completed completer future (not rethrow) so exactly one
      // Future is in flight — a bare rethrow orphans completer.future. See #394.
      return completer.future;
    }
  }

  @override
  Future<SpeechSynthesizer> createTtsModel({
    PreferredBackend? preferredBackend,
    String? language,
  }) async {
    final activeModel = _modelManager.activeTtsModel;
    if (activeModel is! TtsModelSpec) {
      throw StateError(
        'No active TTS model set. Use FlutterGemma.installTts() first.',
      );
    }

    // Check if singleton exists and matches the active model
    if (_initTtsCompleter != null &&
        _initializedTtsModel != null &&
        _lastActiveTtsSpec != null) {
      if (_lastActiveTtsSpec!.name != activeModel.name) {
        // Active model changed - close old model and create new one.
        // Reset the singleton fields BEFORE awaiting close() so a concurrent
        // createTtsModel() can't pass the guard mid-close and spawn a duplicate
        // worker (which would then be orphaned → native leak). Capture the old
        // model first, then close it after the reset.
        final old = _initializedTtsModel;
        _initTtsCompleter = null;
        _initializedTtsModel = null;
        _lastActiveTtsSpec = null;
        _lastActiveTtsLanguage = null;
        await old?.close();
      } else if (_normalizeTtsLanguage(language) != _lastActiveTtsLanguage) {
        // Same model, but a DIFFERENT language was requested — reusing the
        // singleton here would silently emit WRONG-LANGUAGE audio with no
        // error. Fail loud instead of reusing: the caller must close() the
        // existing synthesizer first (tts_screen.dart already does this on
        // every model/language switch — see LiteRtSpeechSynthesizer/
        // getActiveTts's docs). Both
        // sides are normalized ([_normalizeTtsLanguage]) so this only fires
        // for a GENUINELY different language, not e.g. null vs. 'english'
        // or 'English' vs. 'english'.
        throw StateError(
          'Active TTS synthesizer was created for language '
          "'$_lastActiveTtsLanguage'; call close() before requesting "
          "'${_normalizeTtsLanguage(language)}'.",
        );
      } else {
        // Same model, same language - return existing singleton
        return _initTtsCompleter!.future;
      }
    }

    // Return existing if initialization in progress
    if (_initTtsCompleter case Completer<SpeechSynthesizer> completer) {
      return completer.future;
    }

    final completer = _initTtsCompleter = Completer<SpeechSynthesizer>();

    try {
      final filePaths = await _modelManager.getModelFilePaths(activeModel);
      if (filePaths == null || filePaths.isEmpty) {
        throw StateError(
          'Active TTS model files not found on disk. Reinstall via installTts().',
        );
      }
      final config = RuntimeConfig(
        maxTokens: 0,
        modelPath: filePaths
            .values
            .first, // representative; TTS backend uses artifactPaths
        artifactPaths: filePaths,
        preferredBackend: preferredBackend,
        language: language,
      );
      final backend = TtsRegistry.instance.findFor(activeModel);
      if (backend == null) {
        throw StateError(
          TtsRegistry.instance.hasAny
              ? 'No registered TTS backend can handle this model '
                    '(${activeModel.ttsModelType}). Registered: '
                    '${TtsRegistry.instance.registered.map((b) => b.name).join(", ")}.'
              : 'No TTS backend registered. Pass ttsBackends: to FlutterGemma.initialize().',
        );
      }
      gemmaLog(
        'Using active TTS model: ${activeModel.name} (${filePaths.length} files)',
      );
      final synth = await backend.createModel(activeModel, config);

      // Core owns the singleton lifecycle: track it + reset on close. The
      // package-built model fires this via CloseNotifier (addCloseListener).
      _initializedTtsModel = synth;
      _lastActiveTtsSpec = activeModel;
      _lastActiveTtsLanguage = _normalizeTtsLanguage(language);
      synth.addCloseListener(() {
        // Only reset if this close-listener still belongs to the current
        // singleton — a newer model may already have replaced it (the
        // model-changed branch above resets the fields synchronously).
        if (identical(_initializedTtsModel, synth)) {
          _initializedTtsModel = null;
          _initTtsCompleter = null;
          _lastActiveTtsSpec = null;
          _lastActiveTtsLanguage = null;
        }
      });

      completer.complete(synth);
      return synth;
    } catch (e, st) {
      completer.completeError(e, st);
      _initTtsCompleter = null;
      _initializedTtsModel = null;
      _lastActiveTtsSpec = null;
      _lastActiveTtsLanguage = null;
      // Return the completer's future (rather than a bare rethrow) so there
      // is exactly one Future in flight for this call — an unheeded
      // `completer.future` (left behind whenever no concurrent caller
      // grabbed a reference to it first) would otherwise surface as an
      // unhandled async error.
      return completer.future;
    }
  }

  // === RAG Methods ===

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
  Future<void> removeDocument({required String id}) async {
    await ServiceRegistry.instance.vectorStoreRepository.removeDocument(id: id);
  }

  @override
  bool get enableHnsw =>
      ServiceRegistry.instance.vectorStoreRepository.enableHnsw;

  @override
  set enableHnsw(bool value) {
    ServiceRegistry.instance.vectorStoreRepository.enableHnsw = value;
  }
}

/// Check if current platform is desktop
bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}
