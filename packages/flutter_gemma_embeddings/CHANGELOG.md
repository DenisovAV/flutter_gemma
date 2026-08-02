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
