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

  /// Returns true when the model source path/URL ends with `.onnx` or `.ort`.
  ///
  /// [EmbeddingModelSpec] stores the model as a [ModelSource] (not a raw
  /// path string), so we probe via `encode()` — format `<kind>|<value>` —
  /// which reliably ends with the filename extension for all source kinds
  /// (network, asset, file, bundled).
  @override
  bool canHandle(EmbeddingModelSpec spec) {
    final encoded = spec.modelSource.encode();
    return encoded.endsWith('.onnx') || encoded.endsWith('.ort');
  }

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) {
    throw UnimplementedError('Implemented in Task A3');
  }
}
