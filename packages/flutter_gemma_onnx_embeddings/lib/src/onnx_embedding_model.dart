import 'dart:math' as math;

import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show EmbeddingModel, TaskType;

import 'ort_client.dart';
import 'tokenizer.dart';

/// [EmbeddingModel] implementation that runs ONNX Runtime inference.
///
/// Pipeline per text:
///   1. Prepend [TaskType] prefix, then tokenize via [Tokenizer.encode].
///   2. Run [OrtClient.runEmbedding] to obtain per-token vectors of shape
///      `[seq_len, hidden_size]`.
///   3. Mean-pool over the token dimension → single vector `[hidden_size]`.
///   4. L2-normalise the pooled vector so that dot product equals cosine
///      similarity (‖v‖ ≈ 1.0 within 1e-6).
///
/// Both [ortClient] and [tokenizer] are injected to keep all computation
/// unit-testable without any native code or dlopen calls.
class OnnxEmbeddingModel extends EmbeddingModel with CloseNotifier {
  OnnxEmbeddingModel({
    required this._ortClient,
    required this._tokenizer,
  });

  final OrtClient _ortClient;
  final Tokenizer _tokenizer;
  bool _isClosed = false;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
        'OnnxEmbeddingModel is closed; create a new instance to use it.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // EmbeddingModel interface
  // ---------------------------------------------------------------------------

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    _assertNotClosed();
    final prefixed = taskType.prefix + text;
    final tokenIds = _tokenizer.encode(prefixed);
    final tokenEmbeddings = await _ortClient.runEmbedding(tokenIds);
    return _meanPoolAndNormalize(tokenEmbeddings);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    _assertNotClosed();
    return Future.wait(
      texts.map((text) => generateEmbedding(text, taskType: taskType)),
    );
  }

  @override
  Future<int> getDimension() {
    _assertNotClosed();
    return _ortClient.getDimension();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      await _ortClient.close();
    } finally {
      fireCloseListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Pooling + normalisation helpers
  // ---------------------------------------------------------------------------

  /// Mean-pools [tokenEmbeddings] (shape `[seq_len, hidden_size]`) over the
  /// token axis and L2-normalises the result.
  static List<double> _meanPoolAndNormalize(List<List<double>> tokenEmbeddings) {
    assert(tokenEmbeddings.isNotEmpty, 'Token embeddings must not be empty');

    final seqLen = tokenEmbeddings.length;
    final hiddenSize = tokenEmbeddings.first.length;

    // Mean pool over the sequence-length dimension.
    final pooled = List<double>.filled(hiddenSize, 0.0);
    for (final row in tokenEmbeddings) {
      for (var d = 0; d < hiddenSize; d++) {
        pooled[d] += row[d];
      }
    }
    for (var d = 0; d < hiddenSize; d++) {
      pooled[d] /= seqLen;
    }

    // L2 normalise.
    var norm = 0.0;
    for (final v in pooled) {
      norm += v * v;
    }
    norm = math.sqrt(norm);

    if (norm == 0.0) {
      // Return the zero vector untouched; a zero embedding is degenerate but
      // not an error (e.g. an all-zero model output).
      return pooled;
    }

    return pooled.map((v) => v / norm).toList(growable: false);
  }
}
