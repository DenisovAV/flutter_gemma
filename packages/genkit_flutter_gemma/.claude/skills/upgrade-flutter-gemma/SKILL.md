---
name: upgrade-flutter-gemma
description: Upgrade flutter_gemma dependency - discover API changes, fix compilation, support new features, update tests, bump version
---

# Upgrade flutter_gemma dependency

Follow these phases sequentially. Do not skip phases. Ask the user before making decisions about new features in Phase 3.

## Phase 0: Resolve workspace paths

This package lives inside the `flutter_gemma` monorepo and opts into the root Dart workspace. Always resolve the repo root and package directory before editing or running commands:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
PKG_DIR="$REPO_ROOT/packages/genkit_flutter_gemma"
EXAMPLE_DIR="$PKG_DIR/example"
test -f "$PKG_DIR/pubspec.yaml"
cd "$REPO_ROOT"
```

All package-relative paths below refer to `$PKG_DIR`. Run workspace dependency commands from `$REPO_ROOT`; run example-app commands from `$EXAMPLE_DIR`.

## Phase 1: Reconnaissance

1. Run dependency discovery:
   ```bash
   (cd "$PKG_DIR" && dart pub outdated)
   (cd "$EXAMPLE_DIR" && flutter pub outdated)
   ```
2. Update the `flutter_gemma` version in both:
   - `$PKG_DIR/pubspec.yaml`
   - `$EXAMPLE_DIR/pubspec.yaml`
3. Refresh dependencies:
   ```bash
   (cd "$REPO_ROOT" && dart pub get)
   (cd "$EXAMPLE_DIR" && flutter pub get)
   ```
4. Read the new version's CHANGELOG from pub cache:
   ```bash
   find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name "flutter_gemma-*" | sort
   ```
   Then read the `CHANGELOG.md` from the latest version directory.
5. Summarize before code edits:
   - **Breaking changes**: removed/renamed APIs, changed signatures
   - **New APIs**: new parameters, methods, enums, classes
   - **Bug fixes**
   - **Deprecations**

## Phase 2: Fix Compilation

1. Run analysis:
   ```bash
   (cd "$PKG_DIR" && dart analyze)
   ```
2. Fix all compilation errors. These typically appear in package paths:

   **Checklist of files that depend on flutter_gemma API:**
   - [ ] `lib/src/flutter_gemma_runtime.dart` - `FlutterGemma.getActiveModel()`, `FlutterGemma.getActiveEmbedder()` signatures
   - [ ] `lib/src/flutter_gemma_model.dart` - `InferenceModel.createChat()` signature, `ModelResponse` pattern matching, `InferenceChat` methods
   - [ ] `lib/src/flutter_gemma_embedder.dart` - `EmbeddingModel.generateEmbeddings()` signature, `PreferredBackend` enum
   - [ ] `lib/src/converters/request_converter.dart` - `Message` constructors (`.withImage`, `.withAudio`, `.toolCall`, `.toolResponse`)
   - [ ] `lib/src/converters/response_converter.dart` - `ModelResponse` subtypes (`TextResponse`, `FunctionCallResponse`, `ParallelFunctionCallResponse`, `ThinkingResponse`)
   - [ ] `lib/src/converters/tool_converter.dart` - `Tool` constructor
   - [ ] `lib/src/flutter_gemma_plugin.dart` - `ModelType`, `ModelFileType` enums
   - [ ] `test/src/fake_runtime.dart` - `FakeInferenceModel`, `FakeInferenceChat`, `FakeEmbeddingModel` must match upstream abstract class signatures

3. Repeat `dart analyze` until clean.

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
4. Update `FakeInferenceModel.createChat()` in `test/src/fake_runtime.dart` - add parameter, store in `last*` field for test assertions

### New enum value, such as `ModelFileType`

1. Update comments in `lib/src/flutter_gemma_plugin.dart` (`FlutterGemmaModelConfig.fileType`)

### New method on `InferenceChat` or `InferenceModel`

1. Add override in `FakeInferenceChat` or `FakeInferenceModel` in `test/src/fake_runtime.dart`

### Changed model capabilities

1. Update `supports` map in `lib/src/flutter_gemma_plugin.dart` (`list()` method)

### Changed message handling

1. Update converters in `lib/src/converters/`
2. Update `extractSystemInstruction()` if system message handling changed

**IMPORTANT:** The `.g.dart` file is manually maintained. Always update it by hand when changing the schema unless the maintainer explicitly asks to regenerate.

## Phase 4: Tests and Review

1. **Update existing tests** that verify old behavior which has changed
2. **Add new tests** for each new feature integrated in Phase 3
3. Run package and example tests:
   ```bash
   (cd "$PKG_DIR" && flutter test)
   (cd "$EXAMPLE_DIR" && flutter test)
   ```
4. Run `/review-pr` for comprehensive review if the local Claude command is available. If that command is not installed in the current environment, run the same review checklist manually from `packages/genkit_flutter_gemma/.claude/commands/review-pr.md`.
5. Fix any issues found by the review.

## Phase 5: Finalize

1. **Bump version** in `$PKG_DIR/pubspec.yaml`:
   - Minor bump, such as `0.1.1` to `0.2.0`, if there are breaking behavioral changes
   - Patch bump, such as `0.1.1` to `0.1.2`, if only bug fixes or non-breaking additions
2. **Update `$PKG_DIR/CHANGELOG.md`** - add new version section at the top with:
   - Breaking changes prefixed with `**Breaking**:`
   - New features
   - Bug fixes
3. **Update `$PKG_DIR/README.md`**:
   - Options table if new config fields were added
   - Known Limitations section if capabilities changed
   - Quick Start or examples if API usage changed
4. **Verify everything from the right roots:**
   ```bash
   (cd "$PKG_DIR" && dart analyze)
   (cd "$PKG_DIR" && flutter test)
   (cd "$PKG_DIR" && dart pub publish --dry-run)
   (cd "$EXAMPLE_DIR" && flutter test)
   ```
   All must pass cleanly.
5. **Commit** on a feature branch from the repo root, such as `feature/flutter-gemma-X.Y.Z`, and include both workspace and example dependency updates.
