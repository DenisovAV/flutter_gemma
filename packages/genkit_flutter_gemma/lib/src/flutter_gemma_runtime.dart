import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

/// Abstraction over flutter_gemma static API for testability.
///
/// Instead of calling [gemma.FlutterGemma.getActiveModel] directly,
/// production code uses [DefaultFlutterGemmaRuntime] while tests
/// can substitute a fake implementation.
abstract class FlutterGemmaRuntime {
  /// Retrieves the active inference model with the given configuration.
  Future<gemma.InferenceModel> getActiveModel({
    int maxTokens = 1024,
    bool supportImage = false,
    bool supportAudio = false,
    bool? enableSpeculativeDecoding,
  });

  /// Retrieves the active embedding model.
  Future<gemma.EmbeddingModel> getActiveEmbedder({
    gemma.PreferredBackend? preferredBackend,
  });
}

/// Default runtime that delegates to [gemma.FlutterGemma] static methods.
class DefaultFlutterGemmaRuntime implements FlutterGemmaRuntime {
  const DefaultFlutterGemmaRuntime();

  @override
  Future<gemma.InferenceModel> getActiveModel({
    int maxTokens = 1024,
    bool supportImage = false,
    bool supportAudio = false,
    bool? enableSpeculativeDecoding,
  }) {
    return gemma.FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      supportImage: supportImage,
      supportAudio: supportAudio,
      enableSpeculativeDecoding: enableSpeculativeDecoding,
    );
  }

  @override
  Future<gemma.EmbeddingModel> getActiveEmbedder({
    gemma.PreferredBackend? preferredBackend,
  }) {
    return gemma.FlutterGemma.getActiveEmbedder(
      preferredBackend: preferredBackend,
    );
  }
}
