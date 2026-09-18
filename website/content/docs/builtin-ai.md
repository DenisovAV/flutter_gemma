---
title: Built-in AI
description: Run the device's own OS/browser AI as an engine — Gemini Nano (Android + Chrome), Phi-4-mini (Edge), Apple Foundation Models (iOS/macOS) and Windows AI Foundry — with no model to download, plus the availability-probe → open-model fallback pattern.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma's engines are **pluggable**: you register them in
`FlutterGemma.initialize(...)`, and the registry picks one per model by its
declared `ModelFileType`. One of those engines is `flutter_gemma_builtin_ai` —
it runs the model the **operating system (or browser) already ships**, so there
is **nothing to download**: installation only records which built-in model you
want, and the platform owns the weights.

Since **0.3.0** the package is a **thin adapter, not a Flutter plugin**: it ships
no Kotlin, Swift or C++ of its own and gets every OS backend from
[`flutter_local_ai`](https://pub.dev/packages/flutter_local_ai), a standalone
package that never depends on flutter_gemma. The `BuiltInAi*` API is unchanged —
same names, same signatures, same import — so existing code needs no migration.
See [What 0.3.0 changes for your build](#what-030-changes-for-your-build).

## Runtimes & devices

| Platform | Built-in model | Runtime | Minimum devices |
|----------|----------------|---------|-----------------|
| Android | **Gemini Nano** | ML Kit GenAI / AICore | Pixel 9+, Galaxy S25+ (`minSdk 26`, Kotlin 2.3.21) |
| iOS / macOS | **Apple Foundation Models** (Apple Intelligence) | FoundationModels framework | iOS 26+ / macOS 26+ on iPhone 15 Pro+, Apple Silicon Macs — Apple Intelligence enabled |
| Windows | **Phi Silica** | Windows AI Foundry (Windows App SDK 2.0+) | Copilot+ class hardware **and** an app that supplies the App SDK projections — see [Windows setup](#windows-setup) |
| Web | **Gemini Nano** in Chrome, **Phi-4-mini** in Edge | **Prompt API** (`self.LanguageModel`) | Desktop Chrome; Microsoft Edge with a flag (see [Web setup](#web-setup)) |

> **Note:** in Chrome the Prompt API *is* Gemini Nano — the browser runs the same
> on-device model, exposed through a JS API. Edge implements the same API with
> Microsoft's own model, Phi-4-mini: the same calls, a different model.
> **Windows reaches Phi Silica only in a build that opted into the Windows AI
> SDK** (see [Windows setup](#windows-setup)), and **Linux has no OS built-in
> model** at all — in both cases `availability()` returns an `unavailable*`
> status and you fall back to a downloaded model (see [the fallback
> pattern](#the-fallback-pattern)).

Availability is a runtime property of the device/OS/browser — never assume it at
build time; always probe with `BuiltInAi.availability()` /
`BuiltInAi.ensureReady()` before creating the model.

## Setup

Add the package and register `BuiltInAiEngine()` at startup, alongside any other
engines your app uses:

```
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

> **Android:** the underlying `flutter_local_ai` plugin declares `minSdk 26` (the
> ML Kit GenAI / AICore floor). Raise your app's
> `android/app/build.gradle(.kts)` `minSdk` to 26 or the manifest merger fails.
> The ML Kit Prompt API `beta4` artifact carries Kotlin 2.3 metadata, so the app
> also needs **Kotlin 2.3.21** and the current `compilerOptions` DSL.

> **macOS:** the deployment floor is **12.0**. Below that, CocoaPods and SPM fail
> resolution with a message naming the `flutter_local_ai` pod rather than this
> package.

## What 0.3.0 changes for your build

Nothing in your Dart code — but three build-level things move:

- **`pub get` regenerates the plugin registrants and the `Podfile.lock`.**
  `flutter_gemma_builtin_ai` leaves them, `flutter_local_ai` enters. CI that runs
  a frozen `pod install --deployment` fails until the lockfile is re-committed.
- **The macOS floor rises from 10.15 to 12.0**, and this package no longer pins
  an iOS floor of its own (`flutter_local_ai` builds from iOS 13.0). Core
  `flutter_gemma` still requires iOS 15.0, so an app's iOS floor is unchanged.
- **`package:flutter_gemma_builtin_ai/pigeon.g.dart` is gone** with the channel
  it wrapped. It was generated plumbing; the documented API never referenced it.

In exchange, **Windows joins the supported set** and `BuiltInAiModels` gains the
specs for it.

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

`BuiltInAiModels` carries `geminiNano` (Android), `appleFoundationModels`
(iOS/macOS), `windowsAiFoundry` (Windows) and `chromePromptApi` (Web) — plus
`all`, and `forCurrentPlatform`, which is **null on Linux and Fuchsia**, where
there is no built-in model to install:

```dart
final spec = BuiltInAiModels.forCurrentPlatform;
if (spec == null) {
  // No OS model on this platform — install a downloaded one instead.
}
```

Each is a plain `InferenceModelSpec` whose bundled source is an **identity token,
not a file**: the engine is chosen by `fileType == ModelFileType.builtIn` alone,
never by the name.

## Probe availability (and download, if needed)

`BuiltInAi.availability()` reports whether the OS model is ready.
`BuiltInAi.ensureReady()` makes sure the feature is on — and drives the on-device
download the first time it is used (Android, Windows and Web), reporting
progress. That can be a sizeable system download, so get the user's consent
first:

```dart
final status = await BuiltInAi.availability();
// available · downloadable · downloading · unavailable* (device/OS/disabled/other)

await BuiltInAi.ensureReady(
  onProgress: (percent) => debugPrint('Preparing built-in AI: $percent%'),
);
// Throws BuiltInAiUnavailableException for any unavailable* status.
```

**On web, call `ensureReady()` from a user gesture** — straight from a button's
tap handler, with no other `await` in front of it. While the model still has to
be downloaded, the browser refuses to start the session that downloads it unless
the user has interacted with the page (`NotAllowedError: Requires a user gesture
when availability is "downloading" or "downloadable"`). Chrome and Edge both
enforce this.

`availability()` never throws and never hangs — a probe that doesn't return
within `BuiltInAi.debugProbeTimeout` resolves to `unavailableOther`, which is
also what a platform with no built-in model at all (Linux) reports.

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
final spec = BuiltInAiModels.forCurrentPlatform;   // null on Linux / Fuchsia
final builtInReady =
    await BuiltInAi.availability() == BuiltInAiAvailability.available;

if (spec != null && builtInReady) {
  // Built-in: nothing to download.
  await FlutterGemma.installModel(
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  ).fromBundled(spec.name).install();
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

| Feature | Android (Gemini Nano) | iOS / macOS (Apple FM) | Windows (AI Foundry) | Web (Chrome Prompt API) |
|---------|------------------------|-------------------------|----------------------|--------------------------|
| Streaming | ✅ incremental | ✅ incremental | ⚠️ one final chunk | ✅ incremental |
| Function calling | ✅ prompt-based | ✅ prompt-based | ✅ prompt-based | ✅ prompt-based |
| Vision (image input) | ✅ | ✅ OS 27 + OS 27 SDK (text-only on OS 26) | ❌ | ❌ |
| Audio · Thinking · LoRA | ❌ | ❌ | ❌ | ❌ |
| `sizeInTokens` | ✅ native count | ✅ on OS 26.4+, built with Xcode 26.4+ (estimate otherwise) | ❌ estimate | ✅ `measureContextUsage` |
| `maxOutputTokens` | ✅ | ✅ | ❌ ignored | ❌ ignored |

- **Function calling is prompt-based** — tool definitions are woven into the
  prompt by core `InferenceChat`; native tool declarations are deliberately not
  handed to the OS runner as well, which would run two competing tool loops for
  one turn. Gemini Nano handles single-turn calls; multi-turn agent chaining is
  not supported on Web (see [Agent Skills](/docs/agent)).
- **`sizeInTokens` on Apple needs two things at once.**
  `SystemLanguageModel.tokenCount` is `@available(iOS 26.4, macOS 26.4)`, so the
  declaration is missing from earlier SDKs entirely — a build on Xcode 26.1
  cannot reference it, and a build on 26.4+ still falls back when running on an
  older OS. Where no tokenizer is reachable — that case, and Windows, which
  exposes none at all — the count is a `text.length / 4` estimate. On Web it
  needs an **open session** and uses `measureContextUsage`, falling back to the
  legacy `measureInputUsage` on older Chrome builds.
- **Unsupported vision is refused up front.** Creating a model with
  `supportImage: true` on a backend that has none (Windows, Web, Apple below
  OS 27) throws instead of silently dropping images mid-conversation.

- **Web is text-only in this release** (image/audio dropped with a one-time log).
- **Edge:** measured on Edge 151 (macOS) with Phi-4-mini — streaming, stopping
  and `measureContextUsage` work through the same calls, and the context window
  is 9216 tokens. Function calling on Phi-4-mini has not been tested. The web
  arm gates on `'LanguageModel' in self`, not on a browser name, so it reaches
  Edge's model the same way after the move to `flutter_local_ai`.

### Reaching what flutter_gemma's interface has no slot for

Native tool calling (Apple, OS 26+) and schema-constrained JSON output are
`flutter_local_ai` features with no equivalent in flutter_gemma's
`InferenceModelSession`. They remain available through that package's own API —
`LocalAi`, `LocalAiModel.create()`, `LocalAiSession` — which you can use
alongside this engine, since it is the same package driving the same native host.
Gate on `LocalAi.capabilities()` rather than on `Platform.isX`: the same binary
answers differently across OS versions.

## Windows setup

Windows is opt-in and the work happens in the **host app**, not in the package:
deploy/bootstrap Windows App SDK 2.0+, supply its C++/WinRT projections, and
declare the applicable package capabilities. Configure this **before** Flutter
adds the plugin:

```cmake
set(FLUTTER_LOCAL_AI_WINDOWS_AI ON CACHE BOOL "" FORCE)
set(FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR "C:/path/to/generated" CACHE PATH "" FORCE)
```

The default build reports `unavailableDeviceUnsupported` rather than claiming
usable inference. See [Microsoft's setup
guide](https://learn.microsoft.com/en-us/windows/ai/apis/get-started) for current
hardware, OS, manifest and SDK requirements. This path still needs Windows device
validation.

## Web setup

There is **no CDN `<script>` tag** — the Chrome Prompt API is a browser global
(`self.LanguageModel`). What it needs is the feature *enabled*:

- **Production:** register your origin for the [Prompt API origin
  trial](https://developer.chrome.com/origintrials) and add the token to
  `web/index.html`:
  ```
  <meta http-equiv="origin-trial" content="YOUR_TOKEN_HERE">
  ```
- **Local dev:** enable `chrome://flags/#prompt-api-for-gemini-nano` and restart
  Chrome. Floor: desktop Chrome on Windows, macOS 13+, Linux or ChromeOS Plus;
  22 GB free disk; a GPU with more than 4 GB VRAM, or 16 GB RAM and 4 CPU cores.
- **Microsoft Edge:** open `edge://flags`, enable **Prompt API for on-device
  language model** and restart. The model is Phi-4-mini, not Gemini Nano, and
  needs Windows 10/11 or macOS 13.3+, 20 GB free disk and 5.5 GB VRAM; it
  downloads on first use (about 5 minutes on a fast connection). Verified on
  stable Edge 151 on macOS. Edge Dev 154–155 exposes the API but cannot run the
  model ([MSEdgeExplainers#1392](https://github.com/MicrosoftEdge/MSEdgeExplainers/issues/1392)).

`BuiltInAi.availability()` reports `unavailableDeviceUnsupported` on any
browser/version without the Prompt API — always probe before creating a model.
Chrome also fixes sampling when a session is created, so per-call overrides are
not honoured there.

See the [`flutter_gemma_builtin_ai` package](/docs/packages) for the full API.

**Writing this with a coding assistant?** `dart run skills@ get --all` installs [`flutter-gemma-builtin-ai`](/docs/package-skills), the skill that teaches it availability, the user gesture the web arm needs, and falling back to a downloaded model.
