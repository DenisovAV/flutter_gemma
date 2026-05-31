import 'package:flutter_gemma/pigeon.g.dart' show PreferredBackend;

/// Runtime config for building a model — the per-call params `getActiveModel`
/// collects, kept as a small holder so the provider contract stays stable as
/// params evolve.
class RuntimeConfig {
  const RuntimeConfig({
    required this.maxTokens,
    this.preferredBackend,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxNumImages,
    this.enableSpeculativeDecoding,
    this.maxConcurrentSessions,
  });

  final int maxTokens;
  final PreferredBackend? preferredBackend;
  final bool supportImage;
  final bool supportAudio;
  final int? maxNumImages;
  final bool? enableSpeculativeDecoding;
  final int? maxConcurrentSessions;
}
