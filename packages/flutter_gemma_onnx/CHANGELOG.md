## 0.1.0

- Initial release: `OnnxEngine` — ORT-GenAI text generation over `dart:ffi`, macOS arm64.
- Add `OnnxEmbeddingBackend`: plain ONNX Runtime embedding forward pass over `dart:ffi` (no ORT GenAI).
- Fix ORT/GenAI co-location via `ORT_LIB_PATH` (dladdr) — no Podfile/packaging step needed.
- Harden `GenAiFfiClient` lifecycle: cancel/stop/close races can no longer wedge the mutex or hang a caller.
- Platform-gate both engines to macOS arm64; other hosts fail loud, not with a confusing native error.
- Add `OrtClient`/`OrtFfiClient`: injectable ORT 1.27.0 C API seam, fake-testable with zero dlopen.
- Verified against real all-MiniLM-L6-v2 (WordPiece) and EmbeddingGemma-300M-ONNX (SentencePiece) models on macOS.
