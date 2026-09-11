---
name: flutter-gemma-builtin-ai
description: Use when running the device's own model with flutter_gemma_builtin_ai — Gemini Nano on Android or in desktop Chrome, Apple Foundation Models on iPhone, iPad and Mac — with nothing to download or bundle. Also use when BuiltInAiUnavailableException is thrown, availability reports "downloadable", the Android build fails the manifest merge on minSdk, or the model is missing in Chrome. For models you download yourself, use flutter-gemma-inference.
---

# The built-in OS model

## Rules

1. The OS owns the weights, but the model is still installed — as an identity: `fileType: ModelFileType.builtIn` with `.fromBundled(...)`. Nothing is downloaded by the app.
2. Call `BuiltInAi.ensureReady()` before `getActiveModel()`, from a user action: on Android the first call downloads the model and can take minutes.
3. Catch `BuiltInAiUnavailableException` and fall back to a downloadable model.
4. Android apps need `minSdk 26`, or the manifest merge fails.
5. There is no Windows or Linux support.

## Setup

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';

await FlutterGemma.initialize(inferenceEngines: [BuiltInAiEngine()]);

final spec = kIsWeb || defaultTargetPlatform == TargetPlatform.android
    ? BuiltInAiModels.geminiNano
    : BuiltInAiModels.appleFoundationModels;

await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.builtIn,
).fromBundled(spec.name).install();

try {
  await BuiltInAi.ensureReady(onProgress: (percent) => print('$percent%'));
  final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
} on BuiltInAiUnavailableException catch (e) {
  print('No built-in model here: $e — fall back to a downloadable one');
}
```

## Checking before you offer the feature

```dart
final availability = await BuiltInAi.availability();
final usable = availability == BuiltInAiAvailability.available ||
    availability == BuiltInAiAvailability.downloadable ||
    availability == BuiltInAiAvailability.downloading;
```

`downloadable` and `downloading` mean "not yet", not "no" — `ensureReady` finishes the job. The `unavailable*` states are final for this device: `unavailableDeviceUnsupported`, `unavailableOsTooOld`, `unavailableDisabled`, `unavailableOther`.

## Platforms

| Platform | Model | Needs |
| --- | --- | --- |
| Android | Gemini Nano (AICore) | Pixel 9+, Galaxy S25+; `minSdk 26` |
| iOS, macOS | Apple Foundation Models | iPhone 15 Pro+ or an Apple Silicon Mac, Apple Intelligence turned on |
| Web | Gemini Nano (Chrome Prompt API) | desktop Chrome or Edge only — not mobile browsers, Firefox or Safari |

Images work on Android. On Apple platforms they need OS 27 — on OS 26 an image throws. The web model is text-only.

## Web

There is no script to add: the Prompt API is part of the browser. It has to be enabled.

- Production — register the origin for the Prompt API origin trial and add the token to `web/index.html`:

```html
<meta http-equiv="origin-trial" content="YOUR_TOKEN_HERE">
```

- Local development — enable `chrome://flags/#prompt-api-for-gemini-nano` and restart Chrome.

## Trade-offs

No choice of weights, no LoRA, and capabilities that vary by OS version. Use it when zero download and zero disk matter more than picking the model.
