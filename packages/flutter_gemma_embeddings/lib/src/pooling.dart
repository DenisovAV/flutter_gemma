// Mean-pool + L2-normalize a `ForwardResult` into a single embedding vector.
//
// Pure function, no engine/isolate/native dependency — the runtime-agnostic
// half of the embedding pipeline (design doc §2). Exercised entirely with
// fake `ForwardResult`s in `test/pooling_test.dart`.

import 'dart:math' as math;

import 'forward_pass.dart';

/// Turns a raw [ForwardResult] into a single L2-normalized embedding vector
/// of length `dim`.
///
/// Handles both output layouts a [EmbeddingForwardPass] can hand back:
///  - `[1, dim]` (already pooled, e.g. LiteRT's compiled-model output) — the
///    values pass through as-is, then get L2-normalized.
///  - `[1, seq, dim]` (per-token hidden states) — mean-pooled over the `seq`
///    axis, then L2-normalized. When [attentionMask] is supplied, positions
///    where the mask is `0` are excluded from the mean (the standard
///    BERT-style masked mean-pool over real tokens only, ignoring padding).
///
/// Throws [ArgumentError] for an unsupported shape (anything but rank 2 or
/// 3), a batch size other than 1, or an [attentionMask] whose length doesn't
/// match the sequence length. Throws [StateError] if every token is masked
/// out (nothing left to average).
List<double> meanPoolAndNormalize(
  ForwardResult result, {
  List<int>? attentionMask,
}) {
  final shape = result.shape;

  final List<double> pooled;
  if (shape.length == 2) {
    pooled = _passThrough(result, shape);
  } else if (shape.length == 3) {
    pooled = _meanPoolOverSeq(result, shape, attentionMask);
  } else {
    throw ArgumentError(
      'Unsupported ForwardResult shape: $shape (expected rank 2 `[1, dim]` '
      'or rank 3 `[1, seq, dim]`)',
    );
  }

  return _l2Normalize(pooled);
}

List<double> _passThrough(ForwardResult result, List<int> shape) {
  _requireBatchOne(shape);
  final dim = shape[1];
  if (result.values.length != dim) {
    throw ArgumentError(
      'ForwardResult.values.length (${result.values.length}) does not '
      'match shape $shape',
    );
  }
  return List<double>.of(result.values);
}

List<double> _meanPoolOverSeq(
  ForwardResult result,
  List<int> shape,
  List<int>? attentionMask,
) {
  _requireBatchOne(shape);
  final seq = shape[1];
  final dim = shape[2];
  if (result.values.length != seq * dim) {
    throw ArgumentError(
      'ForwardResult.values.length (${result.values.length}) does not '
      'match shape $shape',
    );
  }
  if (attentionMask != null && attentionMask.length != seq) {
    throw ArgumentError(
      'attentionMask length (${attentionMask.length}) must match the '
      'sequence length ($seq)',
    );
  }

  final sums = List<double>.filled(dim, 0.0);
  var countedTokens = 0;
  for (var t = 0; t < seq; t++) {
    if (attentionMask != null && attentionMask[t] == 0) continue;
    final base = t * dim;
    for (var d = 0; d < dim; d++) {
      sums[d] += result.values[base + d];
    }
    countedTokens++;
  }
  if (countedTokens == 0) {
    throw StateError(
      'attentionMask masked out every token — nothing left to pool',
    );
  }
  return [for (final s in sums) s / countedTokens];
}

void _requireBatchOne(List<int> shape) {
  if (shape[0] != 1) {
    throw ArgumentError('Expected a batch size of 1, got shape $shape');
  }
}

List<double> _l2Normalize(List<double> vector) {
  var sumSquares = 0.0;
  for (final v in vector) {
    sumSquares += v * v;
  }
  if (sumSquares == 0.0) return vector;
  final norm = math.sqrt(sumSquares);
  return [for (final v in vector) v / norm];
}
