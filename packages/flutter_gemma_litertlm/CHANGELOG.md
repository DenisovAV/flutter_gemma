## 1.0.4
- Guard native cancel against a freed conversation to fix a use-after-free SIGSEGV when the model is closed mid-stream (#379).

## 1.0.3
- Create the native conversation off the main isolate to avoid ANRs on multimodal models (#365).
- Serialize native conversation create on the engine mutex to prevent a heap-corrupting race (#372).
- Cancel native decode before tearing a conversation down to avoid a multi-second ANR (#364, #373).

## 1.0.2
- Clamp `maxTokens` up to 1024 (min context for .litertlm) to fix the DYNAMIC_UPDATE_SLICE crash (#318).
- Honor `maxOutputTokens` (session + chat) via native `set_max_output_tokens`; skipped on NPU.

## 1.0.1
- Fix `PreferredBackend.npu` on Android (Qualcomm) + Windows (Intel): native-v0.13.1-a restores the NPU dispatch libs omitted from 1.0.0 (#155).
- Point `homepage` to fluttergemma.dev. No code change.

## 1.0.0
- Stable 1.0.0; spec imports redirected off the `dart:io` mobile lib for a wasm-clean web graph.

## 1.0.0-rc.1
- Initial release: LiteRT-LM (`.litertlm`) on-device inference engine for flutter_gemma via dart:ffi.
- Provides `LiteRtLmEngine` (InferenceEngineProvider). Owns the shared LiteRT-LM native library.
- Android, iOS, macOS, Linux, Windows + web (`@litert-lm/core`, early preview).
