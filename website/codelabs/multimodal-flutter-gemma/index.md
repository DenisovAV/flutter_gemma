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

A small on-device chat app, taught to send a **picture** and a **recording**
to the model — and, at the end, taught to know where it cannot.

Two models, and the second one is the point. Step 1 downloads **SmolVLM2
500M** — 0.36 GB, about a minute — and chats with it in text. Step 2 sets one
boolean, and that same file starts describing your own photograph: no second
download, because the encoder was in there the whole time. Step 3 wants audio
— and no flag switches on an encoder the weights do not contain, so it moves
to **Gemma 4 E2B**, 2.59 GB. Seven times the size, said plainly rather than in
a footnote.

You pay it once. Those weights read pictures *and* hear you, so the app never
ends up juggling one model per modality: `complete` ships exactly one.

That is the idea worth taking away:

**A modality is a flag, not a model identity.** Inside a checkpoint that has
the encoder, you do not swap models to add vision or audio. You open the same
weights with another capability switched on — `supportImage`, `supportAudio` —
and the rest of your chat code does not move.

The flag goes in **two** places, and this is the trap: on `getActiveModel`,
where the engine is built and decides whether to load a vision or audio
executor, *and* on `createChat`, where the session declares what it will send.
Set it only on the chat and nothing complains — the model downloads, the engine
starts, the UI offers you the camera — until the first picture, when native
fails the turn with `INVALID_ARGUMENT: Vision executor should not be null`.
A setup mistake that surfaces as a generation error, minutes and a whole model
download after you made it.

Which turns the interesting question around. It stops being *"which model do I
need?"* and becomes *"what does this platform let me switch on?"* — because
that answer is not yours to set. The web runtime has no vision or audio
executor at all, and it does not refuse: it **drops the bytes** and lets the
model answer confidently about something it never received. Step 4 is about
asking, and about saying which side said no — a model that cannot, or a
platform that will not. Two different failures with two different fixes, and
this codelab hands you one of each.

### What you'll learn

* how to attach an image with `Message.withImages` and a clip with
  `Message.withAudio`
* what `supportImage` / `supportAudio` on `createChat` actually switch on, and
  why the same flag has to go on `getActiveModel` as well
* what a second modality costs when the weights do not have it, and why one
  checkpoint carrying both beats two that carry one each
* how to capture 16 kHz mono audio without a file, and why that matters for
  the web build
* that capability is **not** a build-time constant — the app has to ask what
  this platform allows, and name it when the answer is no
* what a learner on the web or an iOS Simulator should expect instead of a
  crash

### What you'll need

* [Getting Started with On-Device LLMs in Flutter](/codelabs/getting-started-flutter-gemma)
  builds the background this one assumes: installing a model, the gate that
  decides between the download screen and the chat, the streaming loop. Its
  finished app is *not* the starter here, though — `step_01_starter` runs the
  same weights Step 2 does, opened as a text session, so the model file never
  changes between Step 1 and Step 2
* **No Hugging Face token, in any step.** Both repositories this codelab
  downloads from are ungated, so every `flutter run` in it is a plain
  `flutter run` — there is no `--dart-define` anywhere in this codelab
* Room for **0.36 GB** from Step 1, and **2.59 GB** from Step 3 on — plus the
  memory to open the larger one, roughly 6 GB of RAM. A 4 GB phone is killed by
  the OS rather than told no
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
step_01_starter/     a text chat on the model Step 2 will teach to see
step_02_vision/      after Step 2 — the same model, and it can see
step_03_audio/       after Step 3 — a bigger one, and it hears too
complete/            after Step 4 — and it knows where it cannot
```

## Step 1: A modality is a session flag
Duration: 7

### Run the starter

Open `step_01_starter` and run it — a plain `flutter run`, no `--dart-define`,
no Hugging Face account. It downloads a `.litertlm` file and chats with it, in
text.

### The model you just downloaded

```dart
  /// A vision-language model small enough to feel like a text model. 0.36 GB
  /// is roughly what a photo-heavy app already spends on its image cache, so
  /// this is the version of "multimodal" you can put in a shipping app
  /// without an argument about download size — about a minute of download,
  /// and then it is looking at your photograph.
  ///
  /// It cannot hear, and that is not a gap in this step: it is a
  /// vision-language model, and the plugin lists audio input for Gemma 4 and
  /// Gemma 3n only (`flutter_gemma/README.md`). A session flag cannot switch
  /// on an encoder the checkpoint does not carry. It is why Step 3
  /// changes models, and it is the model half of the question `complete` asks
  /// at the end — a half that says no here while the device, happily holding
  /// a microphone, says yes.
  /// Run on macOS 2026-09-07: installs (0.36 GB) and answers "RED" to a
  /// 16x16 red square, with `supportImage` set on both `getActiveModel` and
  /// `createChat`. Nothing in CI runs a model, so this line is the only
  /// evidence these weights were ever executed.
  static const smolVlm2 = ModelChoice(
    label: 'SmolVLM2 500M',
    url:
        'https://huggingface.co/litert-community/SmolVLM2-500M/resolve/main/'
        'SmolVLM2-500M.litertlm',
    fileName: 'SmolVLM2-500M.litertlm',
    // `general` and not `gemmaIt`, and the reason is not turn markers. For a
    // `.litertlm` file the runtime owns the chat template on every platform
    // this codelab targets except iOS (`extensions.dart:74-77` returns
    // `raw`, which never consults this field). What the field still picks is
    // what the SDK does to the reply on the way out: `gemmaIt` is on the
    // thinking-tag-stripping list in `cleanResponse` and `general` is not.
    // SmolVLM2 is not a Gemma, so it should not be post-processed as one.
    modelType: ModelType.general,
    sizeLabel: '0.36 GB',
  );
```

A vision-language model, running a text chat. That is deliberate, and it is
what makes Step 2 readable: the file on disk will not change between here and
there. Step 2 does write a fair amount of code — a picker, a preview, a
thumbnail in the transcript — but none of that is what makes the model see.
Two flags are, and because the checkpoint is held fixed you can watch them do
it on their own.

`ModelType.general` and not `gemmaIt` is the line worth pausing on, and it is
worth pausing on for a reason that is easy to get backwards. It is tempting to
read this field as "which chat template" — it is not, at least not here. For a
`.litertlm` model the runtime owns the template on Android, macOS, Windows,
Linux and the web: `extensions.dart:74-77` returns `raw` for that file type on
every one of them, and `raw` never looks at `modelType` at all. iOS is the lone
exception, and there both `general` and `gemmaIt` emit Gemma's own
`<start_of_turn>` markers — so neither of them is "the template inside the
file".

What the field does still decide is what the SDK does to the reply on the way
out. `cleanResponse` strips thinking tags for a fixed list of families, and
`gemmaIt` is on it while `general` is not. Declare SmolVLM2 a Gemma and you
have asked for a Gemma's post-processing on a model that is not one.

0.36 GB is roughly a minute of download, which is the other reason this
codelab starts here rather than on the 2.59 GB model it ends on: you should be
reading a description of your own photograph before you have finished reading
this page.

The repository is ungated, so there is no Hugging Face plumbing in `main.dart`
at all — no token, no `--dart-define`, no 401 to explain. What there is, is a
`try`:

```dart
  try {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
  } catch (error) {
    runApp(_StartupFailed(error: error));
    return;
  }
```

That is not ceremony. This is the earliest thing in the app that can fail —
hot-restarting after adding a plugin throws `MissingPluginException` right here
— and an `await` before `runApp` that throws never reaches `runApp` at all. The
symptom is a blank window and a stack trace in a console you are probably not
looking at. Every other failure in this app arrives on screen; this one has to
be made to.

### The call this codelab changes

Now look at the call that opens the chat, because that is where this codelab's
central change lands:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        maxOutputTokens: 256,
      );
```

Nothing in it mentions pictures, and yet the weights it is opening have a
vision encoder in them. Step 2 downloads nothing: it opens this same file with
one more capability switched on.

### One checkpoint, several sessions

`createChat` takes `supportImage` and `supportAudio`. They map to
`enableVisionModality` and `enableAudioModality` on the native session. Set
neither and you get a text session. Set one and the same weights will take
pictures. Set both and they will take pictures and sound.

Nothing is downloaded in between, and nothing about the model changes: a
`.litertlm` file ships whatever encoders it was built with, and a session
decides which of them are wired up. Step 2 is where you watch that happen on
the file already sitting on this device.

Which is also the limit of the idea, and Step 3 walks straight into it. A flag
can only switch on an encoder that is in the file. The SmolVLM2 you just
downloaded has a vision encoder and no audio one, so `supportAudio: true` on it
is not a cheap way to get sound — it asks for a part the checkpoint does not
contain. Audio means different weights, and different weights mean a download,
not a boolean.

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
Duration: 9

### The model does not change

`lib/model.dart` is untouched. `step_02_vision` opens the same
`SmolVLM2-500M.litertlm` that Step 1 downloaded — same constant, same URL, same
bytes on disk — so running this step fetches nothing. Diff the two apps and
`model.dart`, `main.dart` and `download_page.dart` come back identical. Beyond
`chat_page.dart` the diff prints only what the package below drags in with it:
`pubspec.yaml`, the two entitlements files, and the five plugin registrants
`flutter pub add` regenerates for Linux, macOS and Windows.

That is the claim this codelab is making, and it is only checkable because
Step 1 was already running these weights. If the checkpoint changed here too,
"a modality is a flag" would be a sentence you had to take on trust.

Which is also why the paragraph above is a CI check and not a promise. This
repository's `tool/check_codelabs.sh` asserts both halves of it on every run —
that those three files match, and that `chat_page.dart` does **not**. A
sentence in a codelab that nothing enforces is true on the day it is written.

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

### Open a session that can see

One argument:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // The session half of "this chat can see". It maps to
        // `enableVisionModality` on the native session — a session flag, not a
        // different model: the same weights, opened with one more capability
        // switched on. The model half is the `supportImage` on
        // `getActiveModel` above, and both are required.
        supportImage: true,
        maxOutputTokens: 256,
      );
```

The call above it changes too — in two ways, one of them the trap just
described:

```dart
      // maxTokens is the CONTEXT WINDOW — prompt + history + reply share it.
      // It is NOT a reply-length cap; for that, pass maxOutputTokens below.
      // `InferenceChat` charges a message carrying an image a flat 257 tokens
      // against this budget — the SDK's own accounting, not a measurement of
      // the model, and it is per message, not per picture. 1024 is the floor
      // for a `.litertlm` model and what the earlier codelabs use; with
      // pictures in the history it stops buying a conversation, hence 4096.
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

`_send` changes in five places, and only the last one is about pictures
reaching the model: the guard now lets a turn through with no text (a photo on
its own is a valid question), the local `_Turn` carries the image so the
transcript can draw it, and the picker state is cleared once the turn is
committed. Housekeeping — but if you followed the diff instruction above, you
will see it, so here it is named rather than glossed.

The line that matters is which factory builds the message.

```dart
      await chat.addQueryChunk(
        // One factory per shape of turn. `Message.withImages` takes a LIST —
        // the API is shaped for models that accept several pictures per turn —
        // but this app sends one, and one is what the engine is built for:
        // `getActiveModel` defaults `maxNumImages` to 1 when `supportImage` is
        // on, so raise it there before sending more than one here.
        // `Message.text` is the same call with no pixels attached.
        image == null
            ? Message.text(text: text, isUser: true)
            : Message.withImages(text: text, imageBytes: [image], isUser: true),
      );
```

Everything downstream — `generateChatResponseAsync`, the streaming loop, the
error handling — is byte-for-byte the code Step 1 already ran.

Run `step_02_vision` on a phone or a desktop, attach a photo, and ask what is
in it.

## Step 3: Seven times the size, paid once
Duration: 16

Step 2's model cannot hear. Not "audio is switched off" — SmolVLM2 has no audio
encoder in it at all, and a session flag cannot wire up a part that is not
there. So this step does the thing the rest of the codelab spends its time
telling you that you rarely need to do: it changes models.

**This step downloads 2.59 GB.** Gemma 4 E2B is seven times the size of what
you have been running, and there is no honest way to shrink that number: audio
needs weights that were trained with it.

What you get for the seven times is the reason to stop here rather than keep
collecting: this one checkpoint reads pictures *and* hears you. You pay once.
The alternative — a vision model and an audio model, picked at run time — is
two downloads, two loads, both sets of weights resident the moment a user
switches input, and a conversation that cannot follow them across. `complete`
ships exactly one model, and it is this one.

### The model

```dart
  /// Gemma 4 E2B reads pictures and listens to audio with the same weights.
  ///
  /// Step 2's SmolVLM2 has no audio encoder, and a session flag cannot switch
  /// on something the checkpoint does not carry — so audio costs a second
  /// download, seven times the first at 2.59 GB. You pay it once: both
  /// modalities come out of these weights, so nothing here ever holds two
  /// models open to cover two kinds of input.
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

The id changed, so the download screen is back on the next launch: the gate in
`main.dart` asks `isModelInstalled('gemma-4-E2B-it.litertlm')` and the answer
is no. Step 2's file is not deleted for you — every step app in this codelab
shares one application identity, so SmolVLM2 is still sitting exactly where it
was. Press the delete button in `step_02_vision` before you move on if you want
that 0.36 GB back.

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

### One more flag, in both places

On the session:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        // Two flags, ONE model. They map to `enableVisionModality` and
        // `enableAudioModality` on the native session. Step 2's model had no
        // audio encoder for a flag to switch on, which is what the 2.59 GB
        // bought — and it bought both: the weights that describe your
        // photograph are the weights that hear you, so this app never opens a
        // second model to cover a second modality.
        supportImage: true,
        supportAudio: true,
        maxOutputTokens: 256,
      );
```

and — for exactly the reason Step 2 gave — on the call above it that builds the
engine, because that is where the audio executor is loaded or not loaded:

```dart
      final inference = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        supportImage: true,
        supportAudio: true,
      );
```

Two lines, in two calls. Together with the constant above, that is the entire
model-side change in this step; everything below is about getting sixteen
kilohertz of mono PCM out of a microphone.

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

### One attachment, by construction

A picture and a clip are alternatives, not a pair — a turn carrying both is a
question about neither. So the queued attachment is one field, not two:

```dart
/// What can ride along with a message.
enum _AttachmentKind { image, audio }

/// The thing queued for the next message: one kind, its bytes.
///
/// One record instead of an `_image` and an `_audio` field, because "at most
/// one attachment" is then the shape of the state rather than an invariant
/// three scattered lines have to remember. Two nullable fields can hold both at
/// once, and the sender would have to pick one — silently, which is the exact
/// failure this codelab is about.
typedef _Attached = ({_AttachmentKind kind, Uint8List bytes});
```

Assigning one replaces the other, so nothing has to remember to clear anything.
And `_send` picks the factory that matches what is attached:

```dart
  Message _message(String text, _Attached? attached) => switch (attached) {
    null => Message.text(text: text, isUser: true),
    (kind: _AttachmentKind.image, :final bytes) => Message.withImages(
      text: text,
      imageBytes: [bytes],
      isUser: true,
    ),
    (kind: _AttachmentKind.audio, :final bytes) => Message.withAudio(
      text: text,
      audioBytes: bytes,
      isUser: true,
    ),
  };
```

`Message.withImages` takes a LIST — the API is shaped for models that accept
several pictures per turn — but this app sends one, and one is what the engine
is built for: `getActiveModel` defaults `maxNumImages` to 1 when `supportImage`
is on, so raise it there before sending more than one here.

Run `step_03_audio` on a phone or a desktop. Record a few seconds asking the
model something, and watch the same streaming loop answer it — then attach a
photo to the very next turn. Same session, same weights, nothing else opened:
that is what the 2.59 GB was for.

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
  /// `capabilities.dart`. Both halves really do refuse things, and they refuse
  /// different ones: Step 2's SmolVLM2 answers no to audio on a device holding
  /// a microphone, while this model answers yes to both on a platform that
  /// will carry neither.
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

And you have met both refusals already, one per model. Run `complete` in Chrome
and the platform half says no while the weights have not changed at all. Hand
these same factories Step 2's SmolVLM2 and the **model** half says no to audio,
on a phone whose microphone was never in question. "Not supported" covers both
and helps with neither: one is fixed by opening the app somewhere else, the
other by downloading different weights, and the app is the only thing in the
room that knows which.

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

Both places again — the engine has to be built with the same answer, or the
executor the session asks for was never loaded:

```dart
      final inference = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        supportImage: _imageCapability.available,
        supportAudio: _audioCapability.available,
      );
```

One `Capability` feeds both calls, which is the point of computing it once:
two independently derived booleans are two things that can drift apart, and
this is the drift that costs 2.59 GB to discover.

### Say it out loud

A greyed-out button is not an explanation, so the app prints one:

```dart
/// One line naming a modality this app cannot use here, and which side of the
/// question refused it. Renders nothing when the modality works.
class _BlockedLine extends StatelessWidget {
  const _BlockedLine({required this.capability});

  final Capability capability;

  @override
  Widget build(BuildContext context) {
    final why = capability.blockedBecause;
    if (why == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        '${capability.what} is off — $why.',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
```

Note what this widget does *not* take: a label. `Capability` carries its own
`what` — "Image input", "Audio input" — set by the factory that already knows
which modality it is. A separate label argument compiles just as happily when
it is paired with the wrong answer, and renders *"Audio input is off — Gemma 4
E2B has no vision encoder"*: a confident, fluent sentence about something that
never happened, which is the failure this codelab was written against.

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
  static Widget _row(BuildContext context, Capability c) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.what, style: theme.textTheme.titleSmall),
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

**The iOS Simulator** is the case the two questions do not cover, and the
reason is not that Dart cannot see it — `device_info_plus` exposes
`IosDeviceInfo.isPhysicalDevice` for exactly this. It is that the Simulator is
a *supported* configuration rather than a refused one, so a flat "no" here
would be the wrong answer. The SDK runs it CPU-only, because Metal's simulator
implementation caps a single allocation at 256 MB, far below this model's
weights. A learner on a simulator should expect a 2.59 GB model to crawl if it
loads at all, and should move to hardware for the real thing; the app reports
whatever happens as a load error rather than pretending. That is a third axis —
this device, and what its memory and hardware will stand — and `Capability`
says out loud that it does not model it.

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

Two downloads, two modalities, one model at the end — and an app that knows
where it can use them.

* **Function calling** turns the model's answer into an action, and the same
  `createChat` grows a `tools:` argument for it
* **Speech-to-text** (`flutter_gemma_speech`) is the other way to use a
  microphone: transcribe first, then send text — which works on models with no
  audio encoder at all, Step 2's SmolVLM2 among them, and is often the cheaper
  design
* **MediaPipe** (`flutter_gemma_mediapipe`) opens `.task` models and is the
  engine to reach for when vision on the **web** is a requirement

### Reference

* [flutter_gemma on pub.dev](https://pub.dev/packages/flutter_gemma) — the full
  platform support matrix, including the web `.litertlm` limitations
* [Multimodal documentation](/docs/multimodal)
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
