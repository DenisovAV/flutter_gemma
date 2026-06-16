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
    this.supportImage = false,
    this.supportAudio = false,
    this.maxNumImages,
    this.enableSpeculativeDecoding,
    this.maxConcurrentSessions,
    this.loraRanks,
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

  /// Resolved on-disk path to the tokenizer. Embedding backends only; null for
  /// inference. The spec carries source *identities* (network/asset/file); core
  /// resolves them to on-disk paths via the model manager and passes the
  /// resolved tokenizer path here (install-vs-runtime separation).
  final String? tokenizerPath;

  final PreferredBackend? preferredBackend;
  final bool supportImage;
  final bool supportAudio;
  final int? maxNumImages;
  final bool? enableSpeculativeDecoding;
  final int? maxConcurrentSessions;

  /// LoRA ranks for the MediaPipe path; null falls back to the platform's
  /// `supportedLoraRanks`. Carried in the config so the (cached) default-engine
  /// build closure reads it per call instead of capturing a stale local.
  final List<int>? loraRanks;
}
