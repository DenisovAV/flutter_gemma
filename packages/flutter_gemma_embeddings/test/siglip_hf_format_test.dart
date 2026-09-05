@TestOn('vm')
library;

// The other SigLIP test builds its tokenizer in the LIBRARY's own JSON format.
// Real models do not ship that — they ship HuggingFace `tokenizer.json`, and the
// difference is not cosmetic: the HF path parses `pre_tokenizer`,
// `post_processor`, list-form `merges` and `added_tokens`, none of which the
// internal format exercises.
//
// That gap hid a real break. `dart_sentencepiece_tokenizer` 1.3.3 loads SigLIP2's
// file; 1.4.0 added `pre_tokenizer` validation with no `Split` case and rejects
// it, so `^1.3.3` resolved to 1.4.0 and the profile threw
// `Unsupported Hugging Face pre-tokenizer: Split` for anyone installing from
// pub.dev. Nothing in the suite noticed, because nothing here had ever fed the
// loader a HuggingFace file.
//
// This fixture is that file in miniature: same `model.type`, same `Split`
// pre-tokenizer (`pattern: {String: " "}`, `MergedWithPrevious`), same list-form
// `merges` and `added_tokens`, with an eight-token vocabulary instead of 256k.
// Its `post_processor` and `padding` blocks mirror the real file for fidelity,
// but the loader discards them — see the note in the test body.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma_embeddings/src/embedding_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A HuggingFace `tokenizer.json` carrying SigLIP2's pipeline blocks verbatim.
Future<String> _writeHfTokenizer(Directory dir) async {
  const vocab = {
    '<pad>': 0,
    '<eos>': 1,
    '<bos>': 2,
    '<unk>': 3,
    '▁a': 4,
    '▁b': 5,
    'a': 6,
    'b': 7,
  };
  final json = {
    'version': '1.0',
    'truncation': null,
    // Verbatim from SigLIP2's tokenizer.json.
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
    'normalizer': null,
    // The block 1.4.0 rejects.
    'pre_tokenizer': {
      'type': 'Split',
      'pattern': {'String': ' '},
      'behavior': 'MergedWithPrevious',
      'invert': false,
    },
    // No BOS — the half that distinguishes SigLIP2 from a Gemma tokenizer.
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
      'vocab': vocab,
      // List-of-pairs form — what upstream #26 taught 1.3.3 to read.
      'merges': [
        ['a', 'b'],
      ],
    },
  };
  final path = '${dir.path}/tokenizer.json';
  await File(path).writeAsString(jsonEncode(json));
  return path;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('siglip_hf_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the SigLIP2 profile loads a HuggingFace-format tokenizer.json', () async {
    final path = await _writeHfTokenizer(dir);

    // The first assertion is that this does not throw: a dependency that
    // rejects the `Split` pre-tokenizer or the list-form `merges` fails right
    // here, which is what a version range admitting such a release would
    // otherwise ship to users unnoticed.
    final tok = await loadSiglipSentencePieceEmbeddingTokenizer(path);

    // Then a canary on the result: the two pieces, the EOS, then padding — and
    // no BOS (id 2), which is the Gemma convention rather than SigLIP2's.
    final ids = tok.encode('', 'a b').ids;
    expect(ids.take(3), [4, 5, siglipEosId]);
    expect(ids.skip(3), everyElement(siglipPadId));

    // What this fixture does NOT prove, established by mutating it: under 1.3.3
    // the `pre_tokenizer`, `post_processor` and `padding` blocks are ALL inert.
    // 1.3.3 has no pre-tokenizer parsing at all, so flipping `Split` from
    // `MergedWithPrevious` to `Isolated` changes no id — 1.4.0's contribution
    // was to start reading that block and throw on the `Split` case.
    // `loadEmbeddingTokenizer` passes an explicit `SentencePieceConfig`, so the
    // file's post-processor metadata is discarded (flipping the template to
    // `[<bos>, Sequence A]` changes no id). And `enablePadding` is a 1.4.0
    // addition (width 64 -> 8 changes no id). Every id above comes from the BPE
    // vocabulary plus `encodeForSiglipEmbedding`, never from those blocks.
    //
    // So the LOAD is the load-bearing assertion here, and what it guards is
    // exactly the version range: 1.3.2 cannot read the list-form `merges`,
    // 1.4.0 rejects the `Split` block.
  });
}
