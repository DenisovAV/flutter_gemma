// Unit tests for the SigLIP2 SentencePiece embedding-tokenizer adapter
// (`loadSiglipSentencePieceEmbeddingTokenizer` / `encodeForSiglipEmbedding`).
//
// SigLIP2's text tower uses a DIFFERENT convention from Gemma: NO leading BOS,
// a SINGLE trailing EOS, lowercased text, and a FIXED 64-token width (its ONNX
// export reads as dynamic-shape and carries no attention_mask, so the padding
// must live in the token ids). These tests pin that convention using a tiny,
// self-contained tokenizer — no multi-MB model checked in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma_embeddings/src/embedding_tokenizer.dart';
import 'package:flutter_gemma_embeddings/src/tokenizer_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a tiny SentencePiece tokenizer (single-char vocab over [alphabet])
/// in the library's own JSON format — the same shape the other embedding tests
/// use. Special ids: `<unk>`=0, `<s>`=1, `</s>`=2, `<pad>`=3; alphabet chars
/// start at 4. Normalizer flags are all off so tokenization is exact.
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
  late EmbeddingTokenizer siglip;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('siglip_tokenizer_test');
    // alphabet 'ab' -> ids: a=4, b=5.
    final path = await _writeTinyTokenizer(tmpDir, 'ab');
    siglip = await loadSiglipSentencePieceEmbeddingTokenizer(path);
  });

  tearDownAll(() async {
    await tmpDir.delete(recursive: true);
  });

  group('SigLIP tokenizer convention', () {
    test('no BOS, single trailing EOS, right-padded to the fixed width', () {
      final ids = siglip.encode('', 'ab').ids;

      expect(ids.length, siglipSeqLen);
      // Content starts immediately — NO BOS is prepended.
      expect(ids[0], 4); // 'a'
      expect(ids[1], 5); // 'b'
      // A single EOS follows the content...
      expect(ids[2], siglipEosId);
      // ...then pad to the fixed width.
      expect(ids.sublist(3).every((id) => id == siglipPadId), isTrue);
    });

    test('lowercases the input before tokenizing', () {
      expect(siglip.encode('', 'AB').ids, siglip.encode('', 'ab').ids);
    });

    test('prefix is prepended to the text (then lowercased)', () {
      expect(siglip.encode('a', 'b').ids, siglip.encode('', 'ab').ids);
    });

    test('truncates content longer than the fixed width', () {
      // 200 'a's + EOS would exceed 64; the result is clamped to exactly 64.
      final ids = siglip.encode('', 'a' * 200).ids;
      expect(ids.length, siglipSeqLen);
      expect(ids.every((id) => id == 4), isTrue); // all 'a', EOS truncated off
    });
  });
}
