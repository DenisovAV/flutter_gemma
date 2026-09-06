@TestOn('vm')
library;

// Pins what the DEPENDENCY hands back, not what the profile produces.
//
// The profile is deliberately version-insensitive now — `loadEmbeddingTokenizer`
// calls `noPadding()`/`noTruncation()`, so `encodeForSiglipEmbedding` sees bare
// content whatever the file declares. That is the right design and it is exactly
// why the profile cannot be the canary: it would keep passing while the loader
// changed underneath it.
//
// This is the canary. 1.4.0 changed `encode()`'s return shape inside a MINOR
// release (it began applying the file's `padding` and `truncation` blocks), and
// the constraint is open-topped, so the next minor can do it again. These
// assertions turn that into a red build instead of a quietly different vector.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma_embeddings/src/embedding_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A miniature file carrying the blocks the real SigLIP 2 tokenizer declares:
/// fixed-width right padding, and the normalizer that makes its `Split` legal.
Future<String> _write(Directory dir) async {
  final json = {
    'version': '1.0',
    'truncation': null,
    'padding': {
      'strategy': {'Fixed': 64},
      'direction': 'Right',
      'pad_to_multiple_of': null,
      'pad_id': 0,
      'pad_type_id': 0,
      'pad_token': '<pad>',
    },
    'added_tokens': [
      for (final e in const [
        ('<pad>', 0),
        ('<eos>', 1),
        ('<bos>', 2),
        ('<unk>', 3),
      ])
        {
          'id': e.$2,
          'content': e.$1,
          'single_word': false,
          'lstrip': false,
          'rstrip': false,
          'normalized': false,
          'special': true,
        },
    ],
    'normalizer': {
      'type': 'Replace',
      'pattern': {'String': ' '},
      'content': '▁',
    },
    'pre_tokenizer': {
      'type': 'Split',
      'pattern': {'String': ' '},
      'behavior': 'MergedWithPrevious',
      'invert': false,
    },
    'post_processor': {
      'type': 'TemplateProcessing',
      'single': [
        {
          'Sequence': {'id': 'A', 'type_id': 0},
        },
        {
          'SpecialToken': {'id': '<eos>', 'type_id': 0},
        },
      ],
      'pair': [
        {
          'Sequence': {'id': 'A', 'type_id': 0},
        },
      ],
      'special_tokens': {
        '<eos>': {
          'id': '<eos>',
          'ids': [1],
          'tokens': ['<eos>'],
        },
      },
    },
    'decoder': null,
    'model': {
      'type': 'BPE',
      'unk_token': '<unk>',
      // Contiguous ids: a gap makes the vocabulary build with holes and every
      // piece past it resolve to <unk>.
      'vocab': {
        '<pad>': 0,
        '<eos>': 1,
        '<bos>': 2,
        '<unk>': 3,
        '▁a': 4,
        '▁b': 5,
        'a': 6,
      },
      'merges': <List<String>>[],
    },
  };
  final path = '${dir.path}/tokenizer.json';
  await File(path).writeAsString(jsonEncode(json));
  return path;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sp_contract_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'loadEmbeddingTokenizer returns bare content, whatever the file asks for',
    () async {
      final tokenizer = await loadEmbeddingTokenizer(await _write(dir));

      final ids = tokenizer.encode('a b').ids;

      // The file declares Fixed-64 right padding. If this comes back 64 long, the
      // loader applied it and `noPadding()` stopped working — every profile that
      // appends its own terminator would put it past the pad run.
      expect(
        ids.length,
        2,
        reason:
            'the file asks for 64-wide padding; the loader must not apply it',
      );
      expect(ids, [
        6,
        5,
      ], reason: 'bare Replace normalizer, so no dummy prefix');

      // The file's post_processor appends <eos>. The explicit SentencePieceConfig
      // must keep overriding it: both profiles add their own terminator, and a
      // second one would double it.
      expect(
        ids.contains(siglipEosId),
        isFalse,
        reason:
            'the post_processor EOS must stay suppressed by the explicit config',
      );
    },
  );

  test('a long input is neither truncated nor padded by the loader', () async {
    final tokenizer = await loadEmbeddingTokenizer(await _write(dir));

    // 100 content tokens: past the file's 64-wide padding, and past any
    // truncation a future release might start honouring. The width rule belongs
    // to encodeForSiglipEmbedding, not to the loader.
    final ids = tokenizer.encode('a' * 100).ids;

    expect(
      ids.length,
      greaterThan(siglipSeqLen),
      reason: 'the loader must hand back everything and let the profile clamp',
    );
  });
}
