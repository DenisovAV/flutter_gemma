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
// input, so padding to 64 (pad id 0) is the forward pass's job — the tokenizer
// emits the unpadded `[...ids, EOS]` and the forward pass's `staticSeqLen` path
// pads it. This is a SEPARATE adapter from the Gemma one (which hardcodes
// BOS=2/EOS=1) — routing the SigLIP profile here instead of to the Gemma adapter
// is what avoids the silent BOS-injection corruption; the Gemma path is
// untouched (non-regressing).

/// SigLIP2's trailing end-of-sequence id. No BOS is prepended.
const int siglipEosId = 1;

/// SigLIP2's fixed context width and pad id. Unlike Gemma/MiniLM (whose ONNX
/// graphs declare a static seq-len the forward pass detects and pads to), the
/// SigLIP int8 export reads as DYNAMIC-shape (`OrtIoSpec.staticSeqLen == null`),
/// yet the model was trained/exported for EXACTLY 64 tokens and carries NO
/// attention_mask input — its pooling head sees all 64 positions, so a short,
/// unpadded input yields a DIFFERENT `pooler_output` (measured: cosine 0.69 vs
/// the glasses' 64-padded reference). The glasses pad in their tokenizer (DJL
/// `MAX_LENGTH`/64); this Dart profile must do the same to reach parity.
const int siglipSeqLen = 64;
const int siglipPadId = 0;

/// Tokenizes [text] with SigLIP2's convention: `[...encode(text.toLowerCase()).ids, siglipEosId]`,
/// then RIGHT-PADS (or truncates) to exactly [siglipSeqLen] with [siglipPadId] —
/// SigLIP needs the fixed width baked into the ids (see [siglipSeqLen]). NO BOS,
/// NO task-type prefix, single trailing EOS, lowercased.
List<int> encodeForSiglipEmbedding(
  SentencePieceTokenizer tokenizer,
  String text,
) {
  final encoded = tokenizer.encode(text.toLowerCase());
  final ids = <int>[...encoded.ids, siglipEosId];
  if (ids.length >= siglipSeqLen) return ids.sublist(0, siglipSeqLen);
  return [...ids, ...List<int>.filled(siglipSeqLen - ids.length, siglipPadId)];
}

/// [EmbeddingTokenizerFactory] tear-off for the SigLIP2 text tower — reuses the
/// same base [loadEmbeddingTokenizer] (`.json`/`.model` branch) as Gemma, but
/// wraps it with SigLIP's no-BOS/single-EOS/lowercase convention instead.
Future<EmbeddingTokenizer> loadSiglipSentencePieceEmbeddingTokenizer(
  String tokenizerPath,
) async {
  final tokenizer = await loadEmbeddingTokenizer(tokenizerPath);
  return _SiglipSentencePieceEmbeddingTokenizer(tokenizer);
}

class _SiglipSentencePieceEmbeddingTokenizer implements EmbeddingTokenizer {
  _SiglipSentencePieceEmbeddingTokenizer(this._tokenizer);

  final SentencePieceTokenizer _tokenizer;

  @override
  TokenizedInput encode(String prefix, String text) =>
      TokenizedInput(ids: encodeForSiglipEmbedding(_tokenizer, prefix + text));
}
