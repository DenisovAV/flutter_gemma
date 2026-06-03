// `EmbeddingModel` facade over a background isolate (issue #299).
//
// The blocking LiteRT forward pass (`LiteRtRunCompiledModel`) used to run on
// the calling (UI) isolate, freezing the event loop for the whole pass
// (~80ms/call, more on mobile). This facade now owns an [EmbeddingWorker]
// that runs the native lifecycle — lib open, compile-once, tokenize, forward,
// teardown — on a dedicated background isolate, so the UI stays free.
//
// The native code itself lives in `litert_embedding_core.dart` (driven inside
// the worker isolate); this file is just the public, async, main-isolate API.
// Public method signatures are unchanged, so all call sites work as before.
//
// Replaces the per-platform implementations that 0.15.1 shipped (Android
// `EmbeddingModel.kt`, iOS `EmbeddingModel.swift`, desktop tflite C). Web is
// unchanged (LiteRT.js).

import '../../flutter_gemma_interface.dart' show EmbeddingModel, TaskType;
import '../../pigeon.g.dart' show PreferredBackend;
import 'litert_embedding_worker.dart';

/// Signature for the `onClose` callback. Same name Flutter uses.
typedef VoidCallback = void Function();

// Embeddings run on CPU only. The GPU/NPU plumbing exists end-to-end
// (EmbeddingBackend + the LiteRT accelerator flag + the Lock(Read) device→host
// sync), but the GPU delegate currently compiles and then returns all-zero
// vectors (verified on macOS Metal) — so we do NOT expose it yet. The
// `preferredBackend` argument is accepted but ignored for embeddings until the
// GPU path produces correct output. Tracked separately; do NOT silently route
// embeddings onto a broken accelerator.
EmbeddingBackend _backendFor(PreferredBackend? backend) => EmbeddingBackend.cpu;

class LitertEmbeddingModel extends EmbeddingModel {
  LitertEmbeddingModel._(this._worker, this.onClose);

  final EmbeddingWorker _worker;
  final VoidCallback onClose;
  bool _isClosed = false;

  /// Sequence length the model was compiled for (input tensor dim[1]).
  int get inputSequenceLength => _worker.inputSequenceLength;

  /// Output embedding dimension (output tensor dim[1] — 768 for Gecko /
  /// EmbeddingGemma).
  int get outputDimension => _worker.outputDimension;

  /// Load a `.tflite` embedding model from disk and prepare it for inference
  /// on a background isolate.
  ///
  /// [modelPath] points at a `.tflite` file (Gecko 64, EmbeddingGemma 256,
  /// etc.). [tokenizerPath] is the matching SentencePiece `.model` or exported
  /// `.json`. [preferredBackend] is accepted for API symmetry but currently
  /// ignored — embeddings run on CPU (the GPU delegate returns zero vectors;
  /// see `_backendFor`). Input sequence length and output dimension are
  /// auto-detected from the compiled model's tensor layouts; pass them to
  /// override (rare).
  ///
  /// Caller owns the returned instance and must call [close] when done.
  static Future<LitertEmbeddingModel> create({
    required String modelPath,
    required String tokenizerPath,
    PreferredBackend? preferredBackend,
    int? inputSequenceLength,
    int? outputDimension,
    VoidCallback? onClose,
  }) async {
    final worker = await EmbeddingWorker.spawn(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      backend: _backendFor(preferredBackend),
      inputSequenceLength: inputSequenceLength,
      outputDimension: outputDimension,
    );
    return LitertEmbeddingModel._(worker, onClose ?? () {});
  }

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
          'LitertEmbeddingModel is closed; create a new instance to use it');
    }
  }

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) {
    _assertNotClosed();
    return _worker.embed(text, prefix: taskType.prefix);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) {
    _assertNotClosed();
    // Each embed() is a separate request the worker serves in order; the UI
    // isolate stays free between them.
    return Future.wait(
      texts.map((text) => _worker.embed(text, prefix: taskType.prefix)),
    );
  }

  @override
  Future<int> getDimension() async {
    _assertNotClosed();
    return outputDimension;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      await _worker.close();
    } finally {
      onClose();
    }
  }
}
