---
name: upgrade-flutter-gemma
description: Upgrade flutter_gemma dependency — discover API changes, fix compilation, support new features, update tests, bump version
---

# Upgrade flutter_gemma dependency

Follow these 5 phases sequentially. Do not skip phases. Ask the user before making decisions about new features (Phase 3).

## Phase 1: Reconnaissance

1. Run `dart pub outdated` to identify the available flutter_gemma version
2. Update `flutter_gemma` version in both:
   - `pubspec.yaml`
   - `example/pubspec.yaml`
3. Run `flutter pub get`
4. Read the new version's CHANGELOG from pub cache:
   ```
   find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name "flutter_gemma-*" | sort
   ```
   Then read the CHANGELOG.md from the latest version directory.
5. Summarize for the user:
   - **Breaking changes** (removed/renamed APIs, changed signatures)
   - **New APIs** (new parameters, methods, enums, classes)
   - **Bug fixes**
   - **Deprecations**

## Phase 2: Fix Compilation

1. Run `dart analyze`
2. Fix all compilation errors. These typically appear in:

   **Checklist of files that depend on flutter_gemma API:**
   - [ ] `lib/src/flutter_gemma_runtime.dart` — `FlutterGemma.getActiveModel()`, `FlutterGemma.getActiveEmbedder()` signatures
   - [ ] `lib/src/flutter_gemma_model.dart` — `InferenceModel.createChat()` signature, `ModelResponse` pattern matching, `InferenceChat` methods
   - [ ] `lib/src/flutter_gemma_embedder.dart` — `EmbeddingModel.generateEmbeddings()` signature, `PreferredBackend` enum
   - [ ] `lib/src/converters/request_converter.dart` — `Message` constructors (`.withImage`, `.withAudio`, `.toolCall`, `.toolResponse`)
   - [ ] `lib/src/converters/response_converter.dart` — `ModelResponse` subtypes (`TextResponse`, `FunctionCallResponse`, `ParallelFunctionCallResponse`, `ThinkingResponse`)
   - [ ] `lib/src/converters/tool_converter.dart` — `Tool` constructor
   - [ ] `lib/src/flutter_gemma_plugin.dart` — `ModelType`, `ModelFileType` enums
   - [ ] `test/src/fake_runtime.dart` — `FakeInferenceModel`, `FakeInferenceChat`, `FakeEmbeddingModel` must match upstream abstract class signatures

3. Repeat `dart analyze` until clean (0 issues)

## Phase 3: Support New Features

Based on the CHANGELOG from Phase 1, decide with the user which new APIs to support.

For each new feature, the typical integration points are:

### New parameter in `createChat()` or `createSession()`
1. Add field to `$FlutterGemmaModelOptions` in `lib/src/flutter_gemma_options.dart`
2. **Manually** update `lib/src/flutter_gemma_options.g.dart`:
   - Constructor parameter
   - Field declaration with `@override`
   - `fromJson` parsing
   - `toJson` serialization
   - `jsonSchema()` property entry
3. Extract from config and pass in `lib/src/flutter_gemma_model.dart` (`_executeGeneration`)
4. Update `FakeInferenceModel.createChat()` in `test/src/fake_runtime.dart` — add parameter, store in `last*` field for test assertions

### New enum value (e.g. `ModelFileType`)
1. Update comments in `lib/src/flutter_gemma_plugin.dart` (`FlutterGemmaModelConfig.fileType`)

### New method on `InferenceChat` or `InferenceModel`
1. Add override in `FakeInferenceChat` or `FakeInferenceModel` in `test/src/fake_runtime.dart`

### Changed model capabilities
1. Update `supports` map in `lib/src/flutter_gemma_plugin.dart` (`list()` method, ~line 123)

### Changed message handling
1. Update converters in `lib/src/converters/`
2. Update `extractSystemInstruction()` if system message handling changed

**IMPORTANT:** The `.g.dart` file is manually maintained (build_runner is broken). Always update it by hand when changing the schema.

## Phase 4: Tests and Review

1. **Update existing tests** that verify old behavior which has changed
2. **Add new tests** for each new feature integrated in Phase 3
3. Run `flutter test` — all tests must pass
4. Run `/pr-review-toolkit:review-pr` for comprehensive review
5. Fix any issues found by the review agents

## Phase 5: Finalize

1. **Bump version** in `pubspec.yaml`:
   - Minor bump (e.g. `0.1.1` → `0.2.0`) if there are breaking behavioral changes
   - Patch bump (e.g. `0.1.1` → `0.1.2`) if only bug fixes / non-breaking additions
2. **Update `CHANGELOG.md`** — add new version section at the top with:
   - Breaking changes (prefixed with `**Breaking**:`)
   - New features
   - Bug fixes
3. **Update `README.md`**:
   - Options table if new config fields were added
   - Known Limitations section if capabilities changed
   - Quick Start / examples if API usage changed
4. **Verify everything:**
   ```bash
   dart analyze
   flutter test
   dart pub publish --dry-run
   ```
   All must pass cleanly.
5. **Commit** on a feature branch (e.g. `feature/flutter-gemma-X.Y.Z`)
