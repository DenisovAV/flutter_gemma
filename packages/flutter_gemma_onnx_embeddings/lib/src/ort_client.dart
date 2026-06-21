import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Injectable interface that wraps a single ONNX Runtime session for embedding
/// inference. The separation lets unit tests substitute a fake without loading
/// any native libraries.
abstract class OrtClient {
  /// Run one forward pass for the given [tokenIds].
  ///
  /// Returns the embedding output as a list of rows. For models that produce a
  /// per-token `last_hidden_state` the shape is `[seq_len, hidden_size]`. For
  /// models that produce a pre-pooled `sentence_embedding` the shape is
  /// `[1, hidden_size]` — a single row wrapping the already-pooled vector.
  /// `OnnxEmbeddingModel` mean-pools these rows, so both shapes yield the same
  /// final result (mean of 1 row is identity).
  Future<List<List<double>>> runEmbedding(List<int> tokenIds);

  /// Returns the model's hidden size (number of dimensions per embedding).
  Future<int> getDimension();

  /// Releases the underlying session and any associated resources.
  Future<void> close();
}

/// Production [OrtClient] backed by [flutter_onnxruntime].
///
/// Supports two EmbeddingGemma ONNX output layouts:
///   - `sentence_embedding` (`[batch, hidden_size]`) — pre-pooled; returned as
///     a single-row list so the caller's mean-pool is a no-op.
///   - `last_hidden_state` (`[batch, seq_len, hidden_size]`) — per-token;
///     the batch dimension is stripped and each token row is returned.
///
/// Both input names (`input_ids` and `attention_mask`) are supplied so the
/// model can run correctly with padding-free dynamic-length sequences. The
/// attention mask is all-ones because no padding is applied.
///
/// Callers own the lifecycle — [close] must be called exactly once when the
/// embedding model is closed.
class FlutterOrtClient implements OrtClient {
  FlutterOrtClient._(this._session, this._dimension, this._outputName);

  final OrtSession _session;
  final int _dimension;

  /// The output tensor name to read. Prefer `sentence_embedding` (pre-pooled)
  /// when available; fall back to the first output otherwise.
  final String _outputName;

  /// Load an ONNX model from [modelPath] and probe its embedding dimension by
  /// running a minimal single-token forward pass.
  ///
  /// The dimension probe is necessary because the native macOS/iOS/Android
  /// flutter_onnxruntime plugin returns only `{"name": name}` from
  /// `getOutputInfo()` — no shape is available at session-creation time.
  ///
  /// Throws [StateError] when the model has no outputs or the dimension cannot
  /// be probed.
  static Future<FlutterOrtClient> create(String modelPath) async {
    final runtime = OnnxRuntime();
    final session = await runtime.createSession(modelPath);

    if (session.outputNames.isEmpty) {
      throw StateError(
        'ONNX model at "$modelPath" has no outputs — cannot determine embedding dimension.',
      );
    }

    // Prefer 'sentence_embedding' (shape [batch, hidden]) over
    // 'last_hidden_state' (shape [batch, seq, hidden]) when both exist.
    // Fall back to the first output if neither canonical name is present.
    final outputNames = session.outputNames;
    final String preferredName;
    if (outputNames.contains('sentence_embedding')) {
      preferredName = 'sentence_embedding';
    } else {
      preferredName = outputNames.first;
    }

    // Probe the hidden dimension with a single dummy token (token-id 1).
    // This is the only reliable cross-platform way — getOutputInfo() does not
    // return shape metadata on native platforms (macOS/iOS/Android).
    final int dim;
    {
      final inputNames = session.inputNames;
      final dummyData = Int64List.fromList([1]); // one token
      final dummyTensor = await OrtValue.fromList(dummyData, [1, 1]);
      final dummyMask = await OrtValue.fromList(Int64List.fromList([1]), [1, 1]);
      try {
        final inputs = <String, OrtValue>{inputNames.first: dummyTensor};
        if (inputNames.contains('attention_mask')) {
          inputs['attention_mask'] = dummyMask;
        }
        final outputs = await session.run(inputs);
        final probeTensor = outputs[preferredName];
        if (probeTensor == null) {
          throw StateError(
            'ONNX model at "$modelPath" returned no "$preferredName" output during dimension probe.',
          );
        }
        final raw = await probeTensor.asList();
        await probeTensor.dispose();

        // Extract the last axis size regardless of output shape:
        //   sentence_embedding → [[f0,…,fN]]   → last = list length
        //   last_hidden_state  → [[[f0,…,fN]]] → drill to the leaf list
        dynamic leaf = raw;
        while (leaf is List && leaf.isNotEmpty && leaf.first is List) {
          leaf = leaf.first;
        }
        if (leaf is! List || leaf.isEmpty) {
          throw StateError(
            'ONNX model at "$modelPath" returned an unexpected probe shape.',
          );
        }
        dim = leaf.length;
      } finally {
        await dummyTensor.dispose();
        await dummyMask.dispose();
      }
    }

    if (dim <= 0) {
      throw StateError(
        'ONNX model probed embedding dimension is $dim — cannot be used as embedding dimension.',
      );
    }

    return FlutterOrtClient._(session, dim, preferredName);
  }

  @override
  Future<int> getDimension() async => _dimension;

  @override
  Future<List<List<double>>> runEmbedding(List<int> tokenIds) async {
    // Build 2-D int64 input tensors of shape [1, seq_len].
    final seqLen = tokenIds.length;
    final inputData = Int64List.fromList(tokenIds);
    // All-ones attention mask: no padding is used, every token is real.
    final maskData = Int64List(seqLen)..fillRange(0, seqLen, 1);

    final inputNames = _session.inputNames;
    final inputTensor = await OrtValue.fromList(inputData, [1, seqLen]);
    // Only create the attention_mask tensor when the model declares that input.
    final bool hasMaskInput = inputNames.contains('attention_mask');
    final OrtValue? maskTensor = hasMaskInput
        ? await OrtValue.fromList(maskData, [1, seqLen])
        : null;

    OrtValue? outputTensor;
    try {
      final inputs = <String, OrtValue>{inputNames.first: inputTensor};
      if (hasMaskInput && maskTensor != null) {
        inputs['attention_mask'] = maskTensor;
      }
      final outputs = await _session.run(inputs);
      outputTensor = outputs[_outputName];
      if (outputTensor == null) {
        throw StateError(
          'ONNX session returned no output for "$_outputName".',
        );
      }

      final raw = await outputTensor.asList();

      // Normalise to List<List<double>> regardless of output layout:
      //   [batch, hidden]         → [[hidden]]           (sentence_embedding)
      //   [batch, seq, hidden]    → [[tok0], [tok1], …]  (last_hidden_state)
      //   [hidden]                → [[hidden]]            (edge case: no batch)
      final List<dynamic> rows;
      if (raw.isEmpty) {
        throw StateError('ONNX model returned an empty embedding tensor.');
      }
      if (raw.first is List) {
        if ((raw.first as List).first is List) {
          // Shape [1, seq_len, hidden_size] — strip the batch dimension.
          rows = raw.first as List<dynamic>;
        } else {
          // Shape [1, hidden_size] (sentence_embedding) or [seq_len, hidden_size].
          // For sentence_embedding: one row per batch element; we ran batch=1,
          // so wrap the single flat row in a list so pooling is a no-op.
          if (_outputName == 'sentence_embedding') {
            // raw is [[f0, f1, …, f767]] — already the right shape.
            rows = raw;
          } else {
            rows = raw;
          }
        }
      } else {
        // Flat [hidden_size] — wrap in a list so the caller can pool.
        rows = [raw];
      }

      return rows
          .cast<List<dynamic>>()
          .map((row) => row.cast<num>().map((v) => v.toDouble()).toList())
          .toList();
    } finally {
      await inputTensor.dispose();
      await maskTensor?.dispose();
      await outputTensor?.dispose();
    }
  }

  @override
  Future<void> close() async {
    await _session.close();
  }
}
