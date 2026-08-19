// Tokenizer routing for the ONNX embedding backend (Phase 2 — plain-ORT
// embedding forward pass, hardened plan Task 3).
//
// One factory covers both model families this backend targets — MiniLM
// (WordPiece `tokenizer.json`) and EmbeddingGemma-300M-ONNX (SentencePiece,
// either a raw binary `tokenizer.model`/`sentencepiece.model` OR a
// HuggingFace `tokenizer.json` whose `model.type` is `BPE`/`Unigram`, NOT
// `WordPiece`) — with no per-model config: it sniffs [tokenizerPath] (inside
// the worker isolate, per the sendability rule on
// `EmbeddingTokenizerFactory`) and routes to whichever adapter matches
// (design D-T1).
//
// The sniff MUST tolerate a non-JSON file: `onnx-community/
// embeddinggemma-300m-ONNX` ships BOTH a `tokenizer.json` (HF format, BPE)
// AND a raw-binary SentencePiece `tokenizer.model` — either is a valid
// install choice, and the raw `.model` is NOT valid UTF-8/JSON at all
// (`jsonDecode`/`readAsString` throws on it) — verified against the real
// downloaded file. WordPiece detection is therefore attempted, and any
// failure to parse as JSON falls through to the SentencePiece adapter
// (which itself branches on `.json` vs raw `.model`, matching the LiteRT
// path's `loadEmbeddingTokenizer`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma_embeddings/embedding_tokenizer.dart'
    show loadGemmaSentencePieceEmbeddingTokenizer;
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'
    show EmbeddingTokenizer;
import 'package:flutter_gemma_embeddings/wordpiece_embedding_tokenizer.dart'
    show WordPieceEmbeddingTokenizer;

/// [EmbeddingTokenizerFactory] tear-off (production path for the ONNX
/// backend). Routes:
///  - [tokenizerPath] parses as JSON AND `WordPieceEmbeddingTokenizer.isWordPieceJson`
///    matches -> WordPiece (MiniLM and BERT-family models).
///  - otherwise (not JSON at all — a raw SentencePiece `.model` binary — or
///    JSON but not a WordPiece model, e.g. HF `tokenizer.json` with
///    `model.type: BPE`) -> the Gemma SentencePiece adapter, same convention
///    as the LiteRT path (see `embedding_tokenizer.dart`'s byte-identity
///    guard).
Future<EmbeddingTokenizer> loadOnnxEmbeddingTokenizer(
  String tokenizerPath,
) async {
  // Only attempt to read+decode as JSON for a `.json`-named file — a raw
  // SentencePiece `.model` binary is not valid UTF-8 at all, and
  // `File.readAsString` throws `FileSystemException` (not `FormatException`)
  // on invalid UTF-8, so gating on the extension avoids exception-driven
  // control flow for the common case (verified against a real
  // `tokenizer.model` download).
  if (tokenizerPath.endsWith('.json')) {
    try {
      final raw = await File(tokenizerPath).readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (WordPieceEmbeddingTokenizer.isWordPieceJson(json)) {
        return WordPieceEmbeddingTokenizer.fromJsonString(raw);
      }
    } on FormatException {
      // A `.json`-named file that isn't actually valid JSON — fall through
      // to the SentencePiece adapter's own `.json`-vs-raw branch, which
      // will surface a clearer error if it's not SentencePiece either.
    }
  }
  return loadGemmaSentencePieceEmbeddingTokenizer(tokenizerPath);
}
