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
and a **recording** to the model — and, at the end, taught to know where it
cannot.

One model does all of it: **Gemma 4 E2B**, 2.59 GB, downloaded once in Step 2.
Step 3 adds audio and downloads **nothing**. The weights that described your
photograph are the weights that hear you.

That is the idea worth taking away:

**A modality is a flag, not a model identity.** You do not swap models to add
vision or audio. You open the same weights with another capability switched on
— `supportImage`, `supportAudio` — and the rest of your chat code does not
move.

The flag goes in **two** places, and this is the trap: on `getActiveModel`,
where the engine is built and decides whether to load a vision or audio
executor, *and* on `createChat`, where the session declares what it will send.
Set it only on the chat and nothing complains — the model downloads, the engine
starts, the UI offers you the camera — until the first picture, when native
fails the turn with `INVALID_ARGUMENT: Vision executor should not be null`.
A setup mistake that surfaces as a generation error, several minutes and 2.59 GB
after you made it.

Which turns the interesting question around. It stops being *"which model do I
need?"* and becomes *"what does this platform let me switch on?"* — because
that answer is not yours to set. The web runtime has no vision or audio
executor at all, and it does not refuse: it **drops the bytes** and lets the
model answer confidently about something it never received. Step 4 is about
asking, and about saying which side said no.

### What you'll learn

* how to attach an image with `Message.withImages` and a clip with
  `Message.withAudio`
* what `supportImage` / `supportAudio` on `createChat` actually switch on, and
  that adding one downloads nothing
* how to capture 16 kHz mono audio without a file, and why that matters for
  the web build
* that capability is **not** a build-time constant — the app has to ask what
  this platform allows, and name it when the answer is no
* what a learner on the web or an iOS Simulator should expect instead of a
  crash

### What you'll need

* The finished app from
  [Getting Started with On-Device LLMs in Flutter](/codelabs/getting-started-flutter-gemma)
  — or just its `complete/` directory, which is this codelab's starter
* **No Hugging Face token.** The model repository is ungated, so every
  `flutter run` here is a plain `flutter run` with no `--dart-define`
* A device with room for a **2.59 GB** model and the memory to open it —
  roughly 6 GB of RAM. A 4 GB phone is killed by the OS rather than told no
* Android, a real iPhone or iPad, macOS, Windows or Linux for the full thing.
  The web and the iOS Simulator both run this app; Step 4 covers what they do
  instead

### Get the code

```bash
git clone --depth 1 https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma/codelabs/multimodal-flutter-gemma
ls
```

```text
step_01_starter/     the Getting Started app, unchanged
step_02_vision/      after Step 2 — the model downloaded, and it can see
step_03_audio/       after Step 3 — the same model, now it can hear too
complete/            after Step 4 — and it knows where it cannot
```

## Step 1: A modality is a session flag
Duration: 4

### Run the starter

Open `step_01_starter` and run it. It is the Getting Started app: download a
`.litertlm` file, chat with it, in text.

Now look at the call that opens the chat, because that is the only place this
codelab really changes:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        maxOutputTokens: 256,
      );
```

### One model, three sessions

`createChat` takes `supportImage` and `supportAudio`. They map to
`enableVisionModality` and `enableAudioModality` on the native session. Set
neither and you get a text session. Set one and the same weights will take
pictures. Set both and they will take pictures and sound.

Nothing is downloaded in between, and nothing about the model changes. Gemma 4
E2B ships every encoder it has in the one 2.59 GB file; a session simply
decides which of them are wired up. That is why Step 3 of this codelab —
"now add audio" — has no download step in it at all.

### What is not yours to decide

The flags are yours to set. Whether the platform honours them is not.

`flutter_gemma_litertlm`'s browser arm runs the upstream `@litert-lm/core`
package, and that JS API exposes **no vision executor and no audio executor**.
Setting `supportImage: true` there does not throw. It opens a session that will
never be fed: the image bytes are dropped with a debug warning, and the model
answers — fluently, confidently — about a picture it never received.

An exception you can catch. A dropped input you cannot, and neither can your
user. So by the end of this codelab the app asks first, and when the answer is
no it says **which** no it got:

```dart
  bool get available => byModel && byPlatform;

  /// Which side said no, and why. Null when both said yes.
  ///
  /// Both can refuse at once — a text-only model in a browser — and then the
  /// user deserves both halves, because fixing one changes nothing.
  String? get blockedBecause => switch ((byModel, byPlatform)) {
    (true, true) => null,
    (false, true) => modelReason,
    (true, false) => platformReason,
    (false, false) => '$modelReason, and $platformReason',
  };
```

*"This platform has no audio input"* reads very differently to a learner than a
greyed-out microphone. One is information; the other is a bug report waiting to
be filed.

## Step 2: Send a picture
Duration: 14

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

`step_02_vision` replaces Gemma 3 with the one model this codelab uses from
here on:

```dart
  /// Gemma 4 E2B reads pictures and listens to audio with the same weights.
  /// You download it once, in Step 2, and Step 3 adds a second modality to
  /// the model that is already on the device.
  static const gemma4 = ModelChoice(
    label: 'Gemma 4 E2B',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    modelType: ModelType.gemma4,
    sizeLabel: '2.59 GB',
  );
```

The repository is ungated, so `main.dart` also loses the Hugging Face plumbing
it inherited from Getting Started:

```dart
  await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
```

### Open a session that can see

One argument:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // The whole of "this chat can see". It maps to `enableVisionModality`
        // on the native session — a session flag, not a different model. The
        // same weights, opened with one more capability switched on.
        supportImage: true,
        maxOutputTokens: 256,
      );
```

The call above it changes too — in two ways, one of them the trap just
described:

```dart
      // maxTokens is the CONTEXT WINDOW — prompt + history + reply share it.
      // It is NOT a reply-length cap; for that, pass maxOutputTokens below.
      // An image costs ~257 tokens of it, so 1024 no longer buys a
      // conversation once pictures are in it.
      //
      // The modality flag belongs HERE as well as on the chat below. This is
      // where the engine is built, and it only loads a vision executor if it
      // is told to. Set it on the chat alone and everything looks fine until
      // the first image, when native fails the turn with
      // `INVALID_ARGUMENT: Vision executor should not be null`.
      final inference = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        supportImage: true,
      );
```

Worth knowing that images are not free inside that window: `InferenceChat`
charges a message carrying an image a flat **257 tokens** against `maxTokens`
in its own bookkeeping (`lib/core/chat.dart`), and trims the oldest history
when the total gets close. That is the SDK's accounting, not a measurement of
the model.

### Pick the image

The plugin takes **bytes**, not a path. That is why one code path covers a
phone's gallery and a desktop's file dialog:

```dart
  /// Reads a picture into memory. The plugin takes bytes, not a path — which
  /// is why this works the same on a phone and in a desktop file dialog.
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
original costs time and memory for nothing — on a phone, sometimes an
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

Everything downstream — `generateChatResponseAsync`, the streaming loop, the
error handling — is byte-for-byte the code from Getting Started.

Run `step_02_vision` on a phone or a desktop, attach a photo, and ask what is
in it.

## Step 3: The same model, now it hears
Duration: 14

This is the shortest step in the codelab, and the headline is what it does
*not* contain: **there is no download**. Gemma 4 E2B is already on the device
from Step 2. You are about to add a whole modality by setting one boolean.

### Add the package

```bash
flutter pub add record
```

`record` is for capture, not for the model — the microphone, not the weights.

### Three platform changes

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

### One more flag

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // Two flags, one model. They map to `enableVisionModality` and
        // `enableAudioModality` on the native session. Nothing was downloaded
        // for the second one: the weights that read your photograph in Step 2
        // are the weights that hear you now — the only thing that changed is
        // which capabilities this session was opened with.
        supportImage: true,
        supportAudio: true,
        maxOutputTokens: 256,
      );
```

That is the entire model-side change in this step. Everything below is about
getting sixteen kilohertz of mono PCM out of a microphone.

### Capture without a file

`record.start()` writes to a path — and getting a writable path on every
platform means `path_provider`, which imports `dart:io` and therefore cannot be
compiled for the web. This app has to compile for the web whether or not audio
works there, so it uses `startStream` instead: the samples arrive in Dart and
the clip never touches disk.

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

16 kHz mono is what the model's audio front end wants:

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
whole cost of not taking a sixth dependency is one small, testable function:

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

### The microphone is its own question

```dart
  /// Starts capture, collecting raw samples in memory.
  ///
  /// `hasPermission()` is the device's own answer, and it is not the model's
  /// or the platform's: on a simulator with no input device, or after the
  /// user has declined once, it is false however capable the rest is.
  Future<void> _startRecording() async {
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

Run `step_03_audio` on a phone or a desktop. Record a few seconds asking the
model something, and watch the same streaming loop answer it — no new
download, no second model, one more flag.

## Step 4: Ask what this platform allows
Duration: 9

`step_03_audio` sets both flags to `true` unconditionally. On Android, iOS,
macOS, Windows and Linux that is correct. Run it in Chrome and it is a lie the
app tells itself: attach a photo, ask about it, and Gemma answers in confident
detail about an image the runtime dropped before it ever reached the weights.

`complete` fixes that by asking, and it asks two things.

### Two questions, and a name for the answer

The **model half** is a property of the checkpoint — the same answer on a
Pixel, a Mac and in Chrome:

```dart
  /// What the WEIGHTS accept. Properties of the checkpoint, not of the
  /// device: the same answer on a Pixel, on a Mac and in Chrome. They are
  /// only half of "can this app send one" — the other half is in
  /// `capabilities.dart`, and on this codelab's single model it is the only
  /// half that ever says no.
  final bool supportsImage;
  final bool supportsAudio;
```

The **platform half** is not:

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

Both are needed. Keeping only the AND would work and would tell the user
nothing; `Capability` keeps the two answers apart precisely so it can name the
one that refused.

### The flags stop being constants

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // Still two session flags on one model — but no longer hard-coded
        // `true`. Each is the AND of both answers: what the weights accept
        // and what this platform will carry to them. Asking for a modality
        // the platform cannot deliver opens a session nothing will ever
        // feed, and on the web that failure is silent.
        supportImage: _imageCapability.available,
        supportAudio: _audioCapability.available,
        maxOutputTokens: 256,
      );
```

### Say it out loud

A greyed-out button is not an explanation, so the app prints one:

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

The app bar carries the same verdict in two words, always visible:

```dart
            child: Text(
              'image ${_imageCapability.available ? 'on' : 'off'} · '
              'audio ${_audioCapability.available ? 'on' : 'off'}',
              style: theme.textTheme.labelSmall,
            ),
```

and the info button opens the screen this whole codelab exists for. It never
says "not supported". It shows both answers separately, with the reason
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

Run `complete` natively and both rows read *yes / yes*. Run it in Chrome and
the model rows do not move — the weights did not change — while both platform
rows flip to *no*. Two independent facts, visibly independent.

### The platform matrix, as it really is

| | Android | iOS device | iOS Simulator | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|---|
| Text | yes | yes | CPU only | yes | yes | yes | yes |
| Image input | yes | yes | CPU only | yes | yes | yes | **no** |
| Audio input | yes | yes | no microphone | yes | yes | yes | **no** |
| GPU | yes | yes | **no** | yes | yes | yes | required |

Two of those columns deserve a sentence each.

**The web** is a `no` for both modalities, and it is not a bug in your setup.
The `.litertlm` browser runtime is an early preview of `@litert-lm/core` and it
is text-only. What a learner should expect there: the app loads, the model
downloads, text chat works, and both attachment buttons are disabled with a
line naming the runtime that refused. That is the app working correctly. (Full
vision on the web today means MediaPipe `.task` models and the
`flutter_gemma_mediapipe` package — a different engine, and the subject of the
[Inference Engines codelab](/codelabs/inference-engines-flutter-gemma).)

**The iOS Simulator** is the case the two questions do not cover, because it
fails earlier than either of them. It is CPU-only — Metal's simulator
implementation caps a single allocation at 256 MB, far below this model's
weights — so a 2.59 GB model is a device proposition there, and it has no
microphone to record with in the first place. A learner on a simulator should
expect the load to fail or crawl, and should move to hardware; the app reports
it as a load error rather than pretending.

**Android, a real iPhone, and the three desktops** are the unrestricted case:
both modalities, GPU accelerated, no caveats.

### Try it end to end

`complete` ships an integration test that downloads the model, opens one
session with both flags set to whatever the platform allows, and sends a real
image through it. It needs a device and a 2.59 GB download, so it is not part
of CI:

```bash
cd codelabs/multimodal-flutter-gemma/complete
flutter test integration_test/multimodal_test.dart -d <device-id>
```

## What's next
Duration: 2

One model, two modalities, and an app that knows where it can use them.

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
