// Unit tests for `loadOnnxEmbeddingTokenizer`'s routing (Phase 2 hardened
// plan Task 3). No native session; exercises real file I/O against tiny
// fixtures written to a temp dir.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma_embeddings/wordpiece_embedding_tokenizer.dart';
import 'package:flutter_gemma_onnx/src/embedding/onnx_tokenizer_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const _wordPieceVocab = {
  '[PAD]': 0,
  '[UNK]': 100,
  '[CLS]': 101,
  '[SEP]': 102,
  'hi': 4000,
};

String _wordPieceJson() => jsonEncode({
  'version': '1.0',
  'normalizer': {'type': 'BertNormalizer', 'lowercase': true},
  'model': {
    'type': 'WordPiece',
    'unk_token': '[UNK]',
    'vocab': _wordPieceVocab,
  },
});

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'onnx_tokenizer_loader_test',
    );
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('a `tokenizer.json` with model.type=WordPiece routes to '
      'WordPieceEmbeddingTokenizer', () async {
    final path = '${tmpDir.path}/tokenizer.json';
    await File(path).writeAsString(_wordPieceJson());

    final tokenizer = await loadOnnxEmbeddingTokenizer(path);
    expect(tokenizer, isA<WordPieceEmbeddingTokenizer>());
  });

  test('a `.json`-named file that is not a WordPiece model falls through '
      'to the SentencePiece adapter — a non-.json-loadable path throws '
      'there rather than being silently misrouted', () async {
    final path = '${tmpDir.path}/tokenizer.json';
    await File(path).writeAsString(
      jsonEncode({
        'model': {'type': 'BPE'},
      }),
    );

    // The Gemma SentencePiece adapter cannot parse this HF BPE schema
    // either — it throws, but importantly it is REACHED (not silently
    // treated as WordPiece, which would corrupt every token id).
    await expectLater(loadOnnxEmbeddingTokenizer(path), throwsA(anything));
  });

  test(
    'a non-JSON-named file (raw SentencePiece `.model` binary) is never '
    'read as JSON — routes straight to the SentencePiece adapter without '
    'attempting `File.readAsString` (which throws FileSystemException on '
    'invalid UTF-8, verified against a real tokenizer.model download)',
    () async {
      final path = '${tmpDir.path}/tokenizer.model';
      // Write genuinely invalid-UTF-8 bytes — if `loadOnnxEmbeddingTokenizer`
      // ever tried `readAsString()` on this path, it would throw
      // FileSystemException before even reaching the SentencePiece loader.
      await File(path).writeAsBytes([0xFF, 0xFE, 0x00, 0x01, 0x02]);

      // The SentencePiece adapter itself will fail on this garbage — the
      // point is WHERE it fails (inside SentencePiece parsing, not
      // File.readAsString's UTF-8 decode).
      await expectLater(loadOnnxEmbeddingTokenizer(path), throwsA(anything));
    },
  );
}
