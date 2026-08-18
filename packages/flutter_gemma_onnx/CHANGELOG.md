## 0.1.0

- Scaffold: `OnnxEngine` (InferenceEngineProvider), identity + `canHandle` only — `createModel` throws `UnimplementedError` pending the throughput go/no-go gate.
- Add `OnnxEmbeddingBackend`: plain ONNX Runtime embedding forward pass over `dart:ffi` (no ORT GenAI).
- Add `OrtClient`/`OrtFfiClient`: injectable ORT 1.27.0 C API seam, fake-testable with zero dlopen.
- Add `OnnxEmbeddingForwardPass`: static/dynamic-seq padding, mask thread, `pooledFinal`/`tokenLevel` contract dispatch.
- Verified against real all-MiniLM-L6-v2 (WordPiece) and EmbeddingGemma-300M-ONNX (SentencePiece) models on macOS.
