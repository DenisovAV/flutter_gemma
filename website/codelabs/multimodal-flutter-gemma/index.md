author: Sasha Denisov
summary: Multimodal Inference in Flutter — Vision and Audio on Device
id: multimodal-flutter-gemma
categories: flutter, ai, gemma, multimodal
environments: android, ios, macos, windows, linux, web
status: Published

# Multimodal Inference in Flutter: Vision and Audio on Device

## Overview
Duration: 3

### What you'll build

The chat app from the *Getting Started* codelab, taught to send a **picture**
and a **recording** to the model — and, more importantly, taught to know when
it cannot.

Two models do the work, and the gap between them is the point:

* **SmolVLM2 500M** — 0.36 GB, and it can look at an image. It cannot hear.
* **Gemma 4 E2B** — 2.59 GB, and it can do both.

Seven times the download for one extra modality is not a footnote; it is the
product decision this codelab is really about. The finished app lets the user
make it, and says out loud what each choice costs.

The chat loop itself barely changes. `_send` gains one branch — which
`Message` factory to call — and `createChat` gains two arguments. Everything
else you write is the app finding out what is possible here, and saying so.

### What you'll learn

* how to attach an image with `Message.withImages` and a clip with
  `Message.withAudio`
* what `supportImage` / `supportAudio` on `createChat` actually switch on
* that **capability is not a build-time constant**: a model that accepts audio
  does not mean this platform will deliver it, and a platform that can record
  does not mean the model can hear — the app has to ask both, and say which
  one said no
* what image and audio input really cost in the context window
* why a 2.59 GB model is a device proposition and a 0.36 GB one is not

### What you'll need

* The finished app from
  [Getting Started with On-Device LLMs in Flutter](/codelabs/getting-started-flutter-gemma)
  — or just its `complete/` directory, which is this codelab's starter
* **No Hugging Face token.** Both model repositories here are ungated, so
  every `flutter run` in this codelab is a plain `flutter run` with no
  `--dart-define`
* Anything the app runs on. Image input works on all five native platforms —
  Android, iOS, macOS, Windows, Linux. Audio input works on Android, on a real
  iPhone or iPad, and on all three desktops. **Neither works on the web** with
  the `.litertlm` engine, and Step 1 explains why that is a feature of this
  codelab rather than a hole in it
* For Step 3 and `complete`, roughly **6 GB of RAM** on the device. Gemma 4 E2B
  is 2.59 GB of weights before the KV cache; a 4 GB phone is killed by the OS
  rather than told no

### Get the code

```bash
git clone --depth 1 https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma/codelabs/multimodal-flutter-gemma
ls
```

```text
step_01_starter/     the Getting Started app, unchanged
step_02_vision/      after Step 2 — images, SmolVLM2
step_03_audio/       after Step 3 — audio too, Gemma 4
complete/            after Step 4 — both models, and the choice between them
```

## Step 1: Two questions, not one
Duration: 5

### Run the starter

Open `step_01_starter` and run it. It is the Getting Started app: download a
`.litertlm` file, chat with it, in text.

Now think about what it would take to hand that chat a photograph. The
tempting answer is one boolean — `canSendImage` — set once, somewhere near the
top of the app. That boolean is wrong, and it is wrong in a way that only
shows up on someone else's device.

### The model half

A model can only take the inputs its weights were trained on. SmolVLM2 has a
vision encoder and no audio one. Gemma 4 E2B has both. Gemma 3 1B, the model
you have been running so far, has neither.

This half is a property of the **checkpoint**. It is the same answer on a
Pixel, on a Mac and in Chrome, and you can write it down as a constant:

```dart
  /// Whether these WEIGHTS were trained to look at a picture.
  ///
  /// A property of the checkpoint, not of the device: the answer is the same
  /// on a Pixel, on a Mac and in Chrome. It is only half of "can this app
  /// send an image" — the other half lives in `capabilities.dart`.
  final bool supportsImage;
```

### The platform half

The other half is not about the model at all. It is about whether the runtime
on *this* platform has anywhere to put those bytes.

`flutter_gemma_litertlm`'s browser arm runs the upstream `@litert-lm/core`
package, and that JS API exposes no vision executor and no audio executor. So
on the web the image is not refused. It is **dropped, with a debug warning** —
and the model then answers, fluently and confidently, about a picture it never
received. That is a far worse failure than an exception, because nothing in
the app or the transcript looks wrong.

This half is a property of the **platform**, and no model can tell you the
answer:

```dart
  /// Image input reaches the model on all five native platforms — Android,
  /// iOS, macOS, Windows and Linux.
  ///
  /// Not on the web: `flutter_gemma_litertlm`'s browser arm runs the upstream
  /// `@litert-lm/core` package, whose JS API exposes no vision executor, so
  /// image bytes are **dropped with a debug warning** rather than refused.
  /// That is the worst failure mode a modality can have — the model answers,
  /// fluently and confidently, about a picture it never received — which is
  /// exactly why the app asks this before it sends anything.
  static bool get image => !kIsWeb;
```

### Why one boolean is not enough

Ask only the model and you enable a vision session on a platform that will
never feed it. Ask only the platform and you enable one the weights cannot
use. And collapse the two into a single `bool` and you have thrown away the
only thing the user needed: *which* answer was no.

That is the difference between "Images aren't supported" — which tells a user
nothing and reads as a bug — and "SmolVLM2 500M has no audio encoder", which
tells them to switch models, or "this platform cannot carry audio to the
model", which tells them to switch devices. Same disabled button; completely
different next action.

So the app keeps both answers, and derives the third:

```dart
  bool get available => byModel && byPlatform;

  /// Which side said no, and why. Null when both said yes.
  ///
  /// Both sides can refuse at once — a text-only model in a browser — and
  /// then the user deserves both halves, because fixing one changes nothing.
  String? get blockedBecause => switch ((byModel, byPlatform)) {
    (true, true) => null,
    (false, true) => modelReason,
    (true, false) => platformReason,
    (false, false) => '$modelReason, and $platformReason',
  };
```

The `(false, false)` arm is not defensive padding. A vision-only model opened
in Chrome hits it, and a user told only one of the two reasons would fix that
one and find nothing had changed.

## Step 2: Send a picture
Duration: 16

### Add the package

```bash
flutter pub add image_picker
```

`image_picker` declares all six platforms: a photo gallery on Android and iOS,
and a file dialog — through `file_selector` — on macOS, Windows, Linux and the
web. That single call is why this step needs no platform branching in the UI.

### One platform change

macOS runs sandboxed, and a sandboxed app cannot read a file the user picked
unless it says it will. Add one key to **both** `macos/Runner/DebugProfile.entitlements`
and `macos/Runner/Release.entitlements`:

```xml
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
```

Both files, not one: `Debug` is what `flutter run` uses and `Release` is what
you ship, and an entitlement added to only the first works perfectly until the
day it matters.

Android needs nothing — the system photo picker hands back a URI without a
permission. iOS needs nothing either: since iOS 14 `image_picker` uses
`PHPicker`, which runs out of process and requires no
`NSPhotoLibraryUsageDescription`. Windows, Linux and the web need nothing.

### The model

`step_02_vision` replaces Gemma 3 with a model that can see, and adds the flag
that says so:

```dart
  static const smolVlm2 = ModelChoice(
    label: 'SmolVLM2 500M',
    url:
        'https://huggingface.co/litert-community/SmolVLM2-500M/resolve/main/'
        'SmolVLM2-500M.litertlm',
    fileName: 'SmolVLM2-500M.litertlm',
    // `general` and not `gemmaIt`: SmolVLM2 is not a Gemma, and the chat
    // template that ships inside the `.litertlm` is the right one to use.
    modelType: ModelType.general,
    sizeLabel: '0.36 GB',
    supportsImage: true,
  );
```

0.36 GB is the number that makes this interesting. It is roughly what a
photo-heavy app already spends on its image cache. A vision model at that size
is something you can put in a shipping app without an argument about download
budgets — which is not true of the 2.59 GB one waiting in Step 3.

The repository is ungated, so `main.dart` also loses the Hugging Face plumbing
it inherited:

```dart
  await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
```

### Ask both sides, once

`capabilities.dart` turns the two halves into one value the rest of the page
uses:

```dart
/// Can this app send an image right now, with this model, on this device?
Capability imageCapability(ModelChoice model) => Capability(
  byModel: model.supportsImage,
  byPlatform: PlatformSupport.image,
  modelReason: '${model.label} has no vision encoder',
  platformReason: PlatformSupport.imageBlockedReason,
);
```

The chat page asks it once, in a `late final`, and then uses that one answer
in three places: to open the session, to enable the button, and to explain
itself.

```dart
  /// Asked once, of both sides, and then used everywhere: to open the right
  /// kind of session, to enable the attach button, and to say why not.
  late final Capability _imageCapability = imageCapability(widget.model);
```

### Open a vision session

`supportImage` is the whole switch. It maps to `enableVisionModality` on the
native session, and it takes the AND of both answers — never one of them:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // BOTH halves of the question, in one expression. `supportImage: true`
        // maps to `enableVisionModality` on the native session: asking for it
        // on weights with no vision encoder fails at session creation, and
        // asking for it on a platform that cannot carry images opens a vision
        // session nothing will ever feed.
        supportImage: _imageCapability.available,
        maxOutputTokens: 256,
      );
```

Note the window above it. Images are not free in the context budget — the
vision encoder turns one picture into hundreds of tokens, and they come out of
the same allowance as the history and the reply:

```dart
      // maxTokens is the CONTEXT WINDOW — prompt + history + reply share it.
      // An image is not free there: the vision encoder turns one picture into
      // hundreds of tokens, so a multimodal turn eats context a text turn
      // would not.
      final inference = await FlutterGemma.getActiveModel(maxTokens: 2048);
```

`maxTokens` is still not a reply-length cap. `maxOutputTokens` is; it has not
changed since Getting Started, and it does not need to.

### Pick the image

The plugin takes **bytes**, not a path. That is why one code path covers a
phone's gallery and a desktop's file dialog:

```dart
  /// Reads a picture into memory. The plugin takes bytes, not a path — which
  /// is why this works the same on a phone and on a desktop file dialog.
  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        // The vision encoder resizes to its own input square anyway, so a
        // 12-megapixel original costs decode time and memory for nothing.
        maxWidth: 1024,
        maxHeight: 1024,
      );
      // Null means the user closed the picker. That is not an error, and
      // reporting it as one is how an app earns a reputation for shouting.
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _image = bytes;
          _notice = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Could not read that image: $error');
      }
    }
  }
```

Two details worth keeping. `maxWidth` / `maxHeight` are not cosmetic: the
encoder resizes to its own input square anyway, so decoding a 12-megapixel
original costs time and memory for nothing — on a phone, sometimes for an
out-of-memory kill. And a `null` file is the user closing the picker, not a
failure; an app that shows an error there is an app people learn to distrust.

### Send it

One line changes in `_send`: which factory builds the message.

```dart
      await chat.addQueryChunk(
        // One factory per shape of turn. `Message.withImages` takes a LIST,
        // because a model that can see one picture can usually see several;
        // `Message.text` is the same call with no pixels attached.
        image == null
            ? Message.text(text: text, isUser: true)
            : Message.withImages(text: text, imageBytes: [image], isUser: true),
      );
```

`Message.withImages` takes a `List<Uint8List>` because a model that can see one
picture can usually see several. Everything downstream — `generateChatResponseAsync`,
the streaming loop, the error handling — is byte-for-byte the code from
Getting Started.

### Say which side said no

The last piece is a widget that renders nothing when the modality works, and a
sentence when it does not:

```dart
/// One line naming a modality this app cannot use here, and which side of the
/// question refused it. Renders nothing when the modality works.
class _BlockedLine extends StatelessWidget {
  const _BlockedLine({required this.what, required this.capability});

  final String what;
  final Capability capability;

  @override
  Widget build(BuildContext context) {
    final why = capability.blockedBecause;
    if (why == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        '$what is off — $why.',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
```

Run `step_02_vision` on a Mac, a phone or a desktop: attach a photo, ask what
is in it. Run the same app in Chrome and the attach button is greyed out with
a line under the composer naming the runtime that refused — not a crash, and
not a silent lie about a photo the model never saw.

## Step 3: Send a recording
Duration: 16

### Add the package

```bash
flutter pub add record
```

### Three platform changes

Audio needs a microphone, and every platform wants to be asked differently.

Android, in `android/app/src/main/AndroidManifest.xml`:

```xml
    <!-- Recording the clip the model listens to. `record` asks the user for
         it at run time; without the declaration here that request is denied
         before the dialog can appear. -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
```

iOS, in `ios/Runner/Info.plist` — the string is shown to the user, so write it
as if a reviewer will read it, because one will:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Recordings are sent to a language model running on this device. Nothing leaves the phone.</string>
```

macOS, in **both** entitlements files again:

```xml
	<key>com.apple.security.device.audio-input</key>
	<true/>
```

Windows and Linux need nothing declared.

### The model, and what it costs

SmolVLM2 cannot hear, so this step switches to Gemma 4 E2B:

```dart
  /// Both modalities in one checkpoint — and seven times the download for it.
  /// 2.59 GB is a real product decision, not a detail: it rules out low-RAM
  /// phones and it is why the app in `complete/` lets the user choose.
  static const gemma4 = ModelChoice(
    label: 'Gemma 4 E2B',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    modelType: ModelType.gemma4,
    sizeLabel: '2.59 GB',
    supportsImage: true,
    supportsAudio: true,
  );
```

Both flags are now on `ModelChoice`, and they are independent on purpose:

```dart
  /// Whether these weights were trained to listen. Independent of
  /// [supportsImage]: a vision-language model has an image encoder and no
  /// audio one, and that is the common case, not an edge case.
  final bool supportsAudio;
```

### Capture without a file

`record` writes to a path — and getting a writable path on every platform
means `path_provider`, which imports `dart:io` and therefore cannot be
compiled for the web. `startStream` avoids the problem entirely: it hands the
samples to Dart, and the clip never touches disk.

```dart
      _pcm.clear();
      final done = Completer<void>();
      final stream = await _recorder.startStream(
        const RecordConfig(
          // Raw PCM, not a container: `startStream` hands the samples to Dart
          // instead of writing a file, so nothing here needs a writable path.
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: _channels,
        ),
      );
```

16 kHz mono is what the model's audio front end wants. Sending it 44.1 kHz
stereo means a resample happens somewhere, and the somewhere is native code
you cannot see:

```dart
/// The recorder asks for these, and [wavFromPcm16] writes them into the
/// header. 16 kHz mono is what the model's audio front end wants; sending it
/// 44.1 kHz stereo means resampling somewhere, and the somewhere is native
/// code you cannot see.
const _sampleRate = 16000;
const _channels = 1;
```

Raw PCM is not a file format, so `lib/wav.dart` puts a forty-four-byte header
in front of it. There is nothing clever in it, and that is the point — the
whole cost of avoiding a sixth dependency is one small, testable function:

```dart
  ascii(0, 'RIFF');
  // Everything after this field: 44 - 8 header bytes, plus the samples.
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt chunk length
  header.setUint16(20, 1, Endian.little); // 1 = uncompressed PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
```

A wrong length or a wrong sample rate here does not crash. It makes the model
hear the clip at the wrong speed, which reads to everyone as a bad model — so
`test/widget_test.dart` asserts every field of that header.

### The third question: the device

The model half and the platform half are static. There is a third question,
and it is neither: does this particular device have a microphone the user is
willing to lend you?

```dart
  /// Starts capture, collecting raw samples in memory.
  ///
  /// This is the third question, and it is not the model's or the platform's:
  /// it is the device's. `hasPermission()` is the only honest way to ask it —
  /// on an iOS Simulator with no input device, or after the user has said no
  /// once, the answer is false however capable the model and the OS are.
  Future<void> _startRecording() async {
```

`hasPermission()` is asked at the moment of recording rather than baked into
`Capability`, because unlike the other two it can change while the app is
running.

### Stop, and wait for the last bytes

```dart
      await _recorder.stop();
      // `stop()` returns before the platform has flushed its last buffers.
      // The stream's done event is what says every sample arrived; the
      // timeout is there so a platform that never closes it cannot hang the
      // button, at the cost of the final fraction of a second.
      await _samplesDone?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
```

`stop()` returning is not the same as the samples having arrived. Cancel the
subscription there and you truncate the clip — usually by a fraction of a
second, occasionally by the last word of the question.

### Two modalities, one session

`createChat` now takes both flags, each the AND of its own two answers:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // BOTH halves of each question, in one expression. These map to
        // `enableVisionModality` and `enableAudioModality` on the native
        // session: asking for a modality the weights do not have fails at
        // session creation, and asking for one the platform cannot carry
        // opens a session nothing will ever feed.
        supportImage: _imageCapability.available,
        supportAudio: _audioCapability.available,
        maxOutputTokens: 256,
      );
```

And `_send` picks the factory that matches what is attached:

```dart
  /// One factory per shape of turn. `Message.withImages` takes a LIST, because
  /// a model that can see one picture can usually see several;
  /// `Message.withAudio` takes exactly one clip; `Message.text` is the same
  /// call with nothing attached.
  Message _message(String text, {Uint8List? image, Uint8List? audio}) {
    if (image != null) {
      return Message.withImages(text: text, imageBytes: [image], isUser: true);
    }
    if (audio != null) {
      return Message.withAudio(text: text, audioBytes: audio, isUser: true);
    }
    return Message.text(text: text, isUser: true);
  }
```

The context window grows again — to 4096 — for the same reason as before, one
step further along:

```dart
      // maxTokens is the CONTEXT WINDOW — prompt + history + reply share it.
      // Both modalities spend it: the vision encoder turns one picture into
      // hundreds of tokens and the audio encoder turns every second of sound
      // into more. This is why a multimodal chat asks for a bigger window
      // than a text one, not because the replies got longer.
      final inference = await FlutterGemma.getActiveModel(maxTokens: 4096);
```

That is also why the clip is capped:

```dart
/// A clip long enough to ask a question and short enough not to eat the
/// context window. Audio is not free: the encoder turns every second into
/// tokens, and they come out of the same budget as the reply.
const _maxClip = Duration(seconds: 15);
```

### The platform matrix, as it really is

| | Android | iOS device | iOS Simulator | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|---|
| Text | yes | yes | yes (CPU) | yes | yes | yes | yes |
| Image input | yes | yes | yes (CPU) | yes | yes | yes | **no** |
| Audio input | yes | yes | no microphone | yes | yes | yes | **no** |
| GPU | yes | yes | **no** | yes | yes | yes | required |

Three rows of that table deserve a sentence each.

**The web** is a `no` for both modalities, and it is not a bug in your setup.
The `.litertlm` browser runtime is an early preview of `@litert-lm/core`, and
it is text-only: image and audio bytes are dropped with a debug warning. A
learner running `step_02_vision` or `step_03_audio` in Chrome should expect
the app to load, download the model, chat in text, and grey out both
attachment buttons with a sentence naming the runtime. That is the app
working. (Full vision on the web today means MediaPipe `.task` models and the
`flutter_gemma_mediapipe` package — a different engine, and the subject of the
[Inference Engines codelab](/codelabs/inference-engines-flutter-gemma).)

**The iOS Simulator** is CPU-only: Metal's simulator implementation caps a
single allocation at 256 MB, and LLM weights are far past that. SmolVLM2 at
0.36 GB will load and answer on the simulator's CPU, slowly. Gemma 4 E2B at
2.59 GB is a device proposition, and the simulator has no microphone to record
with either — so a learner on a simulator should run Step 2 there and Step 3
on hardware.

**Android and desktop** are the unrestricted case: both modalities, GPU
accelerated, no caveats.

Run `step_03_audio` on a phone or a desktop. Record five seconds asking the
model something, and watch the same streaming loop answer it.

## Step 4: Let the user choose what it costs
Duration: 8

Steps 2 and 3 each hard-coded a model. `complete` stops doing that, because
the choice between them is the interesting one:

```dart
class _MultimodalAppState extends State<MultimodalApp> {
  /// Which model the app is running. The default is the small one: 0.36 GB
  /// downloads on a phone network, and a user who wants audio can pay the
  /// 2.59 GB deliberately rather than discover it on first launch.
  ModelChoice _choice = Models.smolVlm2;
```

The default is deliberate. 0.36 GB downloads on a phone network without a
conversation; 2.59 GB is something a user should decide to spend, not discover
after tapping *Download model*.

### The way out has to exist before the download does

Which is why the setup screen — the screen that IS the whole app until a model
is on the device — offers the alternative, with its price and its modalities
on the button:

```dart
                // What each model can do, and what it costs, side by side —
                // stated before the download rather than after it.
                for (final other in Models.all)
                  if (other.fileName != widget.model.fileName) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _downloading
                          ? null
                          : () => widget.onSwitch(other),
                      child: Text(
                        'Use ${other.label} instead '
                        '(${other.sizeLabel}, ${_modalities(other)})',
                      ),
                    ),
                  ],
```

A learner who only wants to look at pictures should never have to download an
audio encoder to find that out.

### Switching models means closing the old one

```dart
  /// Release this model's runtime before the app activates another one. Each
  /// holds native memory, and a 2.59 GB model held open while a second one
  /// loads is how a phone runs out of it.
  Future<void> _switchTo(ModelChoice next) async {
    await _inference?.close();
```

And a new key on the gate restarts it for the new model, so the previous
model's "installed" answer cannot leak across the switch:

```dart
      // A new key per model restarts the gate from scratch on a switch —
      // otherwise the gate would keep the previous model's "installed" answer
      // and hand the chat page a model that is not on the device.
      home: ModelGate(
        key: ValueKey(_choice.fileName),
        model: _choice,
        onSwitch: (next) => setState(() => _choice = next),
      ),
```

### Both questions, asked out loud

The app bar carries the summary at all times:

```dart
            child: Text(
              'image ${_imageCapability.available ? 'on' : 'off'} · '
              'audio ${_audioCapability.available ? 'on' : 'off'}',
              style: theme.textTheme.labelSmall,
            ),
```

and the info button opens the screen this whole codelab exists for. It never
says "not supported". It shows both answers, separately, and the reason
underneath:

```dart
  static Widget _row(BuildContext context, String what, Capability c) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(what, style: theme.textTheme.titleSmall),
        Text('the model: ${c.byModel ? 'yes' : 'no'}'),
        Text('this platform: ${c.byPlatform ? 'yes' : 'no'}'),
        if (c.blockedBecause case final why?)
          Text(
            why,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else
          Text('available', style: theme.textTheme.bodySmall),
      ],
    );
  }
```

Run `complete` and switch between the two models with the app bar menu. The
audio row flips from *the model: no* to *the model: yes* while the platform
row does not move. Open the same app in Chrome and the platform row flips
instead, for both modalities, while the model rows stay where they were.

Two independent facts, visibly independent. That is the whole idea, and it is
why the app can tell a user something more useful than "not supported".

### Try it end to end

`complete` also ships an integration test that downloads SmolVLM2, sends a
real image and asserts the model answered about it. It needs a device and a
0.36 GB download, so it is not part of CI:

```bash
cd codelabs/multimodal-flutter-gemma/complete
flutter test integration_test/multimodal_test.dart -d <device-id>
```

## What's next
Duration: 2

You now have an app that knows what it can do, on this model, on this device —
and says which one refused when it cannot.

* **Function calling** turns the model's answer into an action, and the same
  `createChat` grows a `tools:` argument for it
* **Speech-to-text** (`flutter_gemma_speech`) is the other way to use a
  microphone: transcribe first, then send text — which works on models with no
  audio encoder at all, and is often the cheaper design
* **MediaPipe** (`flutter_gemma_mediapipe`) opens `.task` models and is the
  engine to reach for when vision on the **web** is a requirement

### Reference

* [flutter_gemma on pub.dev](https://pub.dev/packages/flutter_gemma) — the full
  platform support matrix, including the web `.litertlm` limitations
* [Multimodal documentation](/docs/multimodal)
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
