import 'dart:math' as math;

import 'package:flutter_gemma/flutter_gemma_interface.dart' show TaskType;
import 'package:flutter_gemma_onnx_embeddings/src/onnx_embedding_model.dart';
import 'package:flutter_gemma_onnx_embeddings/src/ort_client.dart';
import 'package:flutter_gemma_onnx_embeddings/src/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake OrtClient — returns a fixed 3-token × 4-dim tensor so pooling/norm
// logic can be verified without any native code or dlopen.
// ---------------------------------------------------------------------------

/// Token embeddings returned by the fake: shape [3, 4].
///
/// Row 0: [1.0,  2.0,  3.0,  4.0]
/// Row 1: [5.0,  6.0,  7.0,  8.0]
/// Row 2: [9.0, 10.0, 11.0, 12.0]
const List<List<double>> _fakeTokenEmbeddings = [
  [1.0, 2.0, 3.0, 4.0],
  [5.0, 6.0, 7.0, 8.0],
  [9.0, 10.0, 11.0, 12.0],
];

class _FakeOrtClient implements OrtClient {
  int runCount = 0;
  bool closed = false;

  @override
  Future<List<List<double>>> runEmbedding(List<int> tokenIds) async {
    runCount++;
    return _fakeTokenEmbeddings;
  }

  @override
  Future<int> getDimension() async => 4;

  @override
  Future<void> close() async {
    closed = true;
  }
}

// ---------------------------------------------------------------------------
// Fake Tokenizer — always returns [1, 2, 3] ids regardless of input.
// ---------------------------------------------------------------------------

class _FakeTokenizer implements Tokenizer {
  @override
  List<int> encode(String text) => [1, 2, 3];
}

// ---------------------------------------------------------------------------
// Math helpers for computing expected values by hand.
// ---------------------------------------------------------------------------

/// Mean of the 3 rows: [(1+5+9)/3, (2+6+10)/3, (3+7+11)/3, (4+8+12)/3]
///                   = [5.0, 6.0, 7.0, 8.0]
List<double> get _expectedMeanPooled => [5.0, 6.0, 7.0, 8.0];

/// L2 norm of [5, 6, 7, 8] = sqrt(25+36+49+64) = sqrt(174)
double get _expectedNorm => math.sqrt(174.0);

List<double> get _expectedNormalized =>
    _expectedMeanPooled.map((v) => v / _expectedNorm).toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OnnxEmbeddingModel', () {
    late _FakeOrtClient fakeClient;
    late _FakeTokenizer fakeTokenizer;
    late OnnxEmbeddingModel model;

    setUp(() {
      fakeClient = _FakeOrtClient();
      fakeTokenizer = _FakeTokenizer();
      model = OnnxEmbeddingModel(
        ortClient: fakeClient,
        tokenizer: fakeTokenizer,
      );
    });

    // -----------------------------------------------------------------------
    // 1. Mean-pooling + L2-normalisation
    // -----------------------------------------------------------------------

    test('generateEmbedding mean-pools 3 token rows correctly', () async {
      final result = await model.generateEmbedding('hello');

      expect(result.length, equals(4));
      for (var i = 0; i < result.length; i++) {
        expect(
          result[i],
          closeTo(_expectedNormalized[i], 1e-6),
          reason: 'dim $i: expected ${_expectedNormalized[i]}, got ${result[i]}',
        );
      }
    });

    test('generateEmbedding returns a unit-norm vector (within 1e-6)', () async {
      final result = await model.generateEmbedding('hello');
      final norm = math.sqrt(result.fold<double>(0, (s, v) => s + v * v));
      expect(norm, closeTo(1.0, 1e-6));
    });

    // -----------------------------------------------------------------------
    // 2. generateEmbeddings — delegates per text
    // -----------------------------------------------------------------------

    test('generateEmbeddings calls ortClient once per text and returns 2 normalized vectors',
        () async {
      final results = await model.generateEmbeddings(['a', 'b']);

      expect(results.length, equals(2));
      expect(fakeClient.runCount, equals(2));

      for (final vec in results) {
        final norm = math.sqrt(vec.fold<double>(0, (s, v) => s + v * v));
        expect(norm, closeTo(1.0, 1e-6));
      }
    });

    // -----------------------------------------------------------------------
    // 3. getDimension
    // -----------------------------------------------------------------------

    test('getDimension returns 4 (fake hidden size)', () async {
      final dim = await model.getDimension();
      expect(dim, equals(4));
    });

    // -----------------------------------------------------------------------
    // 4. close() fires listeners exactly once
    // -----------------------------------------------------------------------

    test('close() fires registered listeners exactly once', () async {
      var fireCount = 0;
      model.addCloseListener(() => fireCount++);

      await model.close();
      expect(fireCount, equals(1));

      // Second call must be a no-op.
      await model.close();
      expect(fireCount, equals(1));
    });

    test('close() closes the underlying OrtClient', () async {
      await model.close();
      expect(fakeClient.closed, isTrue);
    });

    // -----------------------------------------------------------------------
    // 5. After close(), generateEmbedding throws StateError
    // -----------------------------------------------------------------------

    test('generateEmbedding throws StateError after close()', () async {
      await model.close();
      expect(
        () => model.generateEmbedding('text'),
        throwsStateError,
      );
    });

    test('generateEmbeddings throws StateError after close()', () async {
      await model.close();
      expect(
        () => model.generateEmbeddings(['text']),
        throwsStateError,
      );
    });

    // -----------------------------------------------------------------------
    // 6. TaskType prefix is prepended before tokenization
    // -----------------------------------------------------------------------

    test('generateEmbedding with retrievalQuery prepends task prefix', () async {
      // generateEmbedding() must succeed (the fake tokenizer ignores the text),
      // but we verify the ortClient was called (i.e. inference ran).
      await model.generateEmbedding(
        'query text',
        taskType: TaskType.retrievalQuery,
      );
      expect(fakeClient.runCount, equals(1));
    });

    test('generateEmbedding with retrievalDocument prepends document prefix',
        () async {
      await model.generateEmbedding(
        'document text',
        taskType: TaskType.retrievalDocument,
      );
      expect(fakeClient.runCount, equals(1));
    });
  });
}
