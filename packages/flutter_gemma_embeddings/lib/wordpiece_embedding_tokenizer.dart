/// Public, native-only export of [WordPieceEmbeddingTokenizer] for
/// native-only leaves that need to import it from a file that is itself
/// native-only (never reached on web) — engine packages' embedding backends
/// (e.g. `flutter_gemma_onnx`'s ONNX tokenizer loader, which sniffs a
/// `tokenizer.json` and routes to either this WordPiece adapter or the
/// Gemma SentencePiece one in `embedding_tokenizer.dart`).
///
/// Prefer this over
/// `package:flutter_gemma_embeddings/src/wordpiece_embedding_tokenizer.dart`
/// in native-only files — same pattern as `embedding_tokenizer.dart` at this
/// package's root and `flutter_gemma_litertlm/lib/litert_bindings.dart`.
///
/// This library is unconditional — importing it from code that is also
/// reachable on web will fail to compile there (`dart:io`). Deliberately NOT
/// re-exported from this package's main barrel (`flutter_gemma_embeddings.dart`)
/// for exactly that reason — see that barrel's module doc.
library;

export 'src/wordpiece_embedding_tokenizer.dart';
