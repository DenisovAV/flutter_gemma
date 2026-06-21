import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;

/// ONNX Runtime–based embedding backend for flutter_gemma.
///
/// Handles [EmbeddingModelSpec]s whose model source resolves to an `.onnx`
/// or `.ort` file.  Full inference is implemented in Task A3; this scaffold
/// exports the provider identity so dependent packages can register it.
class OnnxEmbeddingBackend implements EmbeddingBackendProvider {
  const OnnxEmbeddingBackend();

  @override
  String get name => 'ONNX Embedding';

  @override
  int get priority => 0;

  /// Returns true when the model source path resolves to an `.onnx` or `.ort`
  /// file.
  ///
  /// Uses an exhaustive switch on the sealed [ModelSource] hierarchy so a new
  /// subtype will cause a compile error here rather than silently falling
  /// through.  For [NetworkSource] the URL path is extracted via [Uri.parse]
  /// before checking the extension — this correctly handles signed/token URLs
  /// such as `https://host/model.onnx?token=abc` where the raw URL string
  /// would not end with `.onnx`.
  @override
  bool canHandle(EmbeddingModelSpec spec) {
    final source = spec.modelSource;
    final String path = switch (source) {
      NetworkSource(:final url) => Uri.parse(url).path,
      AssetSource(:final path) => path,
      FileSource(:final path) => path,
      BundledSource(:final resourceName) => resourceName,
    };
    return path.endsWith('.onnx') || path.endsWith('.ort');
  }

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) {
    throw UnimplementedError('Implemented in Task A3');
  }
}
