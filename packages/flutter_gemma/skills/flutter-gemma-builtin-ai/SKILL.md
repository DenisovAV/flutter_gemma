---
name: flutter-gemma-builtin-ai
description: Use when running the device's own model with flutter_gemma_builtin_ai — Gemini Nano on Android or in desktop Chrome, Phi-4-mini in Microsoft Edge, Apple Foundation Models on iPhone, iPad and Mac — with nothing to download or bundle, or when falling back to a downloaded model where it is missing. Also use when BuiltInAiUnavailableException or a TimeoutException is thrown, availability reports "downloadable", web throws NotAllowedError about a user gesture, the Android build fails the manifest merge on minSdk, or the model is missing in Chrome. For models the app downloads itself, use flutter-gemma-inference.
---

# The built-in OS model

## Rules

1. The OS owns the weights, but the model is still installed — as an identity: `fileType: ModelFileType.builtIn` with `.fromBundled(...)`. The app downloads nothing.
2. Call `BuiltInAi.ensureReady()` before `getActiveModel()`, from a user action: the first call downloads the model and can take minutes, and on web the browser will not start that download without a user gesture ("NotAllowedError: Requires a user gesture"). Call it straight from the tap handler, with no other `await` before it. It throws `TimeoutException` after `timeout` — 10 minutes by default.
3. Catch `BuiltInAiUnavailableException` and fall back to a downloadable model.
4. Android apps need `minSdk 26`, or the manifest merge fails.
5. There is no Windows or Linux support.

## Setup with a fallback

```sh
flutter pub add flutter_gemma flutter_gemma_builtin_ai flutter_gemma_litertlm
```

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(
  inferenceEngines: [BuiltInAiEngine(), LiteRtLmEngine()],
);

final spec = kIsWeb || defaultTargetPlatform == TargetPlatform.android
    ? BuiltInAiModels.geminiNano
    : defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? BuiltInAiModels.appleFoundationModels
        : null; // Windows and Linux have no built-in model

Future<InferenceModel> downloadGemma() async {
  await FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  ).fromNetwork(
    // 2.6 GB — ask first. On web: gemma-4-E2B-it-web.litertlm
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  ).install();
  return FlutterGemma.getActiveModel(maxTokens: 1024);
}

InferenceModel model;
if (spec == null) {
  model = await downloadGemma();
} else {
  try {
    await FlutterGemma.installModel(
      modelType: ModelType.general,
      fileType: ModelFileType.builtIn,
    ).fromBundled(spec.name).install();
    await BuiltInAi.ensureReady(onProgress: (int percent) => print('$percent%'));
    model = await FlutterGemma.getActiveModel(maxTokens: 4096);
  } on BuiltInAiUnavailableException {
    model = await downloadGemma();
  } on TimeoutException {
    model = await downloadGemma();
  }
}
```

The latest install is the one `getActiveModel` loads, so the fallback replaces the built-in model. Sessions and chats then work as in the flutter-gemma-inference skill.

## Checking before offering the feature

```dart
final availability = await BuiltInAi.availability();
final usable = availability == BuiltInAiAvailability.available ||
    availability == BuiltInAiAvailability.downloadable ||
    availability == BuiltInAiAvailability.downloading;
```

`downloadable` and `downloading` mean "not yet" — `ensureReady` finishes the job. The `unavailable*` states describe the device now, not forever:

| State | Meaning |
| --- | --- |
| `unavailableDeviceUnsupported` | the hardware cannot run it |
| `unavailableOsTooOld` | an OS update would enable it |
| `unavailableDisabled` | the user can turn it on in system settings (Apple Intelligence on Apple devices) |
| `unavailableOther` | anything else, including a probe that timed out after 20 seconds — worth asking again later |

## Platforms

| Platform | Model | Needs |
| --- | --- | --- |
| Android | Gemini Nano (AICore) | Pixel 9+, Galaxy S25+; `minSdk 26` |
| iOS, macOS | Apple Foundation Models | iPhone 15 Pro+ or an Apple Silicon Mac, Apple Intelligence turned on |
| Web | Gemini Nano (Chrome Prompt API) | desktop Chrome — not mobile browsers, Firefox or Safari |
| Web | Phi-4-mini (Edge Prompt API) | Microsoft Edge with the Prompt API flag on; Edge Dev 154–155 exposes the API but cannot run the model |

Images work on Android. On Apple platforms they need OS 27 — on OS 26 an image throws. The web model is text-only.

## Web

There is no script to add: the Prompt API is part of the browser. It has to be enabled.

- Production — register the origin for the Prompt API origin trial and add the token to `web/index.html`:

```html
<meta http-equiv="origin-trial" content="YOUR_TOKEN_HERE">
```

- Local development — enable `chrome://flags/#prompt-api-for-gemini-nano` and restart Chrome.
- Microsoft Edge — enable `edge://flags` → "Prompt API for on-device language model" and restart. Both browsers use `BuiltInAiModels.geminiNano`: the spec names the API, and the browser picks the model.

## Trade-offs

No choice of weights, no LoRA, and capabilities that vary by OS version. The right pick when zero download and zero disk matter more than choosing the model.
