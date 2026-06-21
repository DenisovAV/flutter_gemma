import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Injectable interface that wraps a single ONNX Runtime session for embedding
/// inference. The separation lets unit tests substitute a fake without loading
/// any native libraries.
abstract class OrtClient {
  /// Run one forward pass for the given [tokenIds].
  ///
  /// Returns the raw token-level output of shape `[seq_len, hidden_size]` as a
  /// list of rows, where each row is a vector of [hidden_size] floats.
  Future<List<List<double>>> runEmbedding(List<int> tokenIds);

  /// Returns the model's hidden size (number of dimensions per token vector).
  Future<int> getDimension();

  /// Releases the underlying session and any associated resources.
  Future<void> close();
}

/// Production [OrtClient] backed by [flutter_onnxruntime].
///
/// Callers own the lifecycle — [close] must be called exactly once when the
/// embedding model is closed.
class FlutterOrtClient implements OrtClient {
  FlutterOrtClient._(this._session, this._dimension);

  final OrtSession _session;
  final int _dimension;

  /// Load an ONNX model from [modelPath] and inspect its output shape to
  /// discover [dimension].
  ///
  /// Expects the model to have exactly one output of shape `[*, hidden_size]`
  /// (the `*` is the dynamic sequence-length axis). Throws [StateError] when the
  /// output shape cannot be determined.
  static Future<FlutterOrtClient> create(String modelPath) async {
    final runtime = OnnxRuntime();
    final session = await runtime.createSession(modelPath);

    // Discover the hidden size from output tensor metadata.
    final outputInfoList = await session.getOutputInfo();
    if (outputInfoList.isEmpty) {
      throw StateError(
        'ONNX model at "$modelPath" has no outputs — cannot determine embedding dimension.',
      );
    }
    final outputInfo = outputInfoList.first;
    final shape = outputInfo['shape'] as List?;
    if (shape == null || shape.length < 2) {
      throw StateError(
        'ONNX model output shape is unexpected ($shape); expected at least 2 dimensions.',
      );
    }
    final dim = (shape.last as num).toInt();
    if (dim <= 0) {
      throw StateError(
        'ONNX model output last dimension is $dim — cannot be used as embedding dimension.',
      );
    }

    return FlutterOrtClient._(session, dim);
  }

  @override
  Future<int> getDimension() async => _dimension;

  @override
  Future<List<List<double>>> runEmbedding(List<int> tokenIds) async {
    // Build a 2-D int64 input tensor of shape [1, seq_len].
    final inputName = _session.inputNames.first;
    final inputData = Int64List.fromList(tokenIds);
    final inputTensor = await OrtValue.fromList(inputData, [1, tokenIds.length]);

    OrtValue? outputTensor;
    try {
      final outputs = await _session.run({inputName: inputTensor});
      outputTensor = outputs[_session.outputNames.first];
      if (outputTensor == null) {
        throw StateError('ONNX session returned no output for "${_session.outputNames.first}".');
      }

      // asList() returns a nested list shaped [1, seq_len, hidden_size] or
      // [seq_len, hidden_size]; unwrap the optional batch dimension.
      final raw = await outputTensor.asList();
      final List<dynamic> tokenRows;
      if (raw.first is List && (raw.first as List).first is List) {
        // Shape [1, seq_len, hidden_size] — strip the batch dimension.
        tokenRows = raw.first as List<dynamic>;
      } else {
        // Shape [seq_len, hidden_size]
        tokenRows = raw;
      }

      return tokenRows
          .cast<List<dynamic>>()
          .map((row) => row.cast<num>().map((v) => v.toDouble()).toList())
          .toList();
    } finally {
      await inputTensor.dispose();
      await outputTensor?.dispose();
    }
  }

  @override
  Future<void> close() async {
    await _session.close();
  }
}
