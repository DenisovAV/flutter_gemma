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
