# PR Review: #201 — Add desktop embeddings via TFLite C FFI

**Branch:** feature/desktop-embeddings
**Date:** 2026-03-24
**Reviewers:** 9 agents (4 platform-specific + 5 general) + Copilot CLI (pending)
**Platforms affected:** Desktop (macOS, Windows, Linux)

## Critical Issues

### C1. Linux JAR_CHECKSUM is empty — build-breaking bug
**File:** `linux/scripts/setup_desktop.sh:64`
**Reported by:** Code Reviewer, Silent Failure Hunter, Desktop Reviewer

`JAR_CHECKSUM=""` — the `verify_checksum` function compares the actual hash against an empty string, which always fails. Any fresh Linux build that downloads the JAR will fail with `exit 1`.

**Fix:** Either set the correct checksum or skip verification when empty.

### C2. No checksum verification for TFLite C library downloads
**File:** All 4 build scripts (`setup_tflite`/`install_tflite` functions)
**Reported by:** Flutter Architect, Desktop Reviewer, Silent Failure Hunter, Code Reviewer

JRE and JAR downloads verify SHA-256 checksums, but TFLite dylib is downloaded and used without integrity check. This is a supply-chain risk for a native library loaded via FFI. The CI workflow generates `checksums_tflite.txt` — those values should be added to scripts.

### C3. Tensor pointers not validated for nullptr
**File:** `lib/desktop/tflite/tflite_interpreter.dart:94-96, 130-131, 151-152`
**Reported by:** Silent Failure Hunter

`tfLiteInterpreterGetInputTensor` / `tfLiteInterpreterGetOutputTensor` can return nullptr. Used directly without null checks → segfault instead of graceful error.

## Important Issues

### I1. `createEmbeddingModel()` missing active model change detection
**File:** `lib/desktop/flutter_gemma_desktop.dart:214-218`
**Reported by:** Flutter Coder, Desktop Reviewer, Flutter Architect, Type Analyzer

Unlike `createModel()` which checks `_lastActiveInferenceSpec` and recreates, `createEmbeddingModel()` always returns the first-created instance. If the active embedding model changes, the old model is silently returned.

### I2. `TfLiteBindings` singleton ignores `libraryPath` after first load
**File:** `lib/desktop/tflite/tflite_bindings.dart:18-25`
**Reported by:** Flutter Coder, Flutter Architect, Type Analyzer, Silent Failure Hunter

Second call with different `libraryPath` silently returns the first-loaded library. Either remove the parameter or assert path matches.

### I3. `generateEmbeddings` blocks async event loop
**File:** `lib/desktop/desktop_embedding_model.dart:49-55`
**Reported by:** Flutter Coder, Flutter Architect, Type Analyzer

`_interpreter.run()` is synchronous FFI. Batch processing blocks the UI thread for the full batch duration. Should use `compute()` / isolate, or at minimum document as blocking.

### I4. `numThreads` heuristic based on `preferredBackend` is misleading
**File:** `lib/desktop/flutter_gemma_desktop.dart:248-249`
**Reported by:** Flutter Coder, Flutter Architect, Desktop Reviewer

`cpu ? 4 : 6` — TFLite C API has no GPU delegate configured, so GPU preference only changes CPU thread count with no actual GPU acceleration.

### I5. `close()` does not handle errors from `_interpreter.close()` or `onClose()`
**File:** `lib/desktop/desktop_embedding_model.dart:64-69`
**Reported by:** Silent Failure Hunter, Type Analyzer

If `_interpreter.close()` throws, `onClose()` never executes → parent state stuck. Should use try-finally.

### I6. `TfLiteInterpreterCreateWithSelectedOps` may not exist in the library
**File:** `lib/desktop/tflite/tflite_bindings.dart:90-97`, `tflite_interpreter.dart:72-75`
**Reported by:** Desktop Reviewer, Flutter Coder

The CI builds `//tensorflow/lite/c:tensorflowlite_c` which may not include the `WithSelectedOps` symbol. `late final` lookup will throw `ArgumentError` instead of returning nullptr. Fallback should use `providesSymbol()` or try-catch.

### I7. `_taskPrefix` duplicated across 4 platform implementations
**File:** `lib/desktop/desktop_embedding_model.dart:25`
**Reported by:** Flutter Architect

Same literal in iOS Swift, Web JS, and now Desktop Dart. Drift risk. Should be documented centrally.

### I8. Build scripts silently return 0 on TFLite download failure
**File:** All 4 build scripts
**Reported by:** Silent Failure Hunter

TFLite download failures return 0 (success). Build completes, app crashes at runtime with cryptic FFI error.

## Minor Issues

| # | File | Issue | Reported by |
|---|------|-------|-------------|
| M1 | `tflite_interpreter.dart:60-75` | Excessive debugPrint with raw pointer addresses | Flutter Coder |
| M2 | `tflite_bindings.dart:33-36` | macOS Resources fallback path not existence-checked | Flutter Architect |
| M3 | `desktop_embedding_test.dart` | `print()` used instead of `debugPrint()` (7 occurrences) | Flutter Coder |
| M4 | `desktop_embedding_model.dart:22` | `tokenize` and `onClose` are public fields (should be private) | Type Analyzer |
| M5 | `flutter_gemma_desktop.dart:356-359` | `isDesktop` top-level getter exported unintentionally | Flutter Coder |
| M6 | `tflite_interpreter.dart:99-102` | `tfLiteTensorDim` return not validated for <= 0 | Type Analyzer, Silent Failure Hunter |
| M7 | `pubspec.yaml:34-38` | `ffi` and `dart_sentencepiece_tokenizer` as unconditional deps | Flutter Architect |
| M8 | `macos/scripts` | JRE copy depth differs between `setup_desktop.sh` and `prepare_resources.sh` | Desktop Reviewer |
| M9 | CI workflow | `softprops/action-gh-release@v1` — v2 available | Desktop Reviewer |
| M10 | `macos/Resources/tflite/` | Binary committed to repo (increases clone size) | Desktop Reviewer |

## Passed Checks

- **Android** — No Android changes. PASSED.
- **iOS** — No iOS changes (only macOS podspec version bump). PASSED.
- **Web** — No Web changes. PASSED.
- **PreferencesKeys usage** — Correct: `PreferencesKeys.embeddingModelFile`, `PreferencesKeys.embeddingTokenizerFile`. PASSED.
- **Resource cleanup** — `close()` calls `interpreter.close()` and `onClose()`. `TfLiteInterpreter.close()` frees both interpreter and model. PASSED.
- **FFI memory management** — `malloc`/`free` balanced with `try/finally` in `run()`. PASSED.
- **No AI attribution** — No Co-Authored-By or Claude mentions. PASSED.
- **`flutter analyze`** — 0 issues in `lib/`. PASSED.

## False Positives Discarded

- **C1 from Flutter Coder** — "Missing `dart:typed_data` import" — `package:flutter/foundation.dart` re-exports `dart:typed_data`, so `Int32List` is available. Verified by `flutter analyze` passing with 0 issues. NOT a bug.
- **I6 from Flutter Coder** — "Unsafe `as` cast on activeModel" — this cast is in `createModel()` which is pre-existing code, not changed in this PR. Out of scope.

## Summary

- **Critical:** 3
- **Important:** 8
- **Minor:** 10
- **Recommendation:** REQUEST CHANGES (3 critical issues must be fixed before merge)

### Top 3 Priority Fixes
1. **C1** — Linux JAR_CHECKSUM empty → immediate build failure on Linux
2. **C2** — TFLite dylib checksum verification missing → supply-chain risk
3. **I1** — Stale embedding singleton → incorrect model returned after reinstall
