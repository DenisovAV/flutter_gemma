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
the OS ships one, and falls back to the downloaded model when it doesn't.

The code that talks to the model does not change once in the whole codelab.
Three functions — `_load`, `_send` and `dispose` in `chat_page.dart` — are
character-for-character the same in all four step directories and on both
engines; `diff` them and see. What does grow is the chrome around them: an app
bar menu in Step 2, an engine label beside it, a banner in Step 4. That is the
point.

### What you'll learn

* what an **engine** is in `flutter_gemma`, and why the core ships none
* how a model's `ModelFileType` is the entire "engine switch"
* that *installed* and *active* are different things — and that *installed* is
  not even a concept for a model the OS owns
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
complete/                  after Step 4 — the finished app
```

## Step 1: What an engine is
Duration: 5

### Before you run

The downloaded model in this codelab — the one every fallback path lands on —
is Gemma 3 1B, and its Hugging Face repository is behind a licence gate. Accept
the terms on the
[model page](https://huggingface.co/litert-community/Gemma3-1B-IT) once, create
a read token in your Hugging Face settings, and start every run with it:

```bash
flutter run --dart-define=HF_TOKEN=hf_your_token
```

[Getting Started](/codelabs/getting-started-flutter-gemma) covers that in its
Step 2. Without the token the download 401s — and since a device without a
built-in model takes the fallback path, that is most devices. If you would
rather not have a Hugging Face account, `Models.qwen3` in `model.dart` is
ungated: point the fallback at it instead and nothing else here changes.

### One list of engines

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
Duration: 18

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
    // …
    // flutter_gemma_builtin_ai (ML Kit GenAI / AICore) declares minSdk 26;
    // the manifest merger rejects an app below it.
    minSdk = 26
```

iOS needs nothing beyond what Getting Started already set up — the iOS 15.0
deployment target and the three memory entitlements. `flutter_gemma_builtin_ai`
declares an iOS 15.0 floor of its own, so a project still pinned at Flutter's
older 13.0 template default has to be raised for this package too; on anything
older than OS 26 every call is gated and simply reports the model as
unavailable.

### Register it

```dart
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine(), const BuiltInAiEngine()],
  huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
);
```

Two engines, side by side. Neither knows about the other.

### Rename these first

If you are editing your own `complete/` from Getting Started rather than
opening `step_02_two_engines`, five names change, and the compiler will find
them in four files:

| Rename | Why | Where it breaks |
|---|---|---|
| `ModelChoice.fileName` → `id` | a built-in model has no file name | `main.dart` gate, `chat_page.dart` `uninstallModel`, `test/widget_test.dart` |
| `ModelChoice.url` → `String?` | a built-in model has no URL | `download_page.dart` needs `.fromNetwork(model.url!)`, and so does the test |
| `ModelChoice.fileType` (new, required) | this is the engine switch | both `Models` constants |
| `DownloadPage.onInstalled` → `onReady` | "installed" is the wrong word for a model the OS owns | `main.dart` gate, the widget test |
| `ChatPage` gains a required `onSwitch` | the chat can now ask for a different model | `main.dart` gate |

`download_page.dart` also grows a top-level `activate()` function, below.

### Give the model a shape that fits both

In Getting Started, `ModelChoice` described a file. Now it describes a model
that may or may not *be* a file:

```dart
class ModelChoice {
  // …

  /// How this app names the model. For a downloaded model it is the file name,
  /// which is also what `FlutterGemma.isModelInstalled` is keyed by. For a
  /// built-in one it is the OS model's name — and nothing is keyed by it,
  /// because there is no file and no install record.
  final String id;

  // …

  /// Which engine opens it. `.litertlm` → LiteRtLmEngine, `.builtIn` →
  /// BuiltInAiEngine. This field is the whole "engine switch".
  final ModelFileType fileType;

  /// Where the bytes are. `null` for a built-in model — there is no file.
  final String? url;

  // …

  bool get isBuiltIn => fileType == ModelFileType.builtIn;
}
```

(`// …` is where the constructor and the `label` / `modelType` / `sizeLabel` /
`requiresToken` fields sit — the file has them; this excerpt does not.)

And the built-in model itself, one per platform. It is a getter rather than a
constant only because the platform is decided at run time:

```dart
static ModelChoice get builtIn {
  final (spec, label) = switch (defaultTargetPlatform) {
    TargetPlatform.android => (BuiltInAiModels.geminiNano, 'Gemini Nano'),
    TargetPlatform.iOS || TargetPlatform.macOS => (
      BuiltInAiModels.appleFoundationModels,
      'Apple Foundation Models',
    ),
    _ => throw UnsupportedError(
      'No built-in AI model on $defaultTargetPlatform',
    ),
  };
  return ModelChoice(
    label: label,
    id: spec.name,
    modelType: spec.modelType,
    fileType: ModelFileType.builtIn,
    sizeLabel: 'already on the device',
  );
}
```

Android and Apple are the platforms this codelab targets, and the ones
`flutter_gemma_builtin_ai` has a native arm for there, so anywhere else this
throws instead of quietly handing back a model that cannot exist. (The package
also has a **web** arm — Gemini Nano through Chrome's Prompt API — which is out
of scope here.) Failing loudly is the right contract for the getter; the cost
is that every caller has to be somewhere a throw can be caught. The chat page's
menu builds its list through `_alternatives`, which asks for `Models.builtIn`
inside a `try` and drops the entry on `UnsupportedError`. That getter runs from
`itemBuilder`, so the guard has to be *in* it: a throw during a build is a red
screen, not something a `catch` around the tap could reach. The startup probe
in Step 3 guards the same getter the same way.

### Installed is not active — and a built-in model is never installed

Here is the idea the rest of the codelab rests on, in two halves.

**For a downloaded model.** Installing puts it on the device. Activating makes
it the one `getActiveModel()` loads. The last model you installed is active —
and `install()` is **idempotent**: called on a model that is already there, it
skips the download and just makes it active.

**For a built-in model.** "Installed" is not a concept at all. Nothing is
written to disk and no install record exists, so `FlutterGemma.isModelInstalled`
answers *no* for it forever — before activation and after. Readiness is a
question for the OS, not for your storage.

One function still covers both, because *activating* means the same thing on
either side:

```dart
Future<void> activate(
  ModelChoice model, {
  void Function(int)? onProgress,
}) async {
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
on Android the first call may download the feature. Then `install()` records
the identity; there is no file to fetch, so `fromBundled(model.id)` is just a
name.

That OS download is the reason the setup screen's progress bar is
*indeterminate* for a built-in model and determinate for a file: Android
reports a running byte count with `bytesTotal: 0`, and Apple reports nothing at
all, so there is no percentage to draw. A determinate bar pinned at 0% for
minutes reads as a frozen app, which is worse than admitting you do not know.

The gate from Getting Started therefore grows a branch, not a line — it asks a
different *question* per kind of model:

```dart
Future<bool> _prepare() async {
  if (widget.model.isBuiltIn) {
    // "Installed" is not a concept for a built-in model. The OS owns the
    // weights, nothing lands on disk, and no install record is written — so
    // `isModelInstalled` answers no forever. Ask the OS instead.
    final status = await BuiltInAi.availability();
    if (status != BuiltInAiAvailability.available) return false;
    // Ready, but not yet current: `activate` records the identity that
    // `getActiveModel` will load.
    await activate(widget.model);
    return true;
  }

  final installed = await FlutterGemma.isModelInstalled(widget.model.id);
  // For a downloaded model, installed is still not the same as active.
  // `install()` is idempotent, so re-running it on a model that is already
  // here costs nothing and makes it the one `getActiveModel` will load.
  if (installed) await activate(widget.model);
  return installed;
}
```

Ask the wrong question and the app becomes unreachable rather than broken:
`isModelInstalled` on a built-in model is always false, so the gate would send
you to the setup screen, the setup screen would activate the model
successfully, and the gate would send you straight back. Forever, with no
error anywhere.

### Switch by hand

`step_02_two_engines` adds a menu to the chat's app bar listing the models you
are *not* running — so at most two *Use …* entries, and on iOS the built-in one
reads *Use Apple Foundation Models*. Below them sits *Forget this model*, which
deletes a downloaded one; it is hidden for the built-in model, because there is
no file to free and no record to remove (`uninstallModel` would throw).

Picking a model closes the current runtime and hands the app a different
`ModelChoice`; a new `ValueKey(choice.id)` on the gate restarts it for that
model.

```dart
Future<void> _switchTo(ModelChoice next) async {
  await _inference?.close();
  // Inside `setState`: dropping the chat has to repaint, or the screen keeps
  // showing an enabled composer over a runtime that is gone.
  if (mounted) {
    setState(() {
      _inference = null;
      _chat = null;
    });
    widget.onSwitch(next);
  }
}
```

Close the runtime *before* activating another model. Each engine holds native
memory of its own, and the built-in one holds an OS session. Both menu actions
run through one `_onAction` wrapper that catches whatever they throw, puts it
in the same `_loadError` a failed load uses, and nulls `_chat` alongside it —
closing a runtime and deleting a file are native calls, and a `close()` that
throws has already broken the model while leaving `_chat` non-null, so without
that the page would offer a working composer under *The model did not load.*

Run it. On a device with a built-in model, switch to it and ask the same
question you asked Gemma. A different engine answers, and `_load`, `_send` and
`dispose` are byte-for-byte the code you had — run `diff` over the two
`chat_page.dart` files and every changed line is the app bar's menu, its engine
label, the callback that carries the switch out, or the delete action moving
under that menu: `_removeModel` loses its own `try` (the `_onAction` wrapper
has it now) and takes `model.id` where it took `model.fileName`. Nothing that
talks to the model moved.

On a device *without* one, the switch itself normally succeeds — closing a
runtime is all it does. What happens next is that the gate finds the OS
reporting `unavailable*`, so it shows the setup screen; pressing **Use built-in
model** there is what fails, from `ensureReady()`:

```text
BuiltInAiUnavailableException(BuiltInAiAvailability.unavailableDeviceUnsupported): Built-in AI is not available: BuiltInAiAvailability.unavailableDeviceUnsupported
```

A typed exception carrying a `BuiltInAiAvailability`, not a platform crash —
which is why the app never shows the learner that string. `step_02`'s error
card pattern-matches the status and renders a sentence instead: for a disabled
feature, where the toggle lives on each platform. That typed failure is what
makes the next step possible.

## Step 3: Let the app choose
Duration: 8

Which engine a device has is not knowable at build time. A Pixel 9 has Gemini
Nano; a Pixel 7 does not; an iPhone 15 Pro has Apple Foundation Models only
once the user turns Apple Intelligence on. So the app asks, every launch:

```dart
Future<void> _pickAtStartup() async {
  // `availability()` never throws for an OS that answers — but a plugin
  // that failed to register does, and an uncaught throw here would leave
  // the app on the probe screen forever.
  BuiltInAiAvailability status;
  try {
    status = await BuiltInAi.availability();
  } catch (_) {
    status = BuiltInAiAvailability.unavailableOther;
  }
  // The switch evaluates `Models.builtIn`, which throws where this app has
  // no built-in arm — so guard it here the way the chat page's menu does,
  // and fall through to the downloaded model.
  ModelChoice choice;
  try {
    choice = switch (status) {
      BuiltInAiAvailability.available ||
      BuiltInAiAvailability.downloadable ||
      BuiltInAiAvailability.downloading => Models.builtIn,
      _ => Models.gemma3,
    };
  } on UnsupportedError {
    choice = Models.gemma3;
  }
  if (mounted) setState(() => _choice = choice);
}
```

Three of the seven statuses mean "the OS can give you a model" — now, after a
download, or once a running download finishes. The other four are the
`unavailable*` family, and for all of them the answer is the same: use the
downloaded model.

Two guards, two different failures. The first turns a plugin that never
registered into an `unavailableOther` verdict instead of a hang on the probe
screen. The second covers the fact that the switch *evaluates* `Models.builtIn`
— this runs unawaited from `initState`, so a throw there would escape into the
zone with the app stuck on *Checking for a built-in model…*. It is the same
`on UnsupportedError` the menu uses in Step 2.

The probe is bounded. On a device whose AI stack never answers (a
freshly-provisioned Android with no AICore metadata yet), `availability()`
gives up after 20 seconds and reports `unavailableOther` rather than hanging
your startup. `step_03_pick_at_startup` shows a *Checking for a built-in
model…* screen for that window.

`downloadable` is the interesting one: the OS *can* have a model but hasn't
fetched the feature yet, so the gate's built-in branch answers "not ready", the
app lands on the setup screen, and pressing the button there runs
`ensureReady()` — with the indeterminate bar from Step 2, because that download
has no total to report.

The manual switch from Step 2 stays in the menu, so you can override the
app's choice and compare.

## Step 4: Say why
Duration: 5

A silent decision is a support ticket waiting to happen: "why is my app
downloading half a gigabyte when the phone has Gemini?" `complete` keeps the
probe's verdict and shows it in a dismissible banner above the chat:

```dart
ModelChoice choice;
String reason;
try {
  (choice, reason) = switch (status) {
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
} on UnsupportedError {
  (choice, reason) = (
    Models.gemma3,
    'No built-in model on this platform — using a downloaded model.',
  );
}
```

The switch now yields a record, so Step 3's guard yields one too — every path
out of the probe, the `UnsupportedError` arm included, comes with a sentence
the user can read. `unavailableDisabled` gets its own line because it is the
one case the *user* can fix — the hardware is fine, the feature is switched
off.

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

* **MediaPipe** (`flutter_gemma_mediapipe`) opens `.task` files on Android,
  iOS and the web
* **ONNX Runtime** (`flutter_gemma_onnx`) opens ONNX model directories on
  macOS, Linux, Windows, Android and iOS, and runs on the web through
  Transformers.js
* **LiteRT-LM** — the engine you already registered — has a **web** arm too,
  running `.litertlm` in the browser through `@litert-lm/core`
* the built-in engine also has a **web** arm — Gemini Nano through Chrome's
  Prompt API

Each registers the same way and answers through the same chat code.

### Reference

* [flutter_gemma_builtin_ai on pub.dev](https://pub.dev/packages/flutter_gemma_builtin_ai)
  — supported devices, OS floors, and what each availability status means
* [Built-in AI documentation](/docs/builtin-ai)
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
