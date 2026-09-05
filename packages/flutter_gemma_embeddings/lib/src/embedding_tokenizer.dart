// Runtime-agnostic tokenization half of the embedding pipeline (embedder
// decoupling plan Task 3, Invariant I1).
//
// Verbatim port of what used to live in
// `flutter_gemma_embeddings/lib/src/litert/litert_embedding_core.dart`
// (lines 41-44 + 95-106 pre-refactor): the Gemma BOS/EOS convention and the
// `.json`-vs-`.model` tokenizer-loader branch. This half is engine-agnostic
// (pure Dart, `dart_sentencepiece_tokenizer` only) so it now lives here
// instead of inside the LiteRT-specific forward pass — the pad/truncate-to-
// seqLen half stays with the LiteRT forward pass in `flutter_gemma_litertlm`
// because only that engine's compiled model knows its fixed `seqLen`.
//
// ⚠️ I1 risk: `dart_sentencepiece_tokenizer` defaults to the SWAPPED
// BOS/EOS pair (bosId=1, eosId=2) — we add the correct Gemma pair manually.
// Getting `_bosId`/`_eosId` or the `prefix + text` concatenation order wrong
// silently changes every embedding vector without any exception.

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';

import 'tokenizer_adapter.dart';

/// Gemma special-token IDs. `dart_sentencepiece_tokenizer` defaults to the
/// swapped pair (bosId=1, eosId=2), so we add them manually.
const int bosId = 2;
const int eosId = 1;

/// Loads the SentencePiece tokenizer at [tokenizerPath] — a `.json` (via
/// `TokenizerJsonLoader`) or a raw SentencePiece `.model` file, matching
/// exactly the branch `litert_embedding_core.dart` used pre-refactor.
Future<SentencePieceTokenizer> loadEmbeddingTokenizer(
  String tokenizerPath,
) async {
  if (tokenizerPath.endsWith('.json')) {
    return TokenizerJsonLoader.fromJsonFile(
      tokenizerPath,
      config: const SentencePieceConfig(),
    );
  }
  return SentencePieceTokenizer.fromModelFile(
    tokenizerPath,
    config: const SentencePieceConfig(),
  );
}

/// Tokenizes ([prefix] + [text]) with Gemma BOS/EOS:
/// `[bosId, ...encode(prefix + text).ids, eosId]`.
///
/// Does NOT pad/truncate to a fixed sequence length — that is the forward
/// pass's job (it owns `seqLen`, e.g. LiteRT's compiled input tensor width).
List<int> encodeForEmbedding(
  SentencePieceTokenizer tokenizer,
  String prefix,
  String text,
) {
  final encoded = tokenizer.encode(prefix + text);
  return <int>[bosId, ...encoded.ids, eosId];
}

/// [EmbeddingTokenizerFactory] tear-off (design D-T1) — a thin
/// [EmbeddingTokenizer] adapter over [loadEmbeddingTokenizer] +
/// [encodeForEmbedding]. Byte-identical to the pre-generalization LiteRT
/// path: same BOS=2/EOS=1 convention, same `prefix + text` concatenation
/// order. Always returns `attentionMask: null, tokenTypeIds: null` — Gemma
/// SentencePiece has no notion of either; the forward pass pads/truncates
/// internally and has no mask to report back.
Future<EmbeddingTokenizer> loadGemmaSentencePieceEmbeddingTokenizer(
  String tokenizerPath,
) async {
  final tokenizer = await loadEmbeddingTokenizer(tokenizerPath);
  return _GemmaSentencePieceEmbeddingTokenizer(tokenizer);
}

class _GemmaSentencePieceEmbeddingTokenizer implements EmbeddingTokenizer {
  _GemmaSentencePieceEmbeddingTokenizer(this._tokenizer);

  final SentencePieceTokenizer _tokenizer;

  @override
  TokenizedInput encode(String prefix, String text) =>
      TokenizedInput(ids: encodeForEmbedding(_tokenizer, prefix, text));
}

// ─────────────────────────── SigLIP2 profile ───────────────────────────
//
// SigLIP2's text tower uses a DIFFERENT special-token convention from Gemma:
// NO leading BOS, a SINGLE trailing EOS (id 1), and its canonical preprocessing
// lowercases the text. The model's ONNX graph has a FIXED `input_ids [1, 64]`
// input, so the ids must carry the width. The SigLIP int8 export reads as
// DYNAMIC-shape, so the forward pass's `staticSeqLen` path does NOT pad it —
// [encodeForSiglipEmbedding] pads here instead. This is a SEPARATE adapter from
// the Gemma one (which hardcodes
// BOS=2/EOS=1) — routing the SigLIP profile here instead of to the Gemma adapter
// is what avoids the silent BOS-injection corruption; the Gemma path is
// untouched (non-regressing).

/// SigLIP2's trailing end-of-sequence id. No BOS is prepended.
const int siglipEosId = 1;

/// SigLIP2's fixed context width and pad id, both taken from the model's own
/// `tokenizer.json`, which bakes them in:
///
/// ```json
/// "padding": {"strategy": {"Fixed": 64}, "direction": "Right",
///             "pad_id": 0, "pad_token": "<pad>"}
/// ```
///
/// The width has to live in the ids. The int8 export reads as DYNAMIC-shape
/// (`OrtIoSpec.staticSeqLen == null`), so the forward pass never pads, and the
/// graph carries NO `attention_mask`. Worse, the head does not pool over the
/// sequence at all — `Siglip2TextModel` takes `last_hidden_state[:, -1, :]`
/// ("the last token's hidden state, which may be padding", upstream's own
/// comment). With right-padding the pooled vector therefore IS the pad
/// position, which is why the pad id is first-order: measured against a correct
/// vector, padding with 1 instead of 0 gives cosine 0.81-0.90 and reorders
/// retrieval; not padding at all gives 0.58-0.69.
///
/// SigLIP **2** only. SigLIP 1 is a different tokenizer entirely (T5 Unigram,
/// 32k vocab, pad = `</s>` = 1); SigLIP 2 uses the Gemma BPE tokenizer (256k,
/// `<pad>` = 0, `<eos>` = 1). Pointing this profile at a SigLIP 1 file
/// silently produces wrong vectors.
const int siglipSeqLen = 64;

/// The id every position past the content is filled with — `<pad>`, id 0 in the
/// SigLIP 2 vocabulary. See [siglipSeqLen] for why this one is not cosmetic:
/// with right-padding it is the position the head actually pools.
const int siglipPadId = 0;

/// Tokenizes [text] with SigLIP2's convention and returns exactly [siglipSeqLen]
/// ids: no BOS, lowercased content truncated to `siglipSeqLen - 1`, one trailing
/// [siglipEosId], then right-padding with [siglipPadId].
///
/// The EOS survives truncation — content of 63 tokens or more yields
/// `[...first 63, EOS]` with no padding, matching the reference.
///
/// Takes the content text ALONE. The adapter deliberately does not hand a
/// TaskType prefix through — see [loadSiglipSentencePieceEmbeddingTokenizer].
List<int> encodeForSiglipEmbedding(
  SentencePieceTokenizer tokenizer,
  String text,
) {
  // Truncate the CONTENT to leave room for the EOS, rather than appending it
  // and cutting it back off — the reference (`tokenizers` with
  // `enable_truncation(64)`, and DJL's `LONGEST_FIRST` default, which is what
  // the reference Android app runs) keeps `<eos>` at index 63 on a long input.
  // Appending first silently dropped it and cost cosine 0.9683 on inputs over
  // the width.
  final content = tokenizer.encode(text.toLowerCase()).ids;
  final ids = <int>[...content.take(siglipSeqLen - 1), siglipEosId];
  return [...ids, ...List<int>.filled(siglipSeqLen - ids.length, siglipPadId)];
}

/// [EmbeddingTokenizerFactory] tear-off for the SigLIP2 text tower — reuses the
/// same base [loadEmbeddingTokenizer] (`.json`/`.model` branch) as Gemma, but
/// wraps it with SigLIP's no-BOS/single-EOS/lowercase convention instead.
///
/// The returned tokenizer **ignores the TaskType prefix**. `TaskType` is an
/// EmbeddingGemma convention (`'task: search result | query: '`), and SigLIP's
/// text tower has no vocabulary for it: a prefix would be embedded as literal
/// leading text and move the vector off the space it shares with the vision
/// tower, which encodes an image with no prefix at all. Dropping it is not a
/// silent liberty — [CommonEmbeddingModel.generateEmbedding] DEFAULTS to
/// `TaskType.retrievalQuery`, so rejecting a non-empty prefix would make this
/// profile unreachable through the only public API, and honoring one would make
/// `retrievalQuery` and `retrievalDocument` of the same string two different
/// points.
Future<EmbeddingTokenizer> loadSiglipSentencePieceEmbeddingTokenizer(
  String tokenizerPath,
) async {
  final tokenizer = await loadEmbeddingTokenizer(tokenizerPath);
  _assertSiglip2Vocab(tokenizer, tokenizerPath);
  return _SiglipSentencePieceEmbeddingTokenizer(tokenizer);
}

/// Fails loudly when [tokenizer] is not the SigLIP **2** (Gemma BPE) vocabulary.
///
/// Everything this profile hardcodes — [siglipPadId] 0, [siglipEosId] 1, no BOS
/// — is SigLIP 2's convention. SigLIP 1 ships a different tokenizer entirely
/// (T5 Unigram, 32k, pad = `</s>` = 1), and running it through here produces a
/// plausible vector that is simply wrong: the ids stay in range, nothing
/// throws, and the error only shows up as degraded retrieval. Since the model
/// pools the LAST position (see [siglipSeqLen]), a wrong pad id is the single
/// biggest way to get that silently.
void _assertSiglip2Vocab(SentencePieceTokenizer tokenizer, String path) {
  final pieces = tokenizer.convertIdsToTokens([siglipPadId, siglipEosId]);
  if (pieces[0] == '<pad>' && pieces[1] == '<eos>') return;
  throw ArgumentError.value(
    path,
    'tokenizerPath',
    'not a SigLIP 2 tokenizer: expected id $siglipPadId = <pad> and '
        'id $siglipEosId = <eos> (the Gemma BPE vocabulary SigLIP 2 uses), '
        'got ${pieces[0]} and ${pieces[1]}. SigLIP 1 uses a T5 Unigram vocab '
        'where id 1 is </s> and is NOT interchangeable — its embeddings would '
        'come out wrong rather than fail.',
  );
}

class _SiglipSentencePieceEmbeddingTokenizer implements EmbeddingTokenizer {
  _SiglipSentencePieceEmbeddingTokenizer(this._tokenizer);

  final SentencePieceTokenizer _tokenizer;

  @override
  TokenizedInput encode(String prefix, String text) {
    // [prefix] is deliberately dropped — see the factory's doc for why a
    // TaskType prefix is meaningless here and why throwing is not an option.
    final ids = encodeForSiglipEmbedding(_tokenizer, text);
    // This adapter BUILT the padding, so it is the only thing that knows which
    // positions are real. Reporting the mask matters even though the head pools
    // the last position rather than averaging: when the graph declares an
    // `attention_mask` input, the forward pass otherwise fabricates an all-ones
    // one over the pad tail, and a graph that falls through to
    // `last_hidden_state` would mean-pool 63 pads into the vector.
    // Counted from the END rather than by locating the EOS. Equivalent today —
    // 1.3.3 does not match added tokens inside content, so `encode('a<eos>a')`
    // yields `<unk>`s, never a mid-content id 1 — but `indexOf(siglipEosId)`
    // would rely on that staying true of the dependency. The tail does not:
    // everything past the EOS is padding by construction, and the EOS itself is
    // never [siglipPadId].
    var realTokens = siglipSeqLen;
    while (realTokens > 0 && ids[realTokens - 1] == siglipPadId) {
      realTokens--;
    }
    return TokenizedInput(
      ids: ids,
      attentionMask: [
        ...List<int>.filled(realTokens, 1),
        ...List<int>.filled(siglipSeqLen - realTokens, 0),
      ],
    );
  }
}
