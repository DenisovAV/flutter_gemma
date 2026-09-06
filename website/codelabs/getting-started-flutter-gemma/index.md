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
* says what went wrong when something does, instead of freezing
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
complete/            after Step 5 — the finished app
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
Duration: 12

This is the longest step, and the only one with platform configuration in it.

### Add the two packages

```bash
flutter pub add flutter_gemma flutter_gemma_litertlm
```

Two packages, not one, and the reason matters.

`flutter_gemma` is the **core**: the install and runtime API, the chat loop,
the registry. It ships no inference runtime at all. `flutter_gemma_litertlm`
is one such runtime — the LiteRT-LM engine, which reads `.litertlm` files on
Android, iOS, desktop and the web. There are others (MediaPipe for `.task`, ONNX
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

**iOS** — the deployment target is already right: Flutter's default is 15.0,
which is what the plugin needs. What you do have to add is three memory
entitlements, in `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.kernel.extended-virtual-addressing</key>
	<true/>
	<key>com.apple.developer.kernel.increased-memory-limit</key>
	<true/>
	<key>com.apple.developer.kernel.increased-debugging-memory-limit</key>
	<true/>
</dict>
</plist>
```

…and point the Runner target at it, which is what Xcode's **Signing &
Capabilities** editor writes for you (`CODE_SIGN_ENTITLEMENTS =
Runner/Runner.entitlements;` in each of the target's Debug, Release and Profile
configurations). The step apps from Step 2 onwards already carry all three.

These lift the per-process memory ceiling iOS imposes. Half a gigabyte of
weights plus a KV cache is comfortably over the default jetsam limit on an
older iPhone, and the kill that follows has no Dart-visible error — the app
simply disappears. The third key is the second one's debug twin: it is the one
that applies while a debugger is attached, which is every `flutter run` this
codelab asks you to do, so leaving it out costs you exactly the runs you are
about to make.

That is the whole platform setup. The plugin also runs on macOS, Windows and
Linux; only **macOS** needs an extra build-phase step — a `post_install` block
in `macos/Podfile` that stages the runtime's companion libraries. On macOS
these entitlements need a signing team and are not needed for a model this
size. Both are out of scope here, and covered in the
[desktop docs](/docs/desktop).

### Register the engine

Engines are fully opt-in. The core registers none, so an app that never says
which runtime it wants gets a `StateError` the first time it calls
`getActiveModel()`, telling it to add an engine package. (Installing a model
works without one — nothing has to open the file to write it.) Wire it up in
`main`:

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
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
        'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    fileName: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    modelType: ModelType.gemmaIt,
    sizeLabel: '0.5 GB',
    requiresToken: true,
  );

  static const qwen3 = ModelChoice(
    label: 'Qwen3 0.6B',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
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

A token belongs on the command line, never in source control. `String.fromEnvironment` reads it at compile time and the value never enters a file you might commit. The plugin attaches it only to URLs whose host contains `huggingface.co`, so a token set once does not ride along to the other hosts your app downloads from. (That test is a substring match, so treat it as a convenience rather than a security boundary.)

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
line people forget: it defaults to `task`, which routes to MediaPipe.

It is not about where the bytes land — they land in the same place either way.
`fileType` is what the registry matches engines against: it asks each
registered engine's `canHandle` about the file type the model was *declared*
with, so a `.litertlm` model installed under the `task` default is offered to
MediaPipe, which cannot open it, and never to LiteRT-LM. The download succeeds
and the failure arrives later, out of `getActiveModel()`, as the same
`StateError` you get for a missing engine package: *No inference engine can
handle this model (ModelFileType.task).*

`withProgress` reports whole percent, 0 to 100.

Run it. You should watch the bar fill and land on the placeholder screen.
Compare against `step_02_download` if it doesn't.

Which screen you land on is not luck: `main.dart` asks
`FlutterGemma.isModelInstalled` before it decides what to show. That gate is
already doing its job — Step 5 comes back to it, because that one question is
the difference between downloading the model once and downloading it on every
launch.

## Step 3: Your first reply
Duration: 7

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
prompt, the history and the reply all share it. Ask for 100 hoping for a short
reply and you do not get a short reply: the LiteRT-LM engine raises the value
back to 1024 — the smallest context a `.litertlm` model's baked KV cache can be
built for — and logs that it did. The setting is corrected, not honoured, so it
achieves nothing at all. To cap the answer, use `maxOutputTokens` on the chat,
as above, and leave `maxTokens` big enough for prompt + history + reply.

Sending a message is two calls — add it, then ask:

```dart
await chat.addQueryChunk(Message.text(text: text, isUser: true));
final response = await chat.generateChatResponse();
```

**`Message` defaults `isUser` to `false`.** Leave it out and you have appended
something the model reads as its own previous turn — the reply comes back empty
or bizarre, with no error anywhere.

The result is a sealed `ModelResponse`, because a model can answer with plain
text, with a tool call, or with its own thinking. With no tools declared this
call only ever hands back the text arm, so one `switch` covers it and leaves
the door open for later:

```dart
_turns.add(
  _Turn(switch (response) {
    TextResponse(:final token) => token,
    _ => '(unsupported response)',
  }, fromUser: false),
);
```

### When it fails

This is the first code in the app that talks to a native runtime, so it is the
first code that can fail for reasons no `pub get` catches: a forgotten engine
package, an out-of-memory kill on a small phone, a half-written model file.
Both entry points get a `catch` — and `_send` gets a `finally`:

```dart
} catch (error) {
  if (mounted) setState(() => _loadError = error);
}
```

```dart
} catch (error) {
  // The chat's own history now holds a user turn the model never answered;
  // a production app would reset it with `clearHistory`.
  if (mounted) {
    setState(() => _turns.add(_Turn('⚠️ $error', fromUser: false)));
  }
} finally {
  // `_busy` is what disables the composer, so clearing it belongs in
  // `finally` — a failed generation must not lock the app.
  if (mounted) setState(() => _busy = false);
}
```

The `finally` is the part that matters. `_busy` is what greys out the text
field and the send button, and it is set *before* the call. Clear it only on
the success path and one failed generation disables the composer for the life
of the screen — the app looks alive and accepts nothing, and there is no error
on screen to explain it. Anything that can throw between "disable the UI" and
"enable it again" belongs in a `try`, with the re-enable in `finally`.

`_load`'s failure gets a message and a **Try again** button in place of the
loading bar, because "the model would not open" is a state the user can act on.

One honest limitation, noted in the `catch`: `addQueryChunk` commits your
message to the chat's history before generation runs, so a failed turn leaves a
user message the model never answered — in the Dart-side history and in the
native session both. The chat still works; every later turn is just asked of a
transcript with a hole in it. An app that cares would call
`chat.clearHistory(replayHistory: …)` there. This one keeps the screen simple.

Finally, close what you opened. The runtime holds native memory that Dart's
garbage collector knows nothing about:

```dart
@override
void dispose() {
  _inference?.close().catchError((Object _) {});
  _input.dispose();
  super.dispose();
}
```

`dispose` cannot `await`, so the future is dropped deliberately — and caught,
because an unawaited throw from a native teardown surfaces as an unhandled
async error with no useful stack.

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
    if (!mounted) return;
    setState(
      () => _turns[_turns.length - 1] = _Turn(
        buffer.toString(),
        fromUser: false,
      ),
    );
  }
}
```

**Each `TextResponse` carries only the new text**, not the reply so far. Assign
it instead of appending and you render only the last fragment — a bug that
looks like the model emitting a single word.

The `if (!mounted) return;` is not decoration either: generation outlives the
screen if the user backs out mid-reply, and `setState` on a disposed `State`
throws. The `finally` from Step 3 still runs on that early return, and skips
its own `setState` for the same reason.

Add the empty assistant turn *before* the loop starts, so there is something
on screen for the tokens to flow into.

Run it again. Same model, same answer, and the app now feels like it is
thinking out loud instead of hanging.

## Step 5: Install once, not every launch
Duration: 4

The gate that keeps the app from re-downloading half a gigabyte has been there
since Step 2 — one question, asked before deciding what to show:

```dart
Future<bool> _check() => FlutterGemma.isModelInstalled(widget.model.fileName);
```

What `complete` adds is one thing: a delete button, so you can make that
question answer "no" again on demand. This step is where the rest of the story
around that single line gets told — why the id has to be exactly right, and
what does and does not survive a restart.

That one line is why the file name lives in a constant. `isModelInstalled` is
keyed by the name the model was installed under — get it out of step with the
URL and the check quietly answers "no" forever, and your app re-downloads half
a gigabyte on every launch while looking like it works. It is also why the
model's file name in `Models` is exactly the last segment of its URL, which is
what the plugin derives the installed name from — one typo apart and the check
is answering about a file that was never written.

Every step directory has carried a test for that since Step 2, because it is
the kind of mistake that is invisible when it is wrong:

```dart
test('every model id matches the last segment of its URL', () {
  for (final model in [Models.gemma3, Models.qwen3]) {
    expect(model.fileName, model.url.split('/').last, reason: model.label);
  }
});
```

**What survives a cold start is the decision, not the bytes.** Kill the app
mid-download and relaunch: the gate asks again, sees no installed model, and
starts over from zero. That is deliberate. Hugging Face serves *weak* ETags, so
the plugin sets `allowPause: false` for `huggingface.co` URLs — byte-range
resume against a server that cannot promise the range still matches is worse
than a clean restart. A model hosted on GCS, Firebase Storage, Kaggle or your
own server does resume. It is worth knowing which of those you are on before
you promise your users a resumable download.

The corollary bites on Android: because a Hugging Face transfer cannot pause,
one that runs past WorkManager's nine-minute execution cap fails outright
instead of pausing and re-enqueuing. On a slow connection a 0.5 GB model can
hit that, and the fix is a faster network or a host that supports resume — not
a retry loop.

To watch the whole cycle, `complete` adds a delete button:

```dart
Future<void> _removeModel() async {
  try {
    await _inference?.close();
    // Inside `setState`: dropping the chat has to repaint, or the screen
    // keeps showing an enabled composer over a runtime that is gone.
    if (mounted) {
      setState(() {
        _inference = null;
        _chat = null;
      });
    }
    await FlutterGemma.uninstallModel(widget.model.fileName);
    if (mounted) widget.onModelRemoved();
  } catch (error) {
    // Deleting can fail too — a missing install record, a file the OS still
    // holds. Show it the way a failed load is shown.
    if (mounted) setState(() => _loadError = error);
  }
}
```

Close the runtime *before* deleting the file. The weights are memory-mapped
while a model is open, and pulling the file out from under the engine is a
crash waiting to happen. For the same reason the button is disabled while the
model is still opening — there is no runtime to close yet, and `getActiveModel`
is holding the file open behind the progress bar.

The `try` and the `setState` are the same lesson as Step 3, one screen over.
`uninstallModel` throws if the install record is already gone, and without the
`catch` that exception escapes into the zone: `onModelRemoved` never fires, the
gate never re-runs, and the page you are looking at still paints an enabled
composer over a chat that no longer exists. Nulling the fields outside
`setState` gets you the same painted lie more cheaply.

Delete it, and the gate flips back to the download screen on the next check —
which is the cheapest way to test the gate itself.

## What's next
Duration: 2

You have an app that runs a language model with the network off. The same
core API is the entry point to everything else the plugin does:

* **swap the model** — change one constant; `.litertlm` files from
  [litert-community](https://huggingface.co/litert-community) all work the same way
* **run a different engine** — the OS built-in model (Gemini Nano, Apple
  Foundation Models) needs no download at all
* **send images and audio** — `Message.withImages`, on models that accept them
* **let the model call your Dart functions** — tools and the call/response loop
* **ground answers in your own documents** — embeddings and on-device vector search
* **run it as a voice loop** — speech-to-text in, text-to-speech out

Most of these have a codelab in the [catalogue](/codelabs) — some published,
some still being written.

### Reference

* [flutter_gemma on pub.dev](https://pub.dev/packages/flutter_gemma)
* [Documentation](/docs/getting-started)
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
