// Unit tests for `parseOnnxEmbeddingTokenizerWeb` — pure Dart, no
// `dart:js_interop`, runs under plain `flutter test` (VM).

import 'dart:convert';

import 'package:flutter_gemma_embeddings/wordpiece_embedding_tokenizer.dart';
import 'package:flutter_gemma_onnx/src/web/onnx_web_tokenizer_loader.dart';
import 'package:flutter_test/flutter_test.dart';

String _wordPieceJson() {
  return jsonEncode({
    'model': {
      'type': 'WordPiece',
      'unk_token': '[UNK]',
      'continuing_subword_prefix': '##',
      'max_input_chars_per_word': 100,
      'vocab': {'[UNK]': 100, '[CLS]': 101, '[SEP]': 102, 'hello': 7592},
    },
  });
}

String _bpeJson() {
  return jsonEncode({
    'model': {'type': 'BPE', 'vocab': <String, int>{}, 'merges': <String>[]},
  });
}

void main() {
  group('parseOnnxEmbeddingTokenizerWeb', () {
    test(
      'routes a WordPiece tokenizer.json to WordPieceEmbeddingTokenizer',
      () {
        final tokenizer = parseOnnxEmbeddingTokenizerWeb(_wordPieceJson());
        expect(tokenizer, isA<WordPieceEmbeddingTokenizer>());
      },
    );

    test('a WordPiece tokenizer tokenizes correctly through the seam', () {
      final tokenizer = parseOnnxEmbeddingTokenizerWeb(_wordPieceJson());
      final result = tokenizer.encode('', 'hello');
      expect(result.ids, [101, 7592, 102]);
    });

    test('throws UnsupportedError for a non-WordPiece tokenizer.json (BPE — '
        'SentencePiece/EmbeddingGemma-family is not supported on web)', () {
      expect(
        () => parseOnnxEmbeddingTokenizerWeb(_bpeJson()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('throws FormatException for invalid JSON', () {
      expect(
        () => parseOnnxEmbeddingTokenizerWeb('not json'),
        throwsFormatException,
      );
    });
  });
}
