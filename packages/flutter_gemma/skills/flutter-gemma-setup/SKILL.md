---
name: flutter-gemma-setup
description: Use when adding flutter_gemma to a Flutter app, calling FlutterGemma.initialize, or installing a model — core registers no inference engine by default and routes by the DECLARED file type, so both are easy to get silently wrong.
---

# Setting up flutter_gemma

Two decisions here fail quietly rather than loudly. Get them right first.

## 1. Core ships no engine — you must register one

`flutter_gemma` is the contracts, the registry and the platform shells. It
contains no inference runtime. Adding only `flutter_gemma` to `pubspec.yaml`
compiles fine and throws on the first `getActiveModel()`.

Pick the engine package for the model format you actually have:

| Package | Handles | Platforms |
| --- | --- | --- |
| `flutter_gemma_litertlm` | `.litertlm` | Android, iOS, macOS, Windows, Linux, web |
| `flutter_gemma_mediapipe` | `.task`, `.bin` | Android, iOS, web |
| `flutter_gemma_builtin_ai` | the OS model (Gemini Nano, Apple Foundation Models) | Android 26+, iOS, macOS |
| `flutter_gemma_onnx` | ONNX / ORT-GenAI | macOS arm64, Linux x64, Windows x64, Android arm64, iOS arm64 |

Register the providers before anything else runs:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
);
```

Every capability is opt-in the same way and defaults to an empty list:

```dart
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],        // text / vision / audio
  embeddingBackends: [LiteRtEmbeddingBackend()], // flutter_gemma_embeddings
  sttBackends: [LiteRtSttBackend()],           // flutter_gemma_speech
  ttsBackends: [LiteRtTtsBackend()],           // flutter_gemma_speech
  huggingFaceToken: 'hf_…',                    // only for gated repos
);
```

If a list is empty, the corresponding first call throws a `StateError` naming
the package to add. That message is the intended diagnostic — read it rather
than guessing.

## 2. The engine is chosen by the DECLARED file type, never the filename

`installModel` defaults to `ModelFileType.task`. A `.litertlm` file installed
without declaring its type is routed to MediaPipe, which cannot read it.

```dart
// WRONG — the name says .litertlm, the declaration says .task,
// and the declaration is what routes it.
await FlutterGemma.installModel(modelType: ModelType.gemma4)
    .fromNetwork('https://example.com/model.litertlm')
    .install();

// RIGHT
await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
).fromNetwork('https://example.com/model.litertlm').install();
```

`modelType` is a separate axis and drives the chat template and capabilities
(`ModelType.gemma4`, `.gemma3`, `.qwen3`, `.deepSeek`, `.general`, …). Getting
it wrong does not fail loudly either — it produces a model that generates, but
with the wrong prompt format.

## Installing from Hugging Face

When the repo publishes a deployment manifest, one call resolves the variant,
the revision and the runtime defaults:

```dart
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  huggingFaceResolvers: [LitertlmManifestResolver()],
);

final install = await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.litertlm,
).fromHuggingFace('litert-community/LFM2.5-230M').install();

// The manifest's own runtime defaults — pass them through rather than
// inventing values.
final model = await FlutterGemma.getActiveModel(defaults: install.runtime);
```

Without a registered resolver `fromHuggingFace` throws a clear error. `defaults`
carries what the model publisher tested; an explicit argument you pass alongside
it always wins.

## Other model sources

```dart
.fromNetwork(url, token: hfToken)   // download, resumable
.fromAsset('assets/model.litertlm') // bundled in the app
.fromFile(File(path))               // already on disk
```

## Platform notes that bite

- **Android + `.litertlm`** needs `minSdk 30`. The native library uses
  API-30-only Bionic symbols; on 29 it fails at `dlopen`.
- **`flutter_gemma_builtin_ai`** needs `minSdk 26`, or the manifest merger
  fails.
- **iOS** builds from 15.0, except with `flutter_gemma_mediapipe`, which
  requires 16.0.
- **Web** is GPU-only and needs the CDN script tags plus the runtime JS files
  copied into the app's `web/` directory. See the package README.
- **iOS Simulator** cannot run GPU inference — Metal there has a 256 MB
  single-allocation cap and model weights exceed it. Use CPU or a real device.

## Verifying setup

```dart
await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
).fromNetwork(url).install();

final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
final session = await model.createSession();
try {
  await session.addQueryChunk(
    const Message(text: 'Say hello.', isUser: true),
  );
  print(await session.getResponse());
} finally {
  await session.close();
}
await model.close();
```

If that runs, the engine is registered, the file type routed correctly and the
model loaded. See `flutter-gemma-inference` for what to do next, and why
`maxTokens: 1024` rather than something smaller.
