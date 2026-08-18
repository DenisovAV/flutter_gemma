// Host tests for `embedding_worker.dart` — the generalized background-
// isolate worker that drives a runtime-agnostic [EmbeddingForwardPass]
// (embedder decoupling plan Task 5).
//
// Uses a fake [EmbeddingForwardPass] built exclusively via top-level factory
// tear-offs (as required by `ForwardPassDescriptor.factory`'s doc — the
// worker genuinely `Isolate.spawn`s, so the fake must survive the same
// boundary the isolate test proves). A tiny synthetic SentencePiece
// tokenizer (built in-memory, no checked-in model asset) supplies real
// tokenization so token-stream assertions (Invariant I1) are exact.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_gemma_embeddings/src/embedding_worker.dart';
import 'package:flutter_gemma_embeddings/src/forward_pass.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake forward pass: echoes the (padded/truncated — here untouched, no
/// padding needed) tokenIds it received back as the "embedding" — a
/// deterministic way to prove exactly what token stream reached `run()`
/// without any cross-isolate side channel. Also supports a fixed canned
/// [ForwardResult] for the pooling-contract tests, selected by [mode].
class _FakeForwardPass implements EmbeddingForwardPass {
  _FakeForwardPass(this.modelPath);

  final String modelPath;

  @override
  Future<void> load() async {}

  @override
  Future<ForwardResult> run({
    required List<int> tokenIds,
    List<int>? attentionMask,
    List<int>? tokenTypeIds,
  }) async {
    switch (_FakeMode.fromModelPath(modelPath)) {
      case _FakeMode.echoTokenIds:
        return ForwardResult(
          values: [for (final t in tokenIds) t.toDouble()],
          shape: [1, tokenIds.length],
        );
      case _FakeMode.pooledFinalFixed:
        // norm(3,4) == 5 — the tripwire vector: if anything normalizes this,
        // it comes back as [0.6, 0.8] instead of [3.0, 4.0].
        return const ForwardResult(values: [3.0, 4.0], shape: [1, 2]);
      case _FakeMode.tokenLevelFixed:
        // seq=3, dim=2 hidden states; mean -> [1,1] -> L2 -> [1/√2, 1/√2].
        return const ForwardResult(
          values: [1, 0, 0, 1, 2, 2],
          shape: [1, 3, 2],
        );
      case _FakeMode.killMidRequest:
        // Simulate an unexpected native crash: the isolate dies while a
        // request is in flight, never sending a reply.
        Isolate.current.kill(priority: Isolate.immediate);
        // Unreachable in practice — kill() terminates before this returns —
        // but the switch must be exhaustive and total.
        return const ForwardResult(values: [], shape: [1, 0]);
    }
  }

  @override
  Future<void> close() async {}

  @override
  int get outputDimension => 2;

  @override
  int? get inputSequenceLength => null;
}

/// The fake's behavior is selected by encoding a mode tag into the
/// (otherwise-unused) `modelPath` field of the descriptor — the only
/// sendable channel available before the isolate boundary.
enum _FakeMode {
  echoTokenIds,
  pooledFinalFixed,
  tokenLevelFixed,
  killMidRequest;

  static _FakeMode fromModelPath(String modelPath) =>
      _FakeMode.values.firstWhere((m) => m.name == modelPath);
}

EmbeddingForwardPass _buildFake(String modelPath) =>
    _FakeForwardPass(modelPath);

/// Builds a tiny, self-contained SentencePiece tokenizer (BPE, single-char
/// vocab covering exactly the alphabet the tests use) as a JSON file this
/// library's own `TokenizerJsonLoader` can read — avoids checking in a real
/// (multi-MB) `.model` binary just for this unit test. Normalizer flags are
/// all `false` so `normalize()` is the identity function and token-stream
/// assertions can be exact.
Future<String> _writeTinyTokenizer(Directory dir, String alphabet) async {
  final pieces = ['<unk>', '<s>', '</s>', '<pad>', ...alphabet.split('')];
  final types = [2, 3, 3, 3, ...List.filled(alphabet.length, 1)];
  final json = {
    'version': '1.0',
    'model_type': 'bpe',
    'vocab': {
      'pieces': pieces,
      'scores': List.filled(pieces.length, 0.0),
      'types': types,
    },
    'special_tokens': {
      'unk': {'id': 0, 'piece': '<unk>'},
      'bos': {'id': 1, 'piece': '<s>'},
      'eos': {'id': 2, 'piece': '</s>'},
      'pad': {'id': 3, 'piece': '<pad>'},
    },
    'normalizer': {
      'add_dummy_prefix': false,
      'remove_extra_whitespaces': false,
      'escape_whitespaces': false,
    },
    'config': {'add_bos_token': false, 'add_eos_token': false},
    'byte_fallback': false,
  };
  final file = File('${dir.path}/tiny_tokenizer.json');
  await file.writeAsString(jsonEncode(json));
  return file.path;
}

void main() {
  late Directory tmpDir;
  late String tokenizerPath;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('embedding_worker_test');
    tokenizerPath = await _writeTinyTokenizer(tmpDir, 'p:ab');
  });

  tearDownAll(() async {
    await tmpDir.delete(recursive: true);
  });

  group('EmbeddingWorker output-contract dispatch', () {
    test('pooledFinal copies ForwardResult.values verbatim — no normalization '
        '(Invariant I0 tripwire: [3,4] has norm 5, must NOT come back as '
        '[0.6, 0.8])', () async {
      final worker = await EmbeddingWorker.spawn(
        descriptor: ForwardPassDescriptor(
          engineTag: 'Fake',
          modelPath: _FakeMode.pooledFinalFixed.name,
          factory: _buildFake,
          outputContract: EmbeddingOutputContract.pooledFinal,
        ),
        tokenizerPath: tokenizerPath,
      );
      try {
        final vector = await worker.embed('ab', prefix: '');
        expect(vector, [3.0, 4.0]);
      } finally {
        await worker.close();
      }
    });

    test('tokenLevel mean-pools + L2-normalizes', () async {
      final worker = await EmbeddingWorker.spawn(
        descriptor: ForwardPassDescriptor(
          engineTag: 'Fake',
          modelPath: _FakeMode.tokenLevelFixed.name,
          factory: _buildFake,
          outputContract: EmbeddingOutputContract.tokenLevel,
        ),
        tokenizerPath: tokenizerPath,
      );
      try {
        final vector = await worker.embed('ab', prefix: '');
        expect(vector.length, 2);
        final norm = (vector[0] * vector[0] + vector[1] * vector[1]);
        expect(norm, closeTo(1.0, 1e-9));
      } finally {
        await worker.close();
      }
    });
  });

  group('EmbeddingWorker tokenization (Invariant I1)', () {
    test('wraps prefix+text with [bosId=2, ...ids, eosId=1]', () async {
      final worker = await EmbeddingWorker.spawn(
        descriptor: ForwardPassDescriptor(
          engineTag: 'Fake',
          modelPath: _FakeMode.echoTokenIds.name,
          factory: _buildFake,
          outputContract: EmbeddingOutputContract.pooledFinal,
        ),
        tokenizerPath: tokenizerPath,
      );
      try {
        // prefix 'p:' + text 'ab' -> chars p,:,a,b -> vocab ids 4,5,6,7
        // (unk=0, bos=1, eos=2, pad=3, then p,:,a,b in that order).
        final echoed = await worker.embed('ab', prefix: 'p:');
        final tokenIds = echoed.map((d) => d.round()).toList();
        expect(tokenIds, [2, 4, 5, 6, 7, 1]);
      } finally {
        await worker.close();
      }
    });
  });

  group('EmbeddingWorker lifecycle', () {
    test('loads once, serves concurrent requests correlated by id', () async {
      final worker = await EmbeddingWorker.spawn(
        descriptor: ForwardPassDescriptor(
          engineTag: 'Fake',
          modelPath: _FakeMode.echoTokenIds.name,
          factory: _buildFake,
          outputContract: EmbeddingOutputContract.pooledFinal,
        ),
        tokenizerPath: tokenizerPath,
      );
      try {
        final results = await Future.wait([
          worker.embed('a', prefix: ''),
          worker.embed('b', prefix: ''),
          worker.embed('ab', prefix: ''),
        ]);
        // Each reply must correlate to its own request, not get swapped.
        expect(results[0], [2, 6, 1]); // 'a' -> id 6
        expect(results[1], [2, 7, 1]); // 'b' -> id 7
        expect(results[2], [2, 6, 7, 1]); // 'ab' -> ids 6,7
      } finally {
        await worker.close();
      }
    });

    test('close() acks and further embed() calls fail', () async {
      final worker = await EmbeddingWorker.spawn(
        descriptor: ForwardPassDescriptor(
          engineTag: 'Fake',
          modelPath: _FakeMode.echoTokenIds.name,
          factory: _buildFake,
          outputContract: EmbeddingOutputContract.pooledFinal,
        ),
        tokenizerPath: tokenizerPath,
      );
      await worker.close();
      await worker.close(); // idempotent
      expect(worker.embed('a', prefix: ''), throwsA(isA<StateError>()));
    });

    test('an unexpected worker death fails in-flight requests instead of '
        'hanging them forever', () async {
      final worker = await EmbeddingWorker.spawn(
        descriptor: ForwardPassDescriptor(
          engineTag: 'Fake',
          modelPath: _FakeMode.killMidRequest.name,
          factory: _buildFake,
          outputContract: EmbeddingOutputContract.pooledFinal,
        ),
        tokenizerPath: tokenizerPath,
      );
      final killer = worker.embed('a', prefix: '');
      final bystander = worker.embed('b', prefix: '');
      await expectLater(killer, throwsA(isA<StateError>()));
      await expectLater(bystander, throwsA(isA<StateError>()));
    });
  });
}
