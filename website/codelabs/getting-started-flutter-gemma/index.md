author: Sasha Denisov
summary: Getting Started with On-Device LLMs in Flutter
id: getting-started-flutter-gemma
categories: flutter, ai, gemma
environments: android, ios
status: Published

# Getting Started with On-Device LLMs in Flutter

## Overview
Duration: 3

### What you'll build

A small Flutter chat app that downloads a language model once, then answers
questions with the network switched off. No API key, no server, no per-token
bill — the weights sit on the device and the tokens are generated there.

By the end you will have an app that:

* downloads a model file with a progress bar, and knows on the next launch
  that it already has it
* opens a chat session against that model
* streams the reply token by token, the way a chat app should
* cleans up after itself — both the native runtime and the half-gigabyte file

### What you'll learn

The mechanics are only a few dozen lines. What takes the time is the handful
of decisions the API asks you to make, and this codelab is built around them:

* why `flutter_gemma` refuses to run until you hand it an **engine**
* how a model's **file type** decides which runtime opens it
* why `maxTokens` is not the reply length, and what to use instead
* why the model's **file name is its id**, and what breaks when you forget

### What you'll need

* Flutter 3.44 or newer
* An Android device or emulator, or an iOS device — the same code runs on both
* About 1 GB of free space and a connection that can pull it
* Optionally, a free Hugging Face account (Step 2 explains when you need one)

### Get the code

Every step of this codelab exists as a complete, runnable app, so you can
join at any point or check your work against the next one.

```bash
git clone --depth 1 https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma/codelabs/getting-started-flutter-gemma
ls
```

```text
step_01_starter/     the shell you start from
step_02_download/    after Step 2
step_03_chat/        after Step 3
step_04_streaming/   after Step 4
complete/            the finished app
```

## Step 1: The starter app
Duration: 3

Open `step_01_starter` and run it.

```bash
cd step_01_starter
flutter run
```

You get a chat screen with the composer disabled and a line saying there is no
model yet. That is the whole app — one file, no plugin, nothing to configure:

```dart
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ... a disabled TextField and a send button that does nothing
  }
}
```

Starting from a plain Flutter app is deliberate. Everything that follows is an
addition you can see, and if something breaks you know which addition did it.

## Step 2: Add the plugin and download a model
Duration: 10

This is the longest step, and the only one with platform configuration in it.

### Add the two packages

```bash
flutter pub add flutter_gemma flutter_gemma_litertlm
```

Two packages, not one, and the reason matters.

`flutter_gemma` is the **core**: the install and runtime API, the chat loop,
the registry. It ships no inference runtime at all. `flutter_gemma_litertlm`
is one such runtime — the LiteRT-LM engine, which reads `.litertlm` files on
Android, iOS and desktop. There are others (MediaPipe for `.task`, ONNX
Runtime, the OS built-in models), and you take only the one you need, because
each drags in native binaries you would otherwise ship for nothing.

### Configure the platforms

Less than you would expect.

**Android** — one line, because downloading the model is an ordinary HTTPS
request:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
```

You do **not** need to declare the OpenCL libraries the GPU backend uses. The
plugin's own manifest declares them and the manifest merger folds them into
your app.

**iOS** — nothing. Flutter's default deployment target is already 15.0, which
is what the plugin needs.

That is the whole platform setup. The plugin also runs on macOS, Windows and
Linux, but a desktop app needs one extra build-phase step to stage the
runtime's companion libraries — out of scope here, and covered in the
[desktop docs](https://fluttergemma.dev/docs/desktop).

### Register the engine

Engines are fully opt-in. The core registers none, so an app that never says
which runtime it wants gets a `StateError` on its first model call telling it
to add an engine package. Wire it up in `main`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
  );

  runApp(const QuickstartApp());
}
```

### Choose a model

Put the model's identity in one place. The file name is not decoration — it is
the id the plugin installs under and the id you ask about later:

```dart
abstract final class Models {
  static const gemma3 = ModelChoice(
    label: 'Gemma 3 1B',
    url: 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
        'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    fileName: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    modelType: ModelType.gemmaIt,
    sizeLabel: '0.5 GB',
    requiresToken: true,
  );

  static const qwen3 = ModelChoice(
    label: 'Qwen3 0.6B',
    url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
        'Qwen3-0.6B.litertlm',
    fileName: 'Qwen3-0.6B.litertlm',
    modelType: ModelType.qwen3,
    sizeLabel: '0.6 GB',
    requiresToken: false,
  );
}
```

Gemma's repository is behind a licence gate: open the
[model page](https://huggingface.co/litert-community/Gemma3-1B-IT), accept the
terms once, then create a read token in your Hugging Face settings and pass it
at run time:

```bash
flutter run --dart-define=HF_TOKEN=hf_your_token
```

**No Hugging Face account, or in a hurry?** Switch the app's one `_model`
constant to `Models.qwen3`. That repository is ungated, so it downloads with no
token at all, and every other line of this codelab stays the same. Swapping
models really is a one-line change.

A token belongs on the command line, never in source control. `String.fromEnvironment` reads it at compile time and the value never enters a file you might commit. The plugin attaches it **only** to `huggingface.co` URLs, so a token set once can't leak to some other host you download from later.

### Download it

```dart
await FlutterGemma.installModel(
      modelType: widget.model.modelType,
      fileType: ModelFileType.litertlm,
    )
    .fromNetwork(widget.model.url)
    .withProgress((percent) {
      if (mounted) setState(() => _percent = percent);
    })
    .install();
```

The two arguments to `installModel` answer different questions. `modelType`
says **what the model is**, which decides the chat template wrapped around
your messages. `fileType` says **which runtime reads the file**, and it is the
line people forget: it defaults to `task`, which routes to MediaPipe. Hand a
`.litertlm` file to that default and the install lands somewhere the LiteRT-LM
engine never looks.

`withProgress` reports whole percent, 0 to 100.

Run it. You should watch the bar fill and land on the placeholder screen.
Compare against `step_02_download` if it doesn't.

## Step 3: Your first reply
Duration: 6

Two objects stand between you and an answer.

```dart
final inference = await FlutterGemma.getActiveModel(maxTokens: 1024);
final chat = await inference.createChat(
  modelType: widget.model.modelType,
  maxOutputTokens: 256,
);
```

`getActiveModel` loads the installed weights into a runtime. `createChat` opens
a conversation on top, and it is the chat that remembers what was said.

**`maxTokens` is the context window**, not a cap on the answer's length — the
prompt, the history and the reply all share it. Set it to 100 hoping for a
short reply and you get a model that cannot even fit your question. To limit
the answer, use `maxOutputTokens` on the chat, as above.

Sending a message is two calls — add it, then ask:

```dart
await chat.addQueryChunk(Message.text(text: text, isUser: true));
final response = await chat.generateChatResponse();
```

**`Message` defaults `isUser` to `false`.** Leave it out and you have appended
something the model reads as its own previous turn — the reply comes back empty
or bizarre, with no error anywhere.

The result is a sealed `ModelResponse`, because a model can answer with plain
text, with a tool call, or with its own thinking. A first chat only needs the
text arm, but the switch makes the other cases visible for later:

```dart
switch (response) {
  TextResponse(:final token) => token,
  ThinkingResponse() => '(thinking)',
  _ => '(unsupported response)',
}
```

Finally, close what you opened. The runtime holds native memory that Dart's
garbage collector knows nothing about:

```dart
@override
void dispose() {
  _inference?.close();
  _input.dispose();
  super.dispose();
}
```

Run it and ask something. The app freezes for a few seconds, then the whole
answer appears at once. That pause is the next step.

## Step 4: Stream the reply
Duration: 4

The model produces the answer one piece at a time; waiting for all of it before
drawing anything throws that away. Swap one call for its streaming twin:

```dart
final buffer = StringBuffer();
await for (final chunk in chat.generateChatResponseAsync()) {
  if (chunk is TextResponse) {
    buffer.write(chunk.token);
    setState(() => _turns[_turns.length - 1] =
        _Turn(buffer.toString(), fromUser: false));
  }
}
```

**Each `TextResponse` carries only the new text**, not the reply so far. Assign
it instead of appending and you render only the last fragment — a bug that
looks like the model emitting a single word.

Add the empty assistant turn *before* the loop starts, so there is something
on screen for the tokens to flow into.

Run it again. Same model, same answer, and the app now feels like it is
thinking out loud instead of hanging.

## Step 5: Install once, not every launch
Duration: 4

The app still asks for the model every cold start. The fix is one question,
asked before deciding what to show:

```dart
Future<bool> _check() => FlutterGemma.isModelInstalled(widget.model.fileName);
```

That is why the file name lives in a constant. `isModelInstalled` is keyed by
the name the model was installed under — get it out of step with the URL and
the check quietly answers "no" forever, and your app re-downloads half a
gigabyte on every launch while looking like it works.

`complete` guards exactly that with a test, because it is invisible when wrong:

```dart
test('every model id matches the last segment of its URL', () {
  for (final model in [Models.gemma3, Models.qwen3]) {
    expect(model.fileName, model.url.split('/').last, reason: model.label);
  }
});
```

**Try killing the app mid-download and starting it again.** The download picks
up where it stopped rather than starting over: the plugin derives a stable id
for the transfer from the model's identity, so it can find its own partial file
after a restart.

To watch the whole cycle, `complete` adds a delete button:

```dart
Future<void> _removeModel() async {
  await _inference?.close();
  _inference = null;
  _chat = null;
  await FlutterGemma.uninstallModel(widget.model.fileName);
  if (mounted) widget.onModelRemoved();
}
```

Close the runtime *before* deleting the file. The weights are memory-mapped
while a model is open, and pulling the file out from under the engine is a
crash waiting to happen.

## What's next
Duration: 2

You have an app that runs a language model with the network off. The same
core API is the entry point to everything else the plugin does:

* **swap the model** — change one constant; `.litertlm` files from
  [litert-community](https://huggingface.co/litert-community) all work the same way
* **send images and audio** — `Message.withImages`, on models that accept them
* **let the model call your Dart functions** — tools and the call/response loop
* **ground answers in your own documents** — embeddings and on-device vector search
* **run it as a voice loop** — speech-to-text in, text-to-speech out

Each has its own codelab in the [catalogue](https://fluttergemma.dev/codelabs).

### Reference

* [flutter_gemma on pub.dev](https://pub.dev/packages/flutter_gemma)
* [Documentation](https://fluttergemma.dev/docs/getting-started)
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
