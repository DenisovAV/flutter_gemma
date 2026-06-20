# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

The package lives in the `flutter_gemma` monorepo under
`packages/genkit_flutter_gemma`. When starting from the monorepo root, use that
directory explicitly for package commands.

```bash
# Get dependencies
dart pub get                         # from monorepo root
cd packages/genkit_flutter_gemma/example && flutter pub get

# Run all tests
flutter test

# Run a single test file
flutter test test/converters/response_converter_test.dart

# Static analysis
dart analyze

# Dry-run publish check
dart pub publish --dry-run

# Format code
dart format .
```

## Architecture

This is a **Genkit Dart plugin** that bridges [flutter_gemma](https://pub.dev/packages/flutter_gemma) (on-device AI inference) into the [Genkit](https://pub.dev/packages/genkit) framework.

### Plugin structure

`GenkitFlutterGemmaPlugin` implements Genkit's `GenkitPlugin` interface with `list()` (advertises models/embedders) and `resolve()` (lazily creates and caches actions). Models are registered under the `flutter-gemma/` prefix.

### Key abstractions

- **`FlutterGemmaRuntime`** - abstracts flutter_gemma's static API (`FlutterGemma.getActiveModel`, `FlutterGemma.getActiveEmbedder`). Production uses `DefaultFlutterGemmaRuntime`; tests use `FakeRuntime` from `test/src/fake_runtime.dart`.
- **Model action** (`flutter_gemma_model.dart`) - implements a serialized queue via future-chain lock, caches `InferenceModel` across calls, and delegates to blocking/streaming generation paths.
- **Embedder action** (`flutter_gemma_embedder.dart`) - caches `EmbeddingModel` with backend invalidation.

### Converter layer (`lib/src/converters/`)

Three converters handle the Genkit <-> flutter_gemma type boundary:
- **`request_converter.dart`** - Genkit `Message` to `gemma.Message`. System role is prepended to first user message (flutter_gemma has no system role). Media resolution supports `data:` URIs, `file://`, absolute paths, and HTTP URLs.
- **`response_converter.dart`** - `gemma.ModelResponse` to Genkit `ModelResponse`/`ModelResponseChunk`. Handles text, function calls (single and parallel), and reasoning/thinking parts.
- **`tool_converter.dart`** - Genkit `ToolDefinition` to `gemma.Tool`.

### Config options

`FlutterGemmaModelOptions` is defined via `@Schema()` annotation in `flutter_gemma_options.dart`.

**Manual `.g.dart` note**: `flutter_gemma_options.g.dart` is manually maintained in this package. When schema fields change, update both `flutter_gemma_options.dart` and `flutter_gemma_options.g.dart` by hand unless the maintainer explicitly asks to regenerate. Do not treat `build_runner` as the default drift fix.

### Testing pattern

All tests use `FakeRuntime` + `FakeInferenceModel` + `FakeInferenceChat` from `test/src/fake_runtime.dart`. The fakes must stay in sync with flutter_gemma's `InferenceModel`/`InferenceChat`/`EmbeddingModel` method signatures when bumping the dependency.

## Lint rules

Uses `flutter_lints` with `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`, `prefer_single_quotes` enabled. The `example/test/widget_test.dart` has a pre-existing error (`MyApp` not found) - ignore it.
