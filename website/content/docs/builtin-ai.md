---
title: Built-in AI
description: Run the device's own OS/browser AI as an engine — Gemini Nano (Android + Web) and Apple Foundation Models (iOS/macOS) — with no model to download, plus the availability-probe → open-model fallback pattern.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma's engines are **pluggable**: you register them in
`FlutterGemma.initialize(...)`, and the registry picks one per model by its
declared `ModelFileType`. One of those engines is `flutter_gemma_builtin_ai` —
it runs the model the **operating system (or browser) already ships**, so there
is **nothing to download**: installation only records which built-in model you
want, and the platform owns the weights.

## Runtimes & devices

| Platform | Built-in model | Runtime | Minimum devices |
|----------|----------------|---------|-----------------|
| Android | **Gemini Nano** | ML Kit GenAI / AICore | Pixel 9+, Galaxy S25+ (`minSdk 26`) |
| iOS / macOS | **Apple Foundation Models** (Apple Intelligence) | FoundationModels framework | iOS 26+ / macOS 26+ on iPhone 15 Pro+, Apple Silicon Macs — Apple Intelligence enabled |
| Web | **Gemini Nano** | Chrome **Prompt API** (`self.LanguageModel`) | Desktop Chrome / Chromium-Edge only |

> **Note:** the Chrome Prompt API *is* Gemini Nano — the browser runs the same
> on-device model, exposed through a JS API. **Windows and Linux have no OS
> built-in model** (no ML Kit, no Apple Foundation Models, no browser Prompt API
> in a Flutter desktop app) — there `availability()` reports
> `unavailableDeviceUnsupported`, and you fall back to a downloaded model
> (see [the fallback pattern](#the-fallback-pattern)).

Availability is a runtime property of the device/OS/browser — never assume it at
build time; always probe with `BuiltInAi.availability()` /
`BuiltInAi.ensureReady()` before creating the model.

## Setup

Add the package and register `BuiltInAiEngine()` at startup, alongside any other
engines your app uses:

```yaml
dependencies:
  flutter_gemma: latest_version
  flutter_gemma_builtin_ai: latest_version   # OS/browser built-in AI
```

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';

await FlutterGemma.initialize(
  inferenceEngines: const [BuiltInAiEngine()],
);
```

> **Android:** `flutter_gemma_builtin_ai` declares `minSdk 26` (the ML Kit GenAI
> / AICore floor). Raise your app's `android/app/build.gradle(.kts)` `minSdk` to
> 26 or the manifest merger fails.

## Install a built-in model

Built-in models have no file to fetch, so installation just records the
identity — pass `fileType: ModelFileType.builtIn` and use one of the ready-made
specs from `BuiltInAiModels`:

```dart
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.builtIn,
).fromBundled(BuiltInAiModels.geminiNano.name).install();
```

`BuiltInAiModels.geminiNano` (Android + Web) and
`BuiltInAiModels.appleFoundationModels` (iOS/macOS) are plain
`InferenceModelSpec`s you can also reference directly when building your own
model list.

## Probe availability (and download, if needed)

`BuiltInAi.availability()` reports whether the OS model is ready.
`BuiltInAi.ensureReady()` makes sure the feature is on — and drives the on-device
download the first time it is used (Android), reporting progress:

```dart
final status = await BuiltInAi.availability();
// available · downloadable · downloading · unavailable* (device/OS/disabled/other)

await BuiltInAi.ensureReady(
  onProgress: (percent) => debugPrint('Preparing built-in AI: $percent%'),
);
// Throws BuiltInAiUnavailableException for any unavailable* status.
```

## The fallback pattern

The point of a pluggable engine: **use the built-in model when the device
supports it (zero download, private, fast); otherwise fall back to a downloaded
open model** — through the same API, without rewriting the app.

The fallback below registers a second engine, so add its package too — e.g.
`flutter_gemma_litertlm` (for `LiteRtLmEngine`), or `flutter_gemma_mediapipe` /
`flutter_gemma_onnx`:

```dart
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(
  inferenceEngines: const [
    BuiltInAiEngine(),   // flutter_gemma_builtin_ai
    LiteRtLmEngine(),    // flutter_gemma_litertlm — the fallback
  ],
);

// Does this device have a usable built-in model?
final builtInReady =
    await BuiltInAi.availability() == BuiltInAiAvailability.available;

if (builtInReady) {
  // Built-in: nothing to download.
  await FlutterGemma.installModel(
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  ).fromBundled(BuiltInAiModels.geminiNano.name).install();
} else {
  // Fallback: install an open model (Gemma / Qwen / Phi …).
  await FlutterGemma.installModel(
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
  ).fromNetwork('https://…/gemma3-1b-it.litertlm').install();
}

// From here the code is identical regardless of which engine backs the model:
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
final session = await model.createSession();
await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
final response = await session.getResponse();
```

## Capabilities & limits

| Feature | Android (Gemini Nano) | iOS / macOS (Apple FM) | Web (Chrome Prompt API) |
|---------|------------------------|-------------------------|--------------------------|
| Streaming | ✅ | ✅ | ✅ |
| Function calling | ✅ prompt-based | ✅ prompt-based | ✅ prompt-based |
| Vision (image input) | ✅ | ✅ on OS 27+ (text-only on OS 26) | ❌ (v1, tracked) |
| Audio · Thinking · LoRA | ❌ | ❌ | ❌ |
| `sizeInTokens` | ✅ native count | ✅ native count | ✅ `measureContextUsage` |

- **Function calling is prompt-based** — tool definitions are woven into the
  prompt by core `InferenceChat`; the OS models don't expose a usable native
  tool-calling API. On Web, Chrome's native Prompt-API tool use is experimental
  and not production-usable (Chrome 151), so it too goes through the prompt-based
  path. Gemini Nano handles single-turn calls; multi-turn agent chaining is not
  supported on Web (see [Agent Skills](/docs/agent)).
- **Web is text-only in this release** (image/audio dropped with a one-time log).

## Web setup

There is **no CDN `<script>` tag** — the Chrome Prompt API is a browser global
(`self.LanguageModel`). What it needs is the feature *enabled*:

- **Production:** register your origin for the [Prompt API origin
  trial](https://developer.chrome.com/origintrials) and add the token to
  `web/index.html`:
  ```html
  <meta http-equiv="origin-trial" content="YOUR_TOKEN_HERE">
  ```
- **Local dev:** enable `chrome://flags/#prompt-api-for-gemini-nano` and restart
  Chrome. Floor: desktop Chrome/Edge, ~22 GB free disk + a GPU with >4 GB VRAM
  (or a 16 GB-RAM CPU-only path).

`BuiltInAi.availability()` reports `unavailableDeviceUnsupported` on any
browser/version without the Prompt API — always probe before creating a model.

See the [`flutter_gemma_builtin_ai` package](/docs/packages) for the full API.
