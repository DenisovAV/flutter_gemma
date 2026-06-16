import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;

import 'web/flutter_gemma_web_embedding_model.dart';

/// Web LiteRT embedding backend — builds [WebEmbeddingModel] (LiteRT.js).
class LiteRtEmbeddingBackend implements EmbeddingBackendProvider {
  const LiteRtEmbeddingBackend();

  @override
  String get name => 'LiteRT Embedding';

  @override
  int get priority => 0;

  @override
  bool canHandle(EmbeddingModelSpec spec) => true;

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) async {
    return WebEmbeddingModel(
      modelPath: config.modelPath,
      tokenizerPath: config.tokenizerPath,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }
}
