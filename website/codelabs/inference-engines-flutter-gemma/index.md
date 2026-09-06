author: Sasha Denisov
summary: Inference Engines in Flutter — From a Downloaded Model to Built-in AI
id: inference-engines-flutter-gemma
categories: flutter, ai, gemma, gemini-nano
environments: android, ios
status: Published

# Inference Engines in Flutter: From a Downloaded Model to Built-in AI

## Overview
Duration: 3

### What you'll build

The chat app from the *Getting Started* codelab, taught to run on **two
engines** and to choose between them by itself:

* **LiteRT-LM**, which opens a `.litertlm` file you download — the engine you
  already have
* the **OS built-in model** — Gemini Nano on Android, Apple Foundation Models
  on iOS — which has no file at all, because the operating system owns the
  weights

By the end, the app probes the device at startup, uses the built-in model when
the OS ships one, and falls back to the downloaded model when it doesn't. The
chat code does not change once in the whole codelab. That is the point.

### What you'll learn

* what an **engine** is in `flutter_gemma`, and why the core ships none
* how a model's `ModelFileType` is the entire "engine switch"
* that *installed* and *active* are different things, and how one idempotent
  call moves between them
* why built-in availability can only be asked at run time, and how to ask
* how to fail with a **typed** error so the app can choose a fallback instead
  of crashing

### What you'll need

* The finished app from
  [Getting Started with On-Device LLMs in Flutter](/codelabs/getting-started-flutter-gemma)
  — or just its `complete/` directory, which is this codelab's starter
* An Android device or emulator, or an iOS device. A device **with** a built-in
  model (Pixel 9+, Galaxy S25+, iPhone 15 Pro+ with Apple Intelligence on) lets
  you see both engines answer; a device without one still shows the whole
  fallback path, which is what most of your users will hit

### Get the code

```bash
git clone --depth 1 https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma/codelabs/inference-engines-flutter-gemma
ls
```

```text
step_01_starter/           the Getting Started app, unchanged
step_02_two_engines/       after Step 2
step_03_pick_at_startup/   after Step 3
complete/                  the finished app
```

## Step 1: What an engine is
Duration: 4

Open `step_01_starter` and run it. It is the Getting Started app: download a
`.litertlm` file, chat with it. Look at one line of `main.dart`:

```dart
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
);
```

`flutter_gemma` itself contains **no inference runtime**. It has the install
pipeline, the chat loop, and a registry. Runtimes — engines — come from
separate packages, and each one tells the registry which model files it can
open. `LiteRtLmEngine` opens `.litertlm`. That single list is the only place
the app says which runtimes exist.

When you later call `getActiveModel()`, the registry looks at the active
model's `ModelFileType`, finds an engine whose `canHandle` says yes, and hands
the model to it. Nothing else in your code participates in that choice.

So "switching engines" is not a code path. It is: register a second engine,
and activate a model whose file type routes to it.

## Step 2: Register a second engine
Duration: 12

### Add the package

```bash
flutter pub add flutter_gemma_builtin_ai
```

This engine talks to the model the operating system already has: Gemini Nano
through ML Kit GenAI on Android, Apple Foundation Models on iOS. There is no
file. The OS owns the weights, updates them, and decides whether a given
device gets them at all.

### One platform change

Gemini Nano's Android SDK requires API 26. The package declares that, and the
manifest merger refuses an app that sets less, so raise the app's floor in
`android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    // flutter_gemma_builtin_ai (ML Kit GenAI / AICore) declares minSdk 26;
    // the manifest merger rejects an app below it.
    minSdk = 26
```

iOS needs nothing: the package builds from iOS 15, and on anything older than
OS 26 every call is gated and simply reports the model as unavailable.

### Register it

```dart
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine(), const BuiltInAiEngine()],
  huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
);
```

Two engines, side by side. Neither knows about the other.

### Give the model a shape that fits both

In Getting Started, `ModelChoice` described a file. Now it describes a model
that may or may not *be* a file, so two fields change meaning and one is added:

```dart
class ModelChoice {
  /// What `FlutterGemma.isModelInstalled` is keyed by. For a downloaded model
  /// that is its file name; for a built-in one, the OS model's name.
  final String id;

  /// Which engine opens it. `.litertlm` → LiteRtLmEngine, `.builtIn` →
  /// BuiltInAiEngine. This field is the whole "engine switch".
  final ModelFileType fileType;

  /// Where the bytes are. `null` for a built-in model — there is no file.
  final String? url;

  bool get isBuiltIn => fileType == ModelFileType.builtIn;
}
```

And the built-in model itself, one per platform. It is a getter rather than a
constant only because the platform is decided at run time:

```dart
static ModelChoice get builtIn {
  final spec = defaultTargetPlatform == TargetPlatform.android
      ? BuiltInAiModels.geminiNano
      : BuiltInAiModels.appleFoundationModels;
  return ModelChoice(
    label: defaultTargetPlatform == TargetPlatform.android
        ? 'Gemini Nano'
        : 'Apple Foundation Models',
    id: spec.name,
    modelType: spec.modelType,
    fileType: ModelFileType.builtIn,
    sizeLabel: 'already on the device',
  );
}
```

### Installed is not active

Here is the idea the rest of the codelab rests on. Installing a model puts it
on the device. Activating a model makes it the one `getActiveModel()` loads.
The last model you installed is active — and `install()` is **idempotent**:
called on a model that is already there, it skips the download and just makes
it active.

So one function makes any model ready *and* current, whichever kind it is:

```dart
Future<void> activate(ModelChoice model, {void Function(int)? onProgress}) async {
  if (model.isBuiltIn) {
    // Throws BuiltInAiUnavailableException on a device/OS that has no
    // built-in model, so the failure is typed and the caller can react.
    await BuiltInAi.ensureReady(onProgress: onProgress);
    await FlutterGemma.installModel(
      modelType: model.modelType,
      fileType: model.fileType,
    ).fromBundled(model.id).install();
    return;
  }

  await FlutterGemma.installModel(
        modelType: model.modelType,
        fileType: model.fileType,
      )
      .fromNetwork(model.url!)
      .withProgress((percent) => onProgress?.call(percent))
      .install();
}
```

For the built-in model, `ensureReady()` asks the OS to make its model ready —
on Android the first call may download the feature, and `onProgress` reports
it. Then `install()` records the identity; there is no file to fetch, so
`fromBundled(model.id)` is just a name.

The gate from Getting Started grows by one line, because *installed* no longer
implies *active*:

```dart
Future<bool> _prepare() async {
  final installed = await FlutterGemma.isModelInstalled(widget.model.id);
  // Installed is not the same as active. `install()` is idempotent, so
  // re-running it on a model that is already here costs nothing and makes
  // it the one `getActiveModel` will load.
  if (installed) await activate(widget.model);
  return installed;
}
```

### Switch by hand

`step_02_two_engines` adds a menu to the chat's app bar: *Use Gemini Nano*,
*Use Gemma 3 1B*, *Use Qwen3 0.6B*. Picking one closes the current runtime and
hands the app a different `ModelChoice`; a new `ValueKey(choice.id)` on the
gate restarts it for that model.

```dart
Future<void> _switchTo(ModelChoice next) async {
  await _inference?.close();
  _inference = null;
  _chat = null;
  if (mounted) widget.onSwitch(next);
}
```

Close the runtime *before* activating another model. Each engine holds native
memory of its own, and the built-in one holds an OS session.

Run it. On a device with a built-in model, switch to it and ask the same
question you asked Gemma — a different engine answers, and the chat page is
byte-for-byte the code you had. On a device *without* one, the switch fails —
and look at how:

```text
BuiltInAiUnavailableException(unavailableDeviceUnsupported): Built-in AI is not available
```

A typed exception with a status, not a platform crash. `step_02`'s error card
reads the status and says, for a disabled feature, exactly which Settings
toggle turns it on. That typed failure is what makes the next step possible.

## Step 3: Let the app choose
Duration: 8

Which engine a device has is not knowable at build time. A Pixel 9 has Gemini
Nano; a Pixel 7 does not; an iPhone 15 Pro has Apple Foundation Models only
once the user turns Apple Intelligence on. So the app asks, every launch:

```dart
Future<void> _pickAtStartup() async {
  final status = await BuiltInAi.availability();
  final choice = switch (status) {
    BuiltInAiAvailability.available ||
    BuiltInAiAvailability.downloadable ||
    BuiltInAiAvailability.downloading => Models.builtIn,
    _ => Models.gemma3,
  };
  if (mounted) setState(() => _choice = choice);
}
```

Three of the seven statuses mean "the OS can give you a model" — now, after a
download, or once a running download finishes. The other four are the
`unavailable*` family, and for all of them the answer is the same: use the
downloaded model.

The probe is bounded. On a device whose AI stack never answers (a
freshly-provisioned Android with no AICore metadata yet), `availability()`
gives up after 20 seconds and reports `unavailableOther` rather than hanging
your startup. `step_03_pick_at_startup` shows a *Checking for a built-in
model…* screen for that window.

The manual switch from Step 2 stays in the menu, so you can override the
app's choice and compare.

## Step 4: Say why
Duration: 4

A silent decision is a support ticket waiting to happen: "why is my app
downloading half a gigabyte when the phone has Gemini?" `complete` keeps the
probe's verdict and shows it once, in a banner above the chat:

```dart
final (choice, reason) = switch (status) {
  BuiltInAiAvailability.available => (
    Models.builtIn,
    'Using the model the OS ships — nothing was downloaded.',
  ),
  BuiltInAiAvailability.downloadable ||
  BuiltInAiAvailability.downloading => (
    Models.builtIn,
    'The OS has a built-in model; it will fetch the feature once.',
  ),
  BuiltInAiAvailability.unavailableDisabled => (
    Models.gemma3,
    'Built-in AI is turned off on this device — using a downloaded model.',
  ),
  _ => (
    Models.gemma3,
    'No built-in model here ($status) — using a downloaded model.',
  ),
};
```

`unavailableDisabled` gets its own line because it is the one case the *user*
can fix — the hardware is fine, the feature is switched off.

That is the finished app. Run `complete` on whatever you have:

* a device with a built-in model → the banner says so, nothing downloads, the
  OS model answers
* an emulator or an older phone → the banner names the status, Gemma downloads
  once, LiteRT-LM answers

Same chat page either way.

## What's next
Duration: 2

You now have an app that adapts to the device it lands on. The registry idea
extends further than these two engines:

* **MediaPipe** (`flutter_gemma_mediapipe`) opens `.task` files and is the
  only engine that runs on the web
* **ONNX Runtime** (`flutter_gemma_onnx`) opens ONNX model directories on
  desktop and mobile
* the built-in engine also has a **web** arm — Gemini Nano through Chrome's
  Prompt API

Each registers the same way and answers through the same chat code.

### Reference

* [flutter_gemma_builtin_ai on pub.dev](https://pub.dev/packages/flutter_gemma_builtin_ai)
  — supported devices, OS floors, and what each availability status means
* [Engines documentation](https://fluttergemma.dev/docs/builtin-ai)
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
