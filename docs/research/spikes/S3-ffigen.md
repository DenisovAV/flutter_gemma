# Spike S3: ffigen bindings + host dlopen smoke for ORT-GenAI and plain ORT C APIs

**Date:** 2026-06-21
**ORT-GenAI version:** 0.14.0
**Plain ORT version:** 1.27.0
**Host platform:** macOS arm64 (Darwin 24.5.0, Dart SDK 3.12.0)
**Status:** PASS — all four steps completed successfully. Escalation NOT required.

---

## Step 1: C Headers obtained

### ORT-GenAI — `ort_genai_c.h`

| Field | Value |
|---|---|
| Source repo | `microsoft/onnxruntime-genai` |
| Tag | `v0.14.0` |
| Commit SHA | `b7a6ec307bea84e3b64aa33d59bcad817122d9af` |
| Raw URL | `https://raw.githubusercontent.com/microsoft/onnxruntime-genai/v0.14.0/src/ort_genai_c.h` |
| Lines | 1205 |
| Stored at | `packages/_onnx_ffigen_spike/native/headers/ort_genai_c.h` |

**No dependencies:** `ort_genai_c.h` is self-contained — only standard C headers (`<stddef.h>`, `<stdint.h>`, `<stdbool.h>`). All `OGA*` structs are opaque forward declarations (no definitions shipped in the public header — intentional ABI isolation).

### Plain ORT — `onnxruntime_c_api.h` + `onnxruntime_ep_c_api.h`

| Field | Value |
|---|---|
| Source repo | `microsoft/onnxruntime` |
| Tag | `v1.27.0` |
| Commit SHA | `8f0278c77bf44b0cc83c098c6c722b92a36ac4b5` |
| Raw URL (main) | `https://raw.githubusercontent.com/microsoft/onnxruntime/v1.27.0/include/onnxruntime/core/session/onnxruntime_c_api.h` |
| Raw URL (ep) | `https://raw.githubusercontent.com/microsoft/onnxruntime/v1.27.0/include/onnxruntime/core/session/onnxruntime_ep_c_api.h` |
| Lines (main) | 8648 |
| Stored at | `packages/_onnx_ffigen_spike/native/headers/onnxruntime_c_api.h` + `onnxruntime_ep_c_api.h` |

**Dependency note:** `onnxruntime_c_api.h` `#include`s `onnxruntime_ep_c_api.h` at line 8648. Both files must be in the same include directory. ffigen failed with a fatal error (`'onnxruntime_ep_c_api.h' file not found`) on the first run — resolved by downloading both files.

**`ORT_API_VERSION`:** 27 (defined at line 41 of `onnxruntime_c_api.h`).

---

## Step 2: ffigen configs + generated bindings

### Config: `ffigen_genai.yaml`

Located at `packages/_onnx_ffigen_spike/ffigen_genai.yaml`.

**Key decisions:**
- `functions.include: ['Oga.*']` — binds all public `OGA_EXPORT` functions.
- `structs.include: ['Oga.*']` — binds the opaque struct typedefs (forward-declared only; "No definition found" warnings are expected and harmless).
- `compiler-opts: ['-D__APPLE__']` — ensures the macOS branch of `OGA_EXPORT` (`__attribute__((visibility("default")))`) is selected, not the Windows `__declspec` branch.
- No `include-directives` filtering needed — the header is clean (no system-header noise via `OGA_EXPORT`).

**Generated file:** `packages/_onnx_ffigen_spike/lib/src/ort_genai_bindings.g.dart`

**Key symbols confirmed bound:**

| Symbol | Occurrences in .g.dart | Role |
|---|---|---|
| `OgaCreateModel` | 19 | Load a model from a config dir |
| `OgaCreateGeneratorParams` | 7 | Create generation parameters |
| `OgaGenerator_GenerateNextToken` | 7 | Stream one token |
| `OgaCreateTokenizer` | 19 | Create tokenizer from model |
| `OgaDestroyModel` | ~5 | Release model |
| `OgaDestroyResult` | ~5 | Release OgaResult (error type) |
| `OgaResultGetError` | ~5 | Get error string from OgaResult |

**ffigen run command:**
```bash
cd packages/_onnx_ffigen_spike
dart run ffigen --config ffigen_genai.yaml
```

**Output:** `[INFO]: Finished, Bindings generated in ...ort_genai_bindings.g.dart`
Only `[WARNING]` lines for opaque structs — no `[SEVERE]` errors.

---

### Config: `ffigen_ort.yaml`

Located at `packages/_onnx_ffigen_spike/ffigen_ort.yaml`.

**Key decisions:**
- `functions.include: ['OrtGetApiBase']` — only ONE real exported C function in the ORT API.
- `structs.include: ['OrtApiBase', 'OrtApi', ...]` — bind the struct-of-function-pointers entry point and the opaque handle types.
- `compiler-opts` includes `-D__APPLE__`, `-D__arm64__`, `-DNO_EXCEPTION=`, `-DORT_API_VERSION=` to resolve platform branches in the header.
- All ORT structs are opaque (private implementation) — same "No definition found" warning pattern as GenAI; expected and harmless.

**Generated file:** `packages/_onnx_ffigen_spike/lib/src/onnxruntime_bindings.g.dart`

**Key symbols confirmed bound:**

| Symbol | Occurrences in .g.dart | Role |
|---|---|---|
| `OrtGetApiBase` | 8 | The ONLY exported C function — entry point |
| `OrtApiBase` | 10 | Struct with `GetApi` + `GetVersionString` fn ptrs |
| `OrtApi` | bound as struct | Giant struct-of-function-pointers (CreateEnv, CreateSession, Run, GetTensorMutableData, etc.) |

**OrtApi members exercised via function pointer (NOT separately exported symbols):**
- `CreateEnv` — accessible via `ortApi.ref.CreateEnv`
- `CreateSession` — accessible via `ortApi.ref.CreateSession`
- `Run` — accessible via `ortApi.ref.Run`
- `GetTensorMutableData` — accessible via `ortApi.ref.GetTensorMutableData`
- `ReleaseSession`, `ReleaseEnv`, `ReleaseStatus` — for cleanup

**Phase A usage pattern:**
```dart
final ortLib = DynamicLibrary.open('libonnxruntime.dylib');
final bindings = OnnxRuntimeBindings(ortLib);
final apiBase = bindings.OrtGetApiBase();          // non-null confirmed
final api = apiBase.ref.GetApi.asFunction<...>()(ORT_API_VERSION);  // non-null confirmed
// Then: api.ref.CreateEnv(...), api.ref.CreateSession(...), etc.
```

**ffigen run command:**
```bash
cd packages/_onnx_ffigen_spike
dart run ffigen --config ffigen_ort.yaml
```

**Output:** `[INFO]: Finished, Bindings generated in ...onnxruntime_bindings.g.dart`
Only `[WARNING]` lines for opaque structs — no `[SEVERE]` errors after the `onnxruntime_ep_c_api.h` dependency was resolved.

---

## Step 3: Host smoke — macOS arm64

### Downloads

Both archives verified against SHA256 constants from S1/S2:

| Archive | SHA256 | Status |
|---|---|---|
| `onnxruntime-genai-0.14.0-osx-arm64.tar.gz` | `56583c98e3939d2cfd5a3812471be44017ce2752776d389015ff583a8d758312` | MATCH |
| `onnxruntime-osx-arm64-1.27.0.tgz` | `545e81c58152353acb0d1e8bd6ce4b62f830c0961f5b3acfedc790ffd76e477a` | MATCH |

Both archives extracted to `/tmp/ort_genai_smoke/libs/` (co-location directory):
```
libonnxruntime-genai.dylib   10,096,736 bytes
libonnxruntime.dylib         (symlink → libonnxruntime.1.27.0.dylib)
libonnxruntime.1.27.0.dylib  38,313,360 bytes
```

### Co-location confirmation (macOS)

`otool -L libonnxruntime-genai.dylib` shows NO `libonnxruntime.dylib` in `LC_LOAD_DYLIB` entries — only Apple frameworks + `libSystem.B.dylib` + `libc++.1.dylib`. This confirms the S2 finding: genai's ORT dependency is resolved via runtime `dlopen("libonnxruntime.dylib")` from source (NOT a link-time dependency). The `GetCurrentModuleDir()` fallback in `LoadDynamicLibraryIfExists` resolves the co-located dylib automatically. **No `install_name_tool` needed.**

### Smoke script

`packages/_onnx_ffigen_spike/bin/smoke.dart`

**Run:**
```bash
cd packages/_onnx_ffigen_spike
dart run bin/smoke.dart /tmp/ort_genai_smoke/libs
```

### Output (verbatim)

```
--- S3 HOST DLOPEN SMOKE ---
libs dir: /tmp/ort_genai_smoke/libs

[ORT] Loading /tmp/ort_genai_smoke/libs/libonnxruntime.dylib ...
[ORT] LOADED OK
[ORT] Looking up OrtGetApiBase ...
[ORT] Calling OrtGetApiBase() ...
[ORT] OrtGetApiBase() => 12d3150e0 (non-null)
[ORT] Calling apiBase->GetApi(ORT_API_VERSION=27) ...
[ORT] GetApi(27) => 12d3143b0 (non-null)
[ORT] PASS: OrtGetApiBase + GetApi callable, OrtApi* is non-null

[GenAI] Loading /tmp/ort_genai_smoke/libs/libonnxruntime-genai.dylib ...
[GenAI] LOADED OK
[GenAI] Creating bindings and looking up key symbols ...
[GenAI] OgaCreateModel => 1298d1ad0 (non-null)
[GenAI] OgaCreateGeneratorParams => 1298d1d80 (non-null)
[GenAI] OgaGenerator_GenerateNextToken => 1298d2b10 (non-null)
[GenAI] OgaCreateTokenizer => 1298d3ba4 (non-null)
[GenAI] PASS: All 4 key symbols resolvable

[Co-location] Both dylibs in same dir: /tmp/ort_genai_smoke/libs
[Co-location] libonnxruntime-genai.dylib uses bare-name dlopen()
[Co-location] GetCurrentModuleDir() fallback resolves co-located libonnxruntime.dylib
[Co-location] install_name_tool NOT needed (S2 confirmed)

=== ALL SMOKE CHECKS PASSED ===

Summary:
  [ORT]   libonnxruntime.dylib          loaded OK
  [ORT]   OrtGetApiBase()                non-null
  [ORT]   GetApi(27)                     non-null OrtApi*
  [GenAI] libonnxruntime-genai.dylib     loaded OK (co-location)
  [GenAI] OgaCreateModel                 resolvable
  [GenAI] OgaCreateGeneratorParams       resolvable
  [GenAI] OgaGenerator_GenerateNextToken resolvable
  [GenAI] OgaCreateTokenizer             resolvable
```

**All checks passed. No missing-symbol or dlopen errors.**

---

## Key findings for Phase A/C

### ffigen findings

1. **ORT-GenAI header is self-contained.** Only `ort_genai_c.h` needed — no extra includes. All structs are opaque (forward-declared only). ffigen output has `[WARNING]` only, no `[SEVERE]`.

2. **ORT header needs companion file.** `onnxruntime_c_api.h` `#include`s `onnxruntime_ep_c_api.h` at the end. Both must be in the include directory. Phase A/C hooks must download both files, or use `-I` pointing to the extracted archive's `include/` directory (which contains both).

3. **ORT is struct-of-function-pointers.** Only `OrtGetApiBase` is a real exported symbol. All session/env/run functions are accessed via `OrtApi` struct members. The ffigen config binds `OrtApiBase` and `OrtApi` as structs with `NativeFunction` pointer fields.

4. **ffigen version 20.1.1 works with Dart 3.12.0** for both headers without errors.

5. **The `onnxruntime_ep_c_api.h` companion** defines EP (Execution Provider) plugin types used by the new EP framework in ORT 1.27. Phase A (embedder) does not need EP types — they can be excluded from the Phase A ffigen config's `structs.include` list to reduce generated code size.

### dlopen / co-location findings

6. **Co-location works without `install_name_tool`.** Both dylibs in the same directory; `libonnxruntime-genai.dylib` loaded OK and all GenAI symbols resolved. S2's `GetCurrentModuleDir()` analysis confirmed correct.

7. **Load order matters on macOS.** Load `libonnxruntime.dylib` BEFORE `libonnxruntime-genai.dylib`. This ensures the bare-name `dlopen("libonnxruntime.dylib")` inside genai's `InitApi()` finds the already-loaded handle in the process image (RTLD_NOLOAD path). If genai loads first and ORT is not yet in the process, genai's `InitApi()` will still find it via the `GetCurrentModuleDir()` fallback since both dylibs are co-located — but loading ORT first is safer and mirrors what the Native Assets hook will do (both registered as CodeAssets, ORT listed first).

8. **`libonnxruntime.dylib` is a symlink.** The plain-ORT macOS tarball provides both `lib/libonnxruntime.dylib` (symlink) and `lib/libonnxruntime.1.27.0.dylib` (versioned). The hook must preserve the symlink (use `cp -P` or `tar -xzf` which preserves symlinks). `dlopen("libonnxruntime.dylib")` resolves through the symlink.

### Phase A/C action items

| Item | Action |
|---|---|
| **ORT ffigen config for Phase A** | Use `ffigen_ort.yaml` from this spike as the seed. Narrow `structs.include` to only what the embedder uses (can drop EP structs, CUDA/TensorRT structs). |
| **GenAI ffigen config for Phase C** | Use `ffigen_genai.yaml` from this spike as the seed. No changes needed — all `Oga.*` functions are already included. |
| **Phase A hook includes** | Download both `onnxruntime_c_api.h` + `onnxruntime_ep_c_api.h` from `include/onnxruntime/core/session/` in the ORT release tarball, OR use the `include/` dir from the already-fetched ORT archive as the `-I` path. |
| **Phase C hook includes** | Download `ort_genai_c.h` from the `include/` dir of the ORT-GenAI release tarball. Self-contained. |
| **Load order** | Hook should register ORT CodeAsset before GenAI CodeAsset in `output.assets.code.add()`. |
| **Symlink preservation** | `tar -xzf` on macOS preserves symlinks by default. The `libonnxruntime.dylib` symlink in the ORT tarball is correctly extracted. |

---

## Package layout

```
packages/_onnx_ffigen_spike/
├── pubspec.yaml                        # standalone Dart package (not in workspace)
├── ffigen_genai.yaml                   # ffigen config for ort_genai_c.h
├── ffigen_ort.yaml                     # ffigen config for onnxruntime_c_api.h
├── native/headers/
│   ├── ort_genai_c.h                   # ORT-GenAI 0.14.0 (commit b7a6ec307bea)
│   ├── onnxruntime_c_api.h             # ORT 1.27.0 (commit 8f0278c77bf4)
│   └── onnxruntime_ep_c_api.h          # ORT 1.27.0 companion (required by c_api.h)
├── lib/src/
│   ├── ort_genai_bindings.g.dart       # generated by ffigen_genai.yaml
│   └── onnxruntime_bindings.g.dart     # generated by ffigen_ort.yaml
└── bin/
    └── smoke.dart                      # host dlopen smoke (macOS arm64)
```

---

## Escalation: NOT required

All four spike steps completed successfully:
- Both ffigen configs generate valid bindings (no `[SEVERE]` errors).
- All 4 required GenAI symbols bound and resolvable at runtime.
- `OrtGetApiBase()` callable and returns non-null; `GetApi(27)` returns non-null `OrtApi*`.
- `libonnxruntime-genai.dylib` loads with co-located `libonnxruntime.dylib` — no dlopen errors.

Phase A (`flutter_gemma_onnx_embeddings`) and Phase C (`flutter_gemma_onnx` generator) may proceed.
