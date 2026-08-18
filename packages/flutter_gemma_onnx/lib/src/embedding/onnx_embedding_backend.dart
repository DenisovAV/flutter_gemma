// ONNX Runtime embedding backend (Phase 2 — plain-ORT embedding forward
// pass, hardened plan Task 3). Mirrors `flutter_gemma_litertlm`'s
// `LiteRtEmbeddingBackend` shape: builds a `ForwardPassDescriptor` and hands
// it to the runtime-agnostic `CommonEmbeddingModel`.

import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'
    show CommonEmbeddingModel, EmbeddingOutputContract, ForwardPassDescriptor;

import 'onnx_embedding_forward_pass.dart';
import 'onnx_tokenizer_loader.dart';

/// ONNX Runtime embedding backend — plain ORT forward pass (no GenAI, no
/// text generation) over an `.onnx`/`.ort` embedding model directory. Pure
/// factory; core owns the singleton lifecycle via
/// [EmbeddingModel.addCloseListener].
///
/// Priority 10 (above LiteRT's catch-all 0) so an app that registers both
/// backends and installs an `.onnx` model gets this one, not LiteRT's
/// `canHandle: true` catch-all.
class OnnxEmbeddingBackend implements EmbeddingBackendProvider {
  const OnnxEmbeddingBackend();

  @override
  String get name => 'ONNX Embedding';

  @override
  int get priority => 10;

  /// `EmbeddingModelSpec` has no `fileType` field (unlike
  /// `InferenceModelSpec`) — the installed model file's extension is this
  /// backend's identity signal instead. `.onnx` (single-file export) and
  /// `.ort` (ORT-optimized format) both route here. `spec.files.first` is
  /// always the model file (see `EmbeddingModelSpec.files`: `[modelFile,
  /// tokenizerFile]`).
  @override
  bool canHandle(EmbeddingModelSpec spec) {
    final modelFilename = spec.files.first.filename;
    return modelFilename.endsWith('.onnx') || modelFilename.endsWith('.ort');
  }

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) async {
    final tokenizerPath = config.tokenizerPath;
    if (tokenizerPath == null) {
      throw StateError(
        'OnnxEmbeddingBackend requires config.tokenizerPath (resolved by '
        'core from the active embedding model).',
      );
    }
    return CommonEmbeddingModel.create(
      descriptor: ForwardPassDescriptor(
        engineTag: 'ONNX',
        modelPath: config.modelPath,
        factory: createOnnxEmbeddingForwardPass,
        tokenizerFactory: loadOnnxEmbeddingTokenizer,
        // Default only — the real value is discovered once the ONNX session
        // opens and its output names are visible, then reported per-request
        // via `OnnxEmbeddingForwardPass.outputContract` (design D-T2). The
        // worker resolves `pass.outputContract ?? descriptor.outputContract`,
        // so this default is never actually used once `load()` completes.
        outputContract: EmbeddingOutputContract.tokenLevel,
      ),
      tokenizerPath: tokenizerPath,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }
}
