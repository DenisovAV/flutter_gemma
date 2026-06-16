## 1.0.0-rc.1
- Initial release: on-device text embeddings (Gecko / EmbeddingGemma `.tflite`) via the LiteRT C API + dart:ffi.
- Provides `LiteRtEmbeddingBackend` (EmbeddingBackendProvider); forward pass runs on a background isolate.
- Autonomous (no dependency on flutter_gemma_litertlm); shares the LiteRT-LM native library when both are present.
- Android, iOS, macOS, Linux, Windows + web (LiteRT.js).
