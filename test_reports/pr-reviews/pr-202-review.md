# PR Review: #202 — Fix CI workflow and add TFLite checksums

**Branch:** feature/desktop-embeddings
**Date:** 2026-03-25
**Reviewers:** 7 agents (1 platform-specific + 6 general)
**Platforms affected:** Desktop (macOS, Linux, Windows), CI

## Critical Issues

### C1. Linux JAR_CHECKSUM is empty — JAR integrity not verified
**File:** `linux/scripts/setup_desktop.sh:64`
**Agents:** Desktop, Code Reviewer, Silent Failure Hunter, Flutter Architect

`JAR_CHECKSUM=""` means Linux users download an unverified JAR. macOS and Windows have valid checksums (`fefc53d...`). Since the JAR is the same file for all platforms, add the same checksum.

**Fix:** `JAR_CHECKSUM="fefc53d076533de164b5ce07c65f9aedc4739f83efc93e67625f0d90029ae5b7"`

### C2. `TfLiteInterpreterCreateWithSelectedOps` lookup crashes if symbol missing
**File:** `lib/desktop/tflite/tflite_bindings.dart:90-97`
**Agents:** Flutter Architect, Flutter Coder

CI builds `//tensorflow/lite/c:tensorflowlite_c` which does NOT export `TfLiteInterpreterCreateWithSelectedOps`. The `late final` binding resolves lazily, so it won't crash at load time. But if `tfLiteInterpreterCreate` returns nullptr and the fallback at `tflite_interpreter.dart:76-78` is reached, `DynamicLibrary.lookup()` throws `ArgumentError` instead of returning nullptr.

**Fix:** Guard with `_lib.providesSymbol('TfLiteInterpreterCreateWithSelectedOps')` before lookup, or wrap in try-catch.

### C3. Build scripts return success (return 0) on TFLite download/checksum failures
**File:** `macos/scripts/prepare_resources.sh:405-408,416-419`, `macos/scripts/setup_desktop.sh:503-507,514-519`, `linux/scripts/setup_desktop.sh:288-292`
**Agents:** Silent Failure Hunter, Desktop

Download failures and checksum mismatches for TFLite print "WARNING"/"ERROR" but return 0 (success). Build completes, user sees success, then gets runtime crash from `DynamicLibrary.open()` failure.

**Fix:** Change `return 0` to `return 1` on checksum mismatch; consider `exit 1` on download failure (consistent with JRE/JAR handling).

## Important Issues

### I1. TfLiteInterpreter leaked on tokenizer load failure
**File:** `lib/desktop/flutter_gemma_desktop.dart:265-317`
**Agents:** Silent Failure Hunter

`TfLiteInterpreter.fromFile()` is created at line 268. If tokenizer loading (lines 284-295) throws, the catch block rethrows but never calls `interpreter.close()`. Native memory leaks.

**Fix:** Add `interpreter.close()` in the catch block before rethrowing.

### I2. `generateEmbeddings` blocks UI thread for entire batch
**File:** `lib/desktop/desktop_embedding_model.dart:49-54`
**Agents:** Flutter Coder, Flutter Architect, Type Design Analyzer, Code Reviewer

`_interpreter.run()` is synchronous FFI. `async` keyword gives false impression of non-blocking. N texts = N * inference_time of UI jank.

**Fix:** Use `Isolate.run()` or `compute()`, or document as blocking call. Note: TfLiteInterpreter holds native pointers that can't cross isolate boundaries easily — consider a long-lived background isolate.

### I3. Public `tokenize` and `onClose` fields break encapsulation
**File:** `lib/desktop/desktop_embedding_model.dart:20,22`
**Agents:** Type Design Analyzer, Flutter Architect

External code can call `model.tokenize("text")` bypassing close guard and task prefix. `model.onClose()` can corrupt parent state without closing interpreter.

**Fix:** Make both fields private: `_tokenize`, `_onClose`.

### I4. Stale singleton returned when `currentActiveModel` is null
**File:** `lib/desktop/flutter_gemma_desktop.dart:220-221`
**Agents:** Flutter Coder, Flutter Architect

When `currentActiveModel` is null, `modelChanged` is false and existing (possibly wrong) singleton is returned.

**Fix:** Add null check for `currentActiveModel` before singleton guard.

### I5. `preferredBackend: gpu` silently becomes 6 CPU threads
**File:** `lib/desktop/flutter_gemma_desktop.dart:266-271`
**Agents:** Flutter Architect, Flutter Coder

No GPU delegate is configured. `PreferredBackend.gpu` → 6 threads, not GPU. Broken contract.

**Fix:** Log warning that GPU not implemented for desktop embeddings, or remove parameter.

### I6. macOS `prepare_resources.sh` missing codesign for TFLite dylib
**File:** `macos/scripts/prepare_resources.sh:374-441`
**Agents:** Code Reviewer

`setup_desktop.sh` signs and removes quarantine, but `prepare_resources.sh` does not. Downloaded dylib will be blocked by Gatekeeper.

**Fix:** Add `xattr -r -d com.apple.quarantine` and `codesign --force --sign -` after copy.

### I7. `TfLiteBindings` singleton ignores `libraryPath` after first call
**File:** `lib/desktop/tflite/tflite_bindings.dart:18-24`
**Agents:** Desktop, Flutter Coder, Type Design Analyzer

Second call with different `libraryPath` silently returns first library.

**Fix:** Assert path matches or remove parameter.

### I8. JAR checksums may be stale after version bump to 0.12.7
**File:** `macos/scripts/prepare_resources.sh:44`, `macos/scripts/setup_desktop.sh:63`, `windows/scripts/setup_desktop.ps1:92`
**Agents:** Code Reviewer

JAR_VERSION bumped to 0.12.7 but checksums may be from 0.12.6. If JAR content changed, verification will fail at build time.

**Fix:** Verify checksum matches v0.12.7 JAR, or clear until new JAR is published.

## Minor Issues

| # | File:Line | Issue | Agents |
|---|-----------|-------|--------|
| M1 | `tflite_interpreter.dart:9` | `TfLiteStatus` is instantiable — add private constructor | Type Design |
| M2 | `tflite_interpreter.dart` | No `NativeFinalizer` — forgot `close()` = permanent native leak | Type Design |
| M3 | `tflite_bindings.dart:30-36` | No logging of resolved library path | Silent Failure |
| M4 | `desktop_embedding_model.dart:25` | Hardcoded task prefix — model-specific, not configurable | Desktop, Type Design |
| M5 | `flutter_gemma_desktop.dart:152` | `.values.first` for model path is fragile — use PreferencesKeys | Flutter Coder |
| M6 | `build-tflite.yml:113` | `softprops/action-gh-release@v1` outdated — use @v2 | Desktop |
| M7 | `pubspec.yaml:34,38` | `ffi` and `dart_sentencepiece_tokenizer` are unconditional deps consumed only by desktop | Flutter Architect |
| M8 | `desktop_embedding_test.dart:60` | Hardcoded `expect(768)` — use `model.getDimension()` | Flutter Architect |
| M9 | `windows/scripts/setup_desktop.ps1:493-509` | DXC download has no checksum | Silent Failure |
| M10 | `windows/scripts/setup_desktop.ps1:567-571` | TFLite checksum mismatch is warning, not error | Silent Failure |

## Passed Checks

- No AI attribution in commits (all 5 commits clean)
- No inline string keys — `PreferencesKeys` constants used correctly
- `EmbeddingModel` interface fully implemented
- FFI memory management in `run()` is correct (malloc/free balanced with try/finally)
- `dart:typed_data` / `Int32List` available via `foundation.dart` re-export (false positive from some agents)
- `close()` uses try/finally — `onClose()` guaranteed to execute
- Three-layer architecture (TfLiteInterpreter → DesktopEmbeddingModel → FlutterGemmaDesktop) is clean
- TFLite checksums now populated for all 4 CI-built platforms
- JRE version (Azul Zulu 24.0.2) consistent across all scripts
- CI workflow correctly uses `bazel-contrib/setup-bazel@0.19.0`

## Summary
- Critical: 3
- Important: 8
- Minor: 10
- **Recommendation: REQUEST CHANGES**

Top 3 priorities:
1. **C1** — Add Linux JAR checksum (1-line fix)
2. **C2** — Guard `CreateWithSelectedOps` symbol lookup
3. **I1** — Close interpreter on tokenizer failure
