import 'package:flutter_gemma_speech/src/tokenizer/sentence_piece_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SentencePieceTokenizer tokenizerWith(Map<String, int> vocab) =>
      SentencePieceTokenizer.fromJson({
        'model': {'type': 'BPE', 'vocab': vocab},
      });

  test('skips BOS, stops at EOS, decodes word pieces', () {
    final tokenizer = tokenizerWith({
      '<unk>': 0,
      '<s>': 1,
      '</s>': 2,
      '▁Hello': 3,
      '▁world': 4,
    });
    final text = tokenizer.decode([1, 3, 4, 2, 999]);
    expect(text, 'Hello world');
  });

  test('byte-fallback pieces decode to raw bytes (no leading space)', () {
    final tokenizer = tokenizerWith({
      '<unk>': 0,
      '<s>': 1,
      '</s>': 2,
      '▁Hello': 3,
      '<0x21>': 4, // '!'
      '▁world': 5,
    });
    final text = tokenizer.decode([1, 3, 4, 5, 2]);
    expect(text, 'Hello! world');
  });

  test('unk and added-vocab ids (>= base vocab size) are skipped', () {
    final tokenizer = tokenizerWith({
      '<unk>': 0,
      '<s>': 1,
      '</s>': 2,
      '▁Hi': 3,
    });
    final text = tokenizer.decode([1, 0, 3, 99, 2]);
    expect(text, 'Hi');
  });
}
