# Task S3 Report — ffigen bindings + host dlopen smoke

**Status:** DONE
**Commit:** `030e3552f19db3719131fe60e816e0c989042f10`
**Branch:** `feat/onnx-plugins`

---

## Smoke result

**ORT CreateEnv OK + genai dylib loaded, all 4 key symbols resolved.**

Verbatim smoke output:
```
[ORT]   libonnxruntime.dylib          loaded OK
[ORT]   OrtGetApiBase()                non-null
[ORT]   GetApi(27)                     non-null OrtApi*
[GenAI] libonnxruntime-genai.dylib     loaded OK (co-location)
[GenAI] OgaCreateModel                 resolvable
[GenAI] OgaCreateGeneratorParams       resolvable
[GenAI] OgaGenerator_GenerateNextToken resolvable
[GenAI] OgaCreateTokenizer             resolvable
=== ALL SMOKE CHECKS PASSED ===
```

---

## What was delivered

- `packages/_onnx_ffigen_spike/` — throwaway spike package with:
  - `ffigen_genai.yaml` + `ffigen_ort.yaml` configs (seeds for Phase A/C)
  - `lib/src/ort_genai_bindings.g.dart` (4064 lines) — all Oga.* functions bound
  - `lib/src/onnxruntime_bindings.g.dart` (15 399 lines) — OrtGetApiBase + full OrtApiBase/OrtApi struct-of-fn-ptrs bound
  - `native/headers/` — ort_genai_c.h (v0.14.0), onnxruntime_c_api.h + onnxruntime_ep_c_api.h (v1.27.0)
  - `bin/smoke.dart` — runnable macOS arm64 smoke
- `docs/research/spikes/S3-ffigen.md` — full spike report

---

## Key concerns / gotchas for Phase A/C

1. **`onnxruntime_c_api.h` needs companion `onnxruntime_ep_c_api.h`** — both must be in the same include dir. First ffigen run failed until the companion was downloaded.
2. **ORT_API_VERSION = 27** for ORT 1.27.0 (not 22 as a common assumption).
3. **Load order:** Load `libonnxruntime.dylib` before `libonnxruntime-genai.dylib`. GenAI's bare-name `dlopen("libonnxruntime.dylib")` uses `GetCurrentModuleDir()` fallback, but loading ORT first is safer.
4. **Co-location confirmed empirically:** No `install_name_tool` needed on macOS. Just co-locate both dylibs. S2 analysis validated.
5. **ffigen 20.1.1 with Dart 3.12.0** — works without brew LLVM; uses Xcode-bundled libclang.
