## 0.3.0

- Add web text generation via Transformers.js (`@huggingface/transformers`) — `OnnxEngine` web arm (WebGPU/WASM, HF-repo-id models).
- Fix iOS embeddings: probe ORT `GetApi` down from v27 (the ORT inside onnxruntime-genai predates 1.27).
- Device-verify embeddings on iOS + Android + macOS (unified `onnx_embedding_device_test`).

## 0.2.0

- Add web support for `OnnxEmbeddingBackend` via onnxruntime-web (WebGPU/WASM, WordPiece models).
- `OnnxEngine` (text generation) declines on web for now — Transformers.js support is a fast-follow.

## 0.1.0

- Initial release: `OnnxEngine` — ORT-GenAI text generation over `dart:ffi`, macOS/Linux/Windows/Android/iOS arm64.
- Add `OnnxEmbeddingBackend`: plain ONNX Runtime embedding forward pass over `dart:ffi` (no ORT GenAI).
- Fix ORT/GenAI co-location via `ORT_LIB_PATH` (dladdr) — no Podfile/packaging step needed.
- Harden `GenAiFfiClient` lifecycle: cancel/stop/close races can no longer wedge the mutex or hang a caller.
- Platform-gate both engines to macOS/Linux/Windows/Android arm64 + iOS arm64; other hosts fail loud, not with a confusing native error.
- Add `OrtClient`/`OrtFfiClient`: injectable ORT 1.27.0 C API seam, fake-testable with zero dlopen.
- Verified against real all-MiniLM-L6-v2 (WordPiece) and EmbeddingGemma-300M-ONNX (SentencePiece) models on macOS.
