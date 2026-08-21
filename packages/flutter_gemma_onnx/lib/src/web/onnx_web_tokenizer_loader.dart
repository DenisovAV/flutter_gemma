// Web arm of the ONNX embedding tokenizer routing (ONNX web PR,
// `feat/onnx-web`, Task 2.1/2.3). Pure Dart — no `dart:io`, no
// `dart:js_interop` — unit-testable under plain `flutter test` (VM). The
// caller (`onnx_web_embedding_model.dart`) fetches the tokenizer file's TEXT
// over the network first (a web-only concern, `dart:js_interop`'s `fetch`)
// and hands it here already decoded to a string.
//
// v1 scope: WordPiece only (MiniLM-family `tokenizer.json` exports). The
// native arm additionally supports Gemma SentencePiece
// (EmbeddingGemma-300M-ONNX) via `dart_sentencepiece_tokenizer`, which
// imports `dart:io`/`dart:isolate` UNCONDITIONALLY at its own package root —
// not a "small refactor" gap like the WordPiece `fromPath` split was, but a
// missing pure-Dart SentencePiece implementation. Left as a known, loudly
// documented gap (see [UnsupportedError] below) rather than silently
// mis-tokenizing — native platforms are completely unaffected.
import 'dart:convert';

import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'
    show EmbeddingTokenizer;
import 'package:flutter_gemma_embeddings/wordpiece_embedding_tokenizer.dart'
    show WordPieceEmbeddingTokenizer;

/// Parses an already-fetched `tokenizer.json` [text] into an
/// [EmbeddingTokenizer]. Throws [FormatException] if [text] isn't valid JSON,
/// and [UnsupportedError] if it parses but isn't a WordPiece tokenizer (e.g.
/// a Gemma SentencePiece/BPE `tokenizer.json` — see this file's module doc).
EmbeddingTokenizer parseOnnxEmbeddingTokenizerWeb(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  if (!WordPieceEmbeddingTokenizer.isWordPieceJson(json)) {
    throw UnsupportedError(
      'OnnxEmbeddingBackend (web) only supports WordPiece tokenizer.json '
      'exports in this release (e.g. all-MiniLM-L6-v2 and other BERT-family '
      'models) — got model.type="${(json['model'] as Map?)?['type']}". '
      'SentencePiece (EmbeddingGemma-300M-ONNX) needs a pure-Dart parser '
      'that does not exist yet (the native arm\'s '
      'dart_sentencepiece_tokenizer package imports dart:io/dart:isolate '
      'unconditionally and cannot run on web). Native platforms are '
      'unaffected — this is a web-only gap.',
    );
  }
  return WordPieceEmbeddingTokenizer.fromJsonString(text);
}
