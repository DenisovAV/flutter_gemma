// LiteRT C API embedding backend — native arm (embedder decoupling plan
// Task 4). Moved from `flutter_gemma_embeddings/lib/src/litert_embedding_backend.dart`
// unchanged in shape: builds a `ForwardPassDescriptor` for
// `createLiteRtEmbeddingForwardPass` and hands it to the runtime-agnostic
// `CommonEmbeddingModel`.

import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'
    show CommonEmbeddingModel, EmbeddingOutputContract, ForwardPassDescriptor;

import 'litert_embedding_forward_pass.dart';

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
    // outputContract MUST be pooledFinal — LiteRT's compiled graph already
    // produces the final pooled/normalized vector; routing it through
    // `meanPoolAndNormalize` a second time would silently add an
    // L2-normalize the LiteRT path never had (Invariant I0).
    return CommonEmbeddingModel.create(
      descriptor: ForwardPassDescriptor(
        engineTag: 'LiteRT',
        modelPath: config.modelPath,
        factory: createLiteRtEmbeddingForwardPass,
        outputContract: EmbeddingOutputContract.pooledFinal,
      ),
      tokenizerPath: tokenizerPath,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }
}
