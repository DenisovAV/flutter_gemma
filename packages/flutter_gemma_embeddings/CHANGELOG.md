## 2.1.0
- Add a SigLIP2 text-embedding profile (no BOS, single trailing EOS, lowercased, fixed 64-token width).
- Restore `WordPieceEmbeddingTokenizer.fromPath`, dropped from `main` after 2.0.0 shipped; it reads through a web-safe seam now.
- Require `dart_sentencepiece_tokenizer` 1.3.3 for HuggingFace list-form `merges`.

## 2.0.0
- BREAKING: runtime-agnostic embedder; `LiteRtEmbeddingBackend` moved to flutter_gemma_litertlm.
- Add tokenizer-factory seam (`ForwardPassDescriptor.tokenizerFactory`) so engines can bring WordPiece too.
- Add `EmbeddingForwardPass.outputContract` override + `ForwardResult.attentionMask` for the mask thread.
- Add `WordPieceEmbeddingTokenizer` (BERT-style, e.g. MiniLM) alongside the existing Gemma SentencePiece adapter.

## 1.0.4
- internal: run on the flutter_gemma_litertlm LiteRT engine (no API change).

## 1.0.3
- Migrate to LiteRT v0.14.0 3-arg `LiteRtCreateModelFromFile` (adds `LiteRtEnvironment`); native-v0.14.0.

## 1.0.2
- Realign the shared LiteRT-LM native bundle to native-v0.13.1-b (#364). No API change.

## 1.0.1
- Rebuild on native-v0.13.1-a (shares the LiteRT-LM native bundle; restores NPU dispatch libs, #155). No embeddings API change.
- Point `homepage` to fluttergemma.dev. No code change.

## 1.0.0
- Stable 1.0.0; spec imports redirected off the `dart:io` mobile lib for a wasm-clean web graph.

## 1.0.0-rc.1
- Initial release: on-device text embeddings (Gecko / EmbeddingGemma `.tflite`) via the LiteRT C API + dart:ffi.
- Provides `LiteRtEmbeddingBackend` (EmbeddingBackendProvider); forward pass runs on a background isolate.
- Autonomous (no dependency on flutter_gemma_litertlm); shares the LiteRT-LM native library when both are present.
- Android, iOS, macOS, Linux, Windows + web (LiteRT.js).
