# flutter_gemma_builtin_ai

Built-in OS AI engine for [flutter_gemma](https://pub.dev/packages/flutter_gemma): runs inference
against the **system-provided** on-device model instead of a bundled Gemma checkpoint — Gemini
Nano via ML Kit GenAI (AICore) on Android, and Apple Foundation Models on iOS/macOS. Opt-in
package: add it only if you want your app to use whatever model the OS already ships, with no
model file to download or bundle.

Because the OS owns the weights, there's nothing to fetch: installation just records which
built-in model you want to use, and `BuiltInAi.ensureReady()` makes sure the OS feature itself is
turned on (and downloaded, on Android, the first time it's used).

## Supported devices & OS floors

| Platform | Model | Minimum devices | Notes |
|----------|-------|------------------|-------|
| Android | Gemini Nano (ML Kit GenAI / AICore) | Pixel 9+, Galaxy S25+ | Best experience on Pixel 10. **Consumer apps require `minSdk 26`** (this package declares it; raise your app's `minSdk` to match). |
| iOS / macOS | Apple Foundation Models | iPhone 15 Pro+, Apple Silicon (M-series) Macs | Requires Apple Intelligence enabled in **Settings → Apple Intelligence & Siri**. |

Vision (image input) requires **OS 27+** on Apple platforms — on OS 26 Apple Foundation Models is
**text-only**; sending an image throws a platform error instead of being silently ignored. Android
Gemini Nano supports vision on every supported device.

Availability is a runtime property of the device/OS, not something this package can guarantee at
build time — always probe it with `BuiltInAi.availability()` or `BuiltInAi.ensureReady()` before
creating a model.

## Quick start

Register the engine at startup, alongside any other engines your app uses:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';

void main() {
  FlutterGemma.initialize(
    inferenceEngines: const [BuiltInAiEngine()],
  );
  runApp(MyApp());
}
```

Install a built-in model. Built-in models have no file to download, so installation just records
the identity — pass `fileType: ModelFileType.builtIn` and use `.fromBundled(...)` with one of the
ready-made specs' `name`:

```dart
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.builtIn,
).fromBundled(BuiltInAiModels.geminiNano.name).install();
```

Or reference the spec objects directly if you're building your own model list — each is a plain
`InferenceModelSpec`:

```dart
final spec = defaultTargetPlatform == TargetPlatform.android
    ? BuiltInAiModels.geminiNano
    : BuiltInAiModels.appleFoundationModels;
```

Before creating the model, make sure the OS feature is actually ready — this also drives the
Android on-device download the first time the feature is used:

```dart
await BuiltInAi.ensureReady(
  onProgress: (percent) => print('Preparing built-in AI: $percent%'),
);
```

Then load and use the model exactly like any other flutter_gemma engine:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
final session = await model.createSession();
await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
final response = await session.getResponse();
```

## Feature parity vs. bundled Gemma engines

| Feature | Android (Gemini Nano) | iOS / macOS (Apple FM) |
|---------|------------------------|-------------------------|
| Streaming responses | ✅ | ✅ |
| Vision (image input) | ✅ | ✅ on OS 27+ only (text-only on OS 26) |
| Audio input | ❌ | ❌ |
| Function calling | ✅ (prompt-based) | ✅ (prompt-based) |
| Thinking mode | ❌ | ❌ |
| `sizeInTokens` | ✅ native token count | ✅ native token count |
| LoRA weights | ❌ | ❌ |

"Prompt-based" function calling means tool definitions are woven into the prompt rather than using
a native structured tool-calling API — the OS models don't expose one.

## Troubleshooting

`BuiltInAi.availability()` / `BuiltInAi.ensureReady()` report a `BuiltInAiAvailability` status
(surfaced via `BuiltInAiUnavailableException.status` when `ensureReady()` fails):

| Status | Meaning | User-facing remedy |
|--------|---------|---------------------|
| `available` | Ready to use now. | — |
| `downloadable` | OS feature exists but isn't downloaded yet. | Call `BuiltInAi.ensureReady()` — it triggers the download and reports progress via `onProgress`. |
| `downloading` | A download is already in progress. | Call `BuiltInAi.ensureReady()` and wait; it polls until ready or the `timeout` elapses. |
| `unavailableDeviceUnsupported` | This device doesn't have AICore (Android) or Apple Intelligence hardware (Apple). | Fall back to a bundled model — the device can't run the built-in one. |
| `unavailableOsTooOld` | The OS version is below what the built-in model requires. | Prompt the user to update the OS, or fall back to a bundled model. |
| `unavailableDisabled` | The feature exists but is turned off. | Ask the user to enable it: Apple Intelligence in **Settings → Apple Intelligence & Siri** (iOS/macOS), or the equivalent AICore/Gemini Nano toggle on Android. |
| `unavailableOther` | Unclassified failure. | Fall back to a bundled model; check device logs for detail. |

`ensureReady()` throws `BuiltInAiUnavailableException` immediately for every `unavailable*` status
(no download is attempted); it only drives a download from `downloadable`/`downloading`.
