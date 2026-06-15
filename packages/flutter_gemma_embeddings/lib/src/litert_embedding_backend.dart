import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;

import 'litert/litert_embedding_model.dart';

/// LiteRT C API embedding backend (Gecko / EmbeddingGemma `.tflite`). Pure
/// factory; core owns the singleton lifecycle via [EmbeddingModel.addCloseListener].
class LiteRtEmbeddingBackend implements EmbeddingBackendProvider {
  const LiteRtEmbeddingBackend();

  @override
  String get name => 'LiteRT Embedding';

  @override
  int get priority => 0;

  @override
  bool canHandle(EmbeddingModelSpec spec) => true; // sole embedding backend

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) async {
    final tokenizerPath = config.tokenizerPath;
    if (tokenizerPath == null) {
      throw StateError(
        'LiteRtEmbeddingBackend requires config.tokenizerPath (resolved by '
        'core from the active embedding model).',
      );
    }
    return LitertEmbeddingModel.create(
      modelPath: config.modelPath,
      tokenizerPath: tokenizerPath,
      preferredBackend: config.preferredBackend,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }
}
