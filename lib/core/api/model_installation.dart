import 'package:flutter_gemma/core/domain/model_source.dart';

/// Represents a successfully installed model
///
/// Created after successful installation via [ModelInstallationBuilder].
/// Can be used to load the model for inference or embedding tasks.
///
/// Usage:
/// ```dart
/// final installation = await FlutterGemma.installModel()
///   .fromNetwork('https://example.com/model.bin')
///   .install();
///
/// // Later: load for inference (Phase 5 - not yet implemented)
/// // final model = await installation.loadForInference();
/// ```
class ModelInstallation {
  final ModelSource source;

  const ModelInstallation({required this.source});

  /// Gets model ID (filename)
  String get modelId {
    return switch (source) {
      NetworkSource(:final url) => _extractFilename(url),
      AssetSource(:final path) => _extractFilename(path),
      BundledSource(:final resourceName) => resourceName,
      FileSource(:final path) => _extractFilename(path),
    };
  }

  String _extractFilename(String path) {
    final segments = path.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  // Phase 5: These methods will integrate with existing InferenceModel
  // For now, they're placeholders showing the intended API

  /// Load model for inference tasks (text generation, chat, etc.)
  ///
  /// TODO: Phase 5 - integrate with existing InferenceModel
  Future<void> loadForInference() async {
    throw UnimplementedError('Phase 5: Integration with InferenceModel');
  }

  /// Load model for embedding tasks (vector generation)
  ///
  /// TODO: Phase 5 - integrate with existing embedding functionality
  Future<void> loadForEmbedding() async {
    throw UnimplementedError('Phase 5: Integration with embedding functionality');
  }
}
