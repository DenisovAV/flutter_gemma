import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;

/// Runtime config for building a model — the per-call params `getActiveModel`
/// collects, kept as a small holder so the provider contract stays stable as
/// params evolve.
class RuntimeConfig {
  const RuntimeConfig({
    required this.maxTokens,
    required this.modelPath,
    this.tokenizerPath,
    this.preferredBackend,
    this.preferredVisionBackend,
    this.preferredAudioBackend,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxNumImages,
    this.enableSpeculativeDecoding,
    this.maxConcurrentSessions,
    this.loraRanks,
    this.artifactPaths,
    this.language,
  }) : assert(maxTokens >= 0, 'maxTokens must not be negative'),
       assert(
         maxNumImages == null || maxNumImages >= 0,
         'maxNumImages must not be negative',
       ),
       assert(
         maxConcurrentSessions == null || maxConcurrentSessions > 0,
         'maxConcurrentSessions must be positive when set',
       );

  final int maxTokens;

  /// Resolved on-disk path to the model file. Core's platform `createModel`
  /// preamble resolves it from the active spec via the model manager and passes
  /// it here so the engine package never touches core's file-path resolution.
  ///
  /// Empty on web: the web engines resolve the model source themselves via
  /// `WebModelSourceResolver` (there is no on-disk path), so this is `''` there.
  /// Hence there is no non-empty assert on it.
  final String modelPath;

  /// Resolved on-disk path to the tokenizer. Used by embedding and STT
  /// backends; null for inference. The spec carries source *identities*
  /// (network/asset/file); core
  /// resolves them to on-disk paths via the model manager and passes the
  /// resolved tokenizer path here (install-vs-runtime separation).
  final String? tokenizerPath;

  final PreferredBackend? preferredBackend;

  /// Backend for the VISION encoder, independent of [preferredBackend] (the
  /// text/decoder backend). Null defaults to CPU in the LiteRT-LM engine,
  /// because the vision encoder's `STABLEHLO_COMPOSITE` ops fail to prepare on
  /// the Metal/WebGPU delegates (LiteRT-LM#2461). Set it (e.g. to
  /// `PreferredBackend.gpu`) only for a model whose vision section bakes a
  /// gpu-only `backend_constraint`. Ignored by the MediaPipe engine (whole-model
  /// backend, no per-encoder split).
  final PreferredBackend? preferredVisionBackend;

  /// Backend for the AUDIO encoder, independent of [preferredBackend]. Null
  /// defaults to CPU in the LiteRT-LM engine as a conservative default — but,
  /// unlike the vision encoder, the audio encoder runs fine on GPU and is often
  /// faster there (Gemma 3n audio is ~2× CPU on Metal), so set it to
  /// `PreferredBackend.gpu` for speed. Ignored by MediaPipe.
  final PreferredBackend? preferredAudioBackend;
  final bool supportImage;
  final bool supportAudio;
  final int? maxNumImages;
  final bool? enableSpeculativeDecoding;
  final int? maxConcurrentSessions;

  /// LoRA ranks for the MediaPipe path; null falls back to the platform's
  /// `supportedLoraRanks`. Carried in the config so the (cached) default-engine
  /// build closure reads it per call instead of capturing a stale local.
  final List<int>? loraRanks;

  /// filename → on-disk path for a multi-file model bundle (TTS). The bundle
  /// backend resolves each graph/dictionary/embedding file by name from this
  /// map. Null for single-file models (inference/embedding/STT).
  final Map<String, String>? artifactPaths;

  /// TTS-only (Qwen3): the language to condition generation on — one of
  /// `flutter_gemma_speech`'s `qwen3SupportedLanguages`, or `'auto'`. Null
  /// for non-TTS models, and for TTS models with no language parameter
  /// (e.g. Matcha, whose locale comes from its `TtsModelProfile.locale`
  /// instead) — the TTS backend defaults a null value to `'english'`. Not
  /// validated here; the TTS backend rejects an unsupported value with
  /// `ArgumentError` before loading the model.
  final String? language;
}

/// The runtime knobs a caller passes to `getActiveModel`, captured so a second
/// call can tell whether the cached singleton still satisfies the request.
///
/// This exists because the check was written twice and drifted. Mobile compared
/// nothing beyond the model name, so `getActiveModel(preferredBackend: cpu)`
/// after a GPU creation silently returned the GPU model; desktop compared three
/// of the nine parameters, so the other six were equally silent there. Two
/// copies of one rule is how the copies stop agreeing — keep the comparison
/// here and let both shells call it.
class ActiveModelParams {
  const ActiveModelParams({
    required this.maxTokens,
    this.preferredBackend,
    this.preferredVisionBackend,
    this.preferredAudioBackend,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxNumImages,
    this.enableSpeculativeDecoding,
    this.maxConcurrentSessions,
  });

  final int maxTokens;
  final PreferredBackend? preferredBackend;
  final PreferredBackend? preferredVisionBackend;
  final PreferredBackend? preferredAudioBackend;
  final bool supportImage;
  final bool supportAudio;
  final int? maxNumImages;
  final bool? enableSpeculativeDecoding;
  final int? maxConcurrentSessions;

  /// Name of the first parameter that differs from [other], or null when the
  /// cached model can be reused.
  ///
  /// Returns the NAME rather than a bool so the caller can say which knob
  /// forced the reload. "Model recreation: paramsChanged=true" tells nobody
  /// what to change.
  String? firstDifference(ActiveModelParams other) {
    if (maxTokens != other.maxTokens) return 'maxTokens';
    if (preferredBackend != other.preferredBackend) return 'preferredBackend';
    if (preferredVisionBackend != other.preferredVisionBackend) {
      return 'preferredVisionBackend';
    }
    if (preferredAudioBackend != other.preferredAudioBackend) {
      return 'preferredAudioBackend';
    }
    if (supportImage != other.supportImage) return 'supportImage';
    if (supportAudio != other.supportAudio) return 'supportAudio';
    if (maxNumImages != other.maxNumImages) return 'maxNumImages';
    if (enableSpeculativeDecoding != other.enableSpeculativeDecoding) {
      return 'enableSpeculativeDecoding';
    }
    if (maxConcurrentSessions != other.maxConcurrentSessions) {
      return 'maxConcurrentSessions';
    }
    return null;
  }
}
