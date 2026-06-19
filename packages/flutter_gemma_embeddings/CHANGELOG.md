## 1.0.1
- Rebuild on native-v0.13.1-a (shares the LiteRT-LM native bundle; restores NPU dispatch libs, #155). No embeddings API change.

## 1.0.0
- Stable 1.0.0; spec imports redirected off the `dart:io` mobile lib for a wasm-clean web graph.

## 1.0.0-rc.1
- Initial release: on-device text embeddings (Gecko / EmbeddingGemma `.tflite`) via the LiteRT C API + dart:ffi.
- Provides `LiteRtEmbeddingBackend` (EmbeddingBackendProvider); forward pass runs on a background isolate.
- Autonomous (no dependency on flutter_gemma_litertlm); shares the LiteRT-LM native library when both are present.
- Android, iOS, macOS, Linux, Windows + web (LiteRT.js).
