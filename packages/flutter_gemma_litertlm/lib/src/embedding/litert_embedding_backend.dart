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
import 'package:flutter_gemma/core/embedding/common_embedding_model.dart'
    show CommonEmbeddingModel;
import 'package:flutter_gemma/core/embedding/forward_pass.dart'
    show EmbeddingOutputContract, ForwardPassDescriptor;
import 'package:flutter_gemma/core/registry/embedding_tokenizer_registry.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/utils/gemma_log.dart';

import 'litert_embedding_forward_pass.dart';

/// Logged once per process. The parameter is passed on every call or none,
/// so repeating the line per embedder would only drown the console.
bool _warnedPreferredBackendIgnored = false;

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
    _warnIfBackendRequested(config.preferredBackend);

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
        // Asked for, not named. Which family this model needs is a fact about
        // the model, not about LiteRT — and hardcoding Gemma SentencePiece
        // here is what made `canHandle => true` a trap: a WordPiece model was
        // accepted and then tokenized with the wrong convention.
        tokenizerFactory: EmbeddingTokenizerRegistry.instance.resolveFor(spec),
        outputContract: EmbeddingOutputContract.pooledFinal,
      ),
      tokenizerPath: tokenizerPath,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }

  /// Says out loud that [PreferredBackend] does not reach this path.
  ///
  /// CPU here is not a fallback: the GPU delegate compiles and then returns
  /// all-zero vectors for EmbeddingGemma's int4 weights, so CPU is the only
  /// answer that is correct. What was wrong was accepting the parameter at
  /// `getActiveEmbedder(preferredBackend:)`, carrying it down through
  /// `RuntimeConfig`, and dropping it without a word.
  void _warnIfBackendRequested(PreferredBackend? requested) {
    if (requested == null || requested == PreferredBackend.cpu) return;
    if (_warnedPreferredBackendIgnored) return;
    _warnedPreferredBackendIgnored = true;
    gemmaLog(
      '[LiteRT/embedding] preferredBackend: ${requested.name} is ignored. '
      'LiteRT embeddings run on CPU, and not as a fallback: the GPU delegate '
      'compiles and then returns all-zero vectors for EmbeddingGemma. Drop '
      'the argument to silence this.',
    );
  }
}
