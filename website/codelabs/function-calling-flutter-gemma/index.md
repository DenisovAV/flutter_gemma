author: Sasha Denisov
summary: Function Calling with On-Device Models in Flutter
id: function-calling-flutter-gemma
categories: flutter, ai, gemma, function-calling
environments: android, ios, macos, windows, linux, web
status: Published

# Function Calling with On-Device Models in Flutter

## Overview
Duration: 3

### What you'll build

A chat app taught to hand work to your own Dart functions — and then, at the
end, taught to run on a model you fine-tuned yourself.

It begins the way the other codelabs here begin — download a model, stream a
reply — but on the model this one is about. Three models, in fact, and the
order is the argument. The starter chats with **FunctionGemma 270M**: 284 MB,
ungated, and a model whose entire job is calling functions, so Step 2 has it
running your Dart before you have finished reading the page. Step 4 fine-tunes
that same 270M model on the three tools this codelab declares and produces a
`.litertlm` you open from disk. Step 5 pays **2.59 GB** for **Gemma 4 E2B**,
for the thing a 270M model cannot do at all: reason out loud before it chooses
which function to call. It also declares its tools by a different route, which
is where `toolChoice` stops behaving the way its three names suggest.

That is the idea worth taking away:

**A tool is a declaration plus a function, and the model never runs anything.**
It can only ask. Your app decides what `multiply` means, runs it, and sends
back a map — and that map is the model's entire knowledge of what happened.
Nothing about the weights changes, nothing is downloaded, and the model has no
way to reach your code except by asking for it by name.

Which makes the second idea the one that actually bites. **Function calling is
not a request, it is a loop.** The model answers, or it asks; if it asks you
run something and answer *it*, and then it generates again — and it may ask
again. A turn is not one generation, it is however many the model needs, and
something has to decide when that stops. Step 2 writes that loop by hand so you
can see every exit it has. Step 3 deletes it and calls the one the SDK ships,
which has three exits the hand-written version did not.

And the third: what a call is *committed* to. The moment the SDK hands you a
`FunctionCallResponse`, that call is already in the chat's history. Leave it
without a reply — because the user cancelled, because your tool threw, because
the stream errored — and the next message on that chat is poisoned: the model
re-issues the call, or answers nothing. Every exit path has to answer every
call. That is the rule the loop in Step 3 exists to keep.

### What you'll learn

* what a `Tool` declaration is, what it is not, and why the description is the
  only thing telling the model *when* to call
* how a call arrives — `FunctionCallResponse` on the same stream as the text —
  and how a result goes back, as `Message.toolResponse`
* how to drive the loop by hand, and then how to hand it to
  `generateChatResponseWithTools` with `maxToolTurns` as the stop condition
* why every committed call must be answered on every exit path, including the
  ones you did not plan for
* what `toolChoice` actually changes — and, on both models here, what it does
  not: neither can be forced to call, for two different reasons
* how to fine-tune a 270M model on your own tools with **litetune**, convert it
  to `.litertlm`, and measure what the conversion cost
* that a model you tuned loads through the same API as one you downloaded —
  not one line of Dart changes

### What you'll need

* Flutter 3.44 or newer, and any one of Flutter's six platforms to run on: an
  Android device or emulator, an iOS device or simulator, an Apple-silicon Mac,
  a Windows or Linux desktop, or Chrome. `step_01_starter/` is a whole app, not
  a diff against another codelab — clone the repo and run it
* **No Hugging Face token to run the app**, in any step. The two repositories
  it downloads from — `sasha-denisov/function-gemma-270M-it` and
  `litert-community/gemma-4-E2B-it-litert-lm` — are ungated, so every
  `flutter run` here is a plain `flutter run` with no `--dart-define`
* Room for **284 MB** — one download, shared by Steps 1, 2 and 3 — and for
  **2.59 GB** more in Step 5, plus the memory to open the larger one, roughly
  6 GB of RAM. A 4 GB phone is killed by the OS rather than told no
* Step 4 is optional and costs CPU time instead of megabytes: **Linux or
  macOS**, Python 3.10–3.12, and about 2.2 GB of cached Python environments.
  It is the one part of this codelab that *does* need a Hugging Face token,
  because the base checkpoint it fine-tunes is gated and the approval is
  manual — **request access before you start it**, see that step's own
  prerequisites. Skip it and the app works on the stock models

### Get the code

```bash
git clone --depth 1 https://github.com/DenisovAV/flutter_gemma.git
cd flutter_gemma/codelabs/function-calling-flutter-gemma
ls
```

```text
step_01_starter/     a plain chat on FunctionGemma — no tools yet
step_02_one_tool/    after Step 2 — one tool, the loop written out
step_03_the_loop/    after Step 3 — the same tools, the SDK's loop
step_04_finetune/    NOT an app: the data and commands for a litetune run
complete/            after Step 5 — three tools, toolChoice, thinking
```

`step_04_finetune` has no `pubspec.yaml` on purpose. Its output is a model, not
code.

## Step 1: What a tool call actually is
Duration: 6

### Run the starter

Open `step_01_starter` and run it. It is the same shape of app the other
codelabs here start from — download a `.litertlm`, stream the reply, in text —
on the model this one is about: **FunctionGemma 270M**, 284 MB, from an ungated
repository, so there is no token to get and no `--dart-define` to remember.

Nothing in it knows about tools yet, and that is the point of starting here:
everything Step 2 adds is visible as a diff against this.

One thing in `main.dart` is worth seeing before you go on — the call that runs
before the first frame is guarded:

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
— and an `await` before `runApp` that throws never reaches `runApp` at all.

Now look at the call that opens the chat, because that is where this codelab's
change lands:

```dart
      final chat = await inference.createChat(
        modelType: widget.model.modelType,
        maxOutputTokens: 256,
      );
```

### Three things, and only one of them is code

A tool the model can call is made of three parts, and it helps to name them
before any of them appear on screen.

**The declaration** is a `Tool`: a name, a description, and a JSON Schema for
the arguments. It holds no code and it cannot run. The SDK renders it into the
prompt; the model reads it and nothing else. The description is not a comment —
it is the only thing that tells the model *when* this is the right function.

**The call** is a `FunctionCallResponse`, and it arrives on the same stream as
the text. `generateChatResponseAsync` yields `ModelResponse`, which is a sealed
type: a `TextResponse` is a token of the answer, a `FunctionCallResponse` is
the model asking for `name(args)`. One turn can be either, or both.

**The answer** is a `Message.toolResponse`, staged with `addQueryChunk` like
any other message. Until it reaches the session the model has not seen your
result — a tool is not a function the model called, it is a question it asked
and you replied to.

### What the model cannot do

It cannot run your code, it cannot see your code, and it cannot find out
whether the function exists. It writes a name and some arguments, and if that
name is one you never declared, you get a call for a function that is not
there. Answering that with an error map is the app working correctly; throwing
is the app losing the conversation.

It also cannot be relied on for the thing this codelab uses as its example. Ask
a 270M model for 1234 × 5678 and you get a confident number of about the right
length. The point of the tool is not that the model is bad at arithmetic — it
is that you can check the answer without a network, without a service, and
without trusting anything.

## Step 2: One tool, and the loop by hand
Duration: 11

### One field on the model you already have

`step_02_one_tool` downloads nothing new. `main.dart`, `model.dart` and
`download_page.dart` are byte for byte the starter's, and everything this step
adds is a new `lib/tools.dart` and the chat page. Which makes one field in
`model.dart` worth reading before the tools arrive, because it is the field
that decides whether any of them work:

```dart
  /// A 270M model whose whole job is function calling.
  ///
  /// 284 MB — small enough to download while you read this page, and small
  /// enough that it does very little else: ask it a general question and the
  /// answer will be thin. That is the trade this step is making on purpose.
  /// Calling a function is a narrow skill, and a model specialised for it can
  /// be a fraction of the size of one that also has to hold a conversation.
  static const functionGemma = ModelChoice(
    label: 'FunctionGemma 270M',
    url:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/'
        'resolve/main/functiongemma-270M-it.litertlm',
    fileName: 'functiongemma-270M-it.litertlm',
    modelType: ModelType.functionGemma,
    sizeLabel: '284 MB',
  );
```

`ModelType.functionGemma` is the line to pause on. It selects the format the
SDK writes *and* reads: the declarations go into a developer turn these weights
were trained on, and `<start_function_call>call:multiply{…}` is parsed back
into a `FunctionCallResponse`. Name a different family and the SDK writes a
prompt the model never saw and waits for a syntax it never emits — every turn
comes back as plain text and nothing says why.

### Declare the function

A new file, `lib/tools.dart`:

```dart
const multiplyTool = Tool(
  name: 'multiply',
  // The model reads this. It is the only thing telling it WHEN to call — so
  // "use this instead of working it out yourself" is instruction, not prose.
  description:
      'Multiply two numbers and return the exact product. Use this for any '
      'multiplication instead of working it out yourself.',
  parameters: {
    'type': 'object',
    'properties': {
      'a': {'type': 'number', 'description': 'The first number.'},
      'b': {'type': 'number', 'description': 'The second number.'},
    },
    'required': ['a', 'b'],
  },
);
```

Nothing there runs. The half that does is a plain Dart function:

```dart
Map<String, dynamic> runMultiply(Map<String, dynamic> args) {
  final a = asNumber(args['a']);
  final b = asNumber(args['b']);
  if (a == null || b == null) {
    // Returned, not thrown. A model wrote these arguments and a model can
    // write nonsense; an error map is a turn it can read and correct on the
    // next one, while an exception ends the conversation and takes the
    // committed call with it.
    return {
      'error':
          'multiply needs two numbers. Got a=${args['a']}, b=${args['b']}.',
    };
  }
  final product = a * b;
  // `12 * 13` arriving as doubles comes back as `156.0`, and the model has to
  // read that number out loud. Say 156.
  return {
    'result': product is double && product == product.truncateToDouble()
        ? product.toInt()
        : product,
  };
}
```

Two details there earn their lines. The arguments are whatever JSON the model
produced — FunctionGemma is trained to emit them as strings, so `"12"` is the
ordinary case and `12` and `12.0` are the others:

```dart
num? asNumber(Object? value) => switch (value) {
  final num n => n,
  final String s => num.tryParse(s.trim()),
  _ => null,
};
```

And a bad call is *answered*, not thrown. Everything `runMultiply` returns
becomes the model's only knowledge of what happened; an exception instead ends
the turn and leaves a call in the history that nothing replied to.

### Open a session that has tools

Two arguments on `createChat`:

```dart
      final chat = await inference.createChat(
        // Which family's call syntax the SDK writes and reads. With
        // `ModelType.functionGemma` it renders the declarations into a
        // developer turn these weights were trained on, and parses
        // `<start_function_call>call:multiply{…}` back into the
        // `FunctionCallResponse` the loop below waits for.
        modelType: widget.model.modelType,
        // The declarations. This is the whole of "the model can call your
        // code": a list of names, descriptions and argument schemas.
        tools: const [multiplyTool],
        // And the switch that turns the machinery on. `tools` without this is
        // the quiet failure worth knowing about: `InferenceChat` logs
        // "Model does not support function calls, but tools were provided.
        // Tools will be ignored", never renders the declarations, and the
        // model answers every question out of its own head — fluently, and
        // with arithmetic it made up.
        supportsFunctionCalls: true,
        maxOutputTokens: 256,
      );
```

Note what the call *above* it does not take. If you came from the multimodal
codelab you will be looking for the second place to set the flag — the trap
where `supportImage` has to go on `getActiveModel` as well or native fails the
turn. There is no second place here:

```dart
      final inference = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.cpu,
      );
```

`getActiveModel` builds the engine, and nothing about the engine changes when
you declare a function. Tools belong to the session.

The two arguments it *does* take are worth a moment. `maxTokens: 1024` is what
this checkpoint is built for. The CPU backend is a workaround for **this file**,
and the distinction matters more than the workaround does.

The `.litertlm` you just downloaded was converted before litetune began setting
`prefer_activation_type=fp32`. Without that key the GPU path answers every
prompt with `<pad>` repeated to the token limit — measured on Android and on
macOS Metal alike, with no exception, no warning, and a chat that looks alive
while it returns filler. On CPU the same weights ask for `multiply` correctly.

So this is not "FunctionGemma needs a CPU", and it is not a platform bug. It is
one published artifact carrying a conversion setting that predates the fix. Step
4 converts the model again with a current litetune, and that artifact scores the
same on GPU as on CPU and runs about 1.5× faster — which is a fair summary of
what the fine-tuning step buys you even before you change a single training
row.

What changes with tools is not the number but what has to fit under it: the
declarations are rendered into the prompt once and stay in the history for the
rest of the conversation, and every call and every tool response is another
turn inside the same 1024 — so a tool-calling chat runs out of room sooner than
a plain one does.

### The loop, written out

This is the part worth reading once. One message, three questions asked in
order:

```dart
      await chat.addQueryChunk(Message.text(text: text, isUser: true));

      // ROUND ONE. The model either answers, or asks for the function.
      final calls = await _generate(chat);
      if (calls.isEmpty) return; // a plain answer — nothing to run

      // The app runs it. This half is never the SDK's: a tool is an action in
      // your program, and only your program knows what `multiply` means.
      for (final call in calls) {
        final result = _run(call);
        if (mounted) {
          setState(() {
            _turns
              ..add(_Turn(_describeCall(call), kind: _TurnKind.toolCall))
              ..add(_Turn(jsonEncode(result), kind: _TurnKind.toolResult));
          });
        }
        // Handing the answer back is a MESSAGE, not a return value. Until this
        // reaches the session the model has not seen the number at all.
        await chat.addQueryChunk(
          Message.toolResponse(toolName: call.name, response: result),
        );
      }

      // ROUND TWO. Same session, same history — now with the result in it.
      final again = await _generate(chat);
      if (again.isEmpty) return;
```

`_generate` is one generation. The text and the calls arrive on the same
stream, so it collects both:

```dart
    await for (final chunk in chat.generateChatResponseAsync()) {
      switch (chunk) {
        case TextResponse(:final token):
          // Each TextResponse carries only the NEW text, not the whole reply
          // so far — append, never replace.
          buffer.write(token);
          // Guarded rather than returned: a call this stream has already
          // yielded is committed to the chat's history and still has to be
          // answered, so the loop keeps draining even with no screen to paint.
          if (mounted) {
            setState(
              () =>
                  _turns[at] = _Turn(buffer.toString(), kind: _TurnKind.model),
            );
          }
        case FunctionCallResponse():
          pending.add(chunk);
        case ParallelFunctionCallResponse(:final calls):
          // One turn, several calls. FunctionGemma with a single declared tool
          // will rarely do this, but the case exists and dropping it would
          // leave committed calls unanswered.
          pending.addAll(calls);
        case ThinkingResponse():
          // Filtered out upstream unless the chat was opened with
          // `isThinking: true` — `complete` does exactly that. Here the branch
          // exists so the switch stays exhaustive.
          break;
      }
    }
```

The switch is exhaustive over the sealed `ModelResponse` on purpose. Write it
as `if (chunk is TextResponse)` and a case the SDK adds later becomes silence
in your app rather than a compile error.

### The rule this loop is already keeping

Round two can come back with *another* call. This app runs one round and stops
— but it still answers what it will not run:

```dart
      // The model asked for another call. Every call the stream yielded is
      // ALREADY in the chat's history, and a call left without a response
      // poisons the next turn on this chat — the model re-issues it, or
      // answers nothing at all. So the ones this step will not run still get
      // an answer, and it says what happened.
```

That is the invariant to carry into Step 3. A `FunctionCallResponse` is
committed to the persistent history *at the moment it is yielded* — before your
code has seen it — so every call needs a reply on every path out, not only the
happy one.

### Run it

Run `step_02_one_tool` and ask *what is 1234 times 5678?* The transcript shows
four lines: your question, `multiply(a: 1234, b: 5678)`, `{"result":7006652}`,
and the model reading that number back. Check it on a calculator — that is the
point of choosing arithmetic.

Then ask it something with no tool in it, like *hello*. One round, no calls,
and a thin little answer: this is a 270M model, and conversation is not what it
is for.

## Step 3: Hand the loop to the SDK
Duration: 8

Everything in Step 2's `_send` past `addQueryChunk` is the same in every
tool-calling app ever written, and it has more edges than it looks. So the SDK
ships it:

```dart
      await for (final chunk in chat.generateChatResponseWithTools(
        // Run the function. Returning the map is what feeds the model; the
        // SDK wraps it in `Message.toolResponse` and stages it before the
        // next generation.
        onToolCall: _onToolCall,
        maxToolTurns: _maxToolTurns,
        // Called once, if the loop runs out of turns with calls still coming.
        // Without it the reply is quietly empty or half-written and nothing
        // says the cap is why.
        onMaxToolTurns: () => hitCap = true,
      )) {
```

The whole of your half is now the callback:

```dart
  Future<Map<String, dynamic>> _onToolCall(FunctionCallResponse call) async {
    final result = _run(call);
```

Staging your message is still yours. The loop drives generation; it does not
send your turn for you, exactly as `generateChatResponseAsync` does not:

```dart
      await chat.addQueryChunk(Message.text(text: text, isUser: true));
```

### The stop condition

```dart
const _maxToolTurns = 4;
```

The loop ends when a generation comes back with no calls in it — which is a
promise about the model, not about the code. A model that keeps asking would
run until the context window filled, so `maxToolTurns` is the cap, and hitting
it is reported rather than swallowed:

```dart
      if (hitCap && mounted) {
        setState(
          () => _notice =
              'The model was still asking for tools after $_maxToolTurns '
              'turns, so the loop stopped. The answer above may be missing '
              'or cut short.',
        );
      }
```

A cap below 1 throws a `RangeError`, deliberately. Zero turns would answer the
message you just staged with nothing at all and close the stream, which on
screen is indistinguishable from a model that had nothing to say — so the SDK
refuses instead of producing a silent no-op.

### What you got that you did not write

The happy path in Step 2 was correct. Three others were not there at all, and
each of them is a committed call that would have been left dangling:

* **the turn was cancelled** — the loop answers every collected call with
  `{'status': 'cancelled'}` before returning, so the history is balanced and
  the tools' side effects never run
* **your tool threw** — the failed call is answered with `{'error': …}`, the
  siblings in that turn are answered as not run, and the exception is
  *rethrown* so you still see it
* **the generation stream errored mid-turn** — the calls it had already yielded
  are answered before the original error is rethrown

All three balance the history before they return, and that is what leaves the
chat usable for the next message — with one exception the SDK states rather
than hides: if the session is already too broken to accept the balancing feed
itself, it logs that the history may be left unbalanced and that the recovery
is to recreate the session. All three would have taken another twenty lines in
`_send`, and you would only have found out you needed them from a conversation
that started answering nothing.

### Run it

Run `step_03_the_loop` and ask for something that chains: *12 times 12, then
that times 3*. Whether a 270M model plans two calls or stops after one is the
model's decision, not the loop's — a single call is what was measured here — and
either way the transcript shows each generation writing underneath the work it
was given, because the reply bubble is re-anchored every time a tool runs. If
it stops after one, that is the checkpoint's limit: the loop keeps going for as
long as calls keep coming, up to `_maxToolTurns`.

## Step 4: Fine-tune the model on your own tools
Duration: 14

This step is optional, it does not touch `lib/`, and its output is a file.

### Before you start: request access to the base model

Three of the five commands below name `google/functiongemma-270m-it` — as the
tokenizer, as the model to tune, and as the base to record in the bundle. That
repository is **gated, and the approval is manual**: an anonymous fetch of its
`config.json` returns `401`, and access is granted by a person rather than by
accepting a checkbox, so it can take hours or days.

So do this part first, not when you reach command 1:

1. Open [the model page](https://huggingface.co/google/functiongemma-270m-it)
   and request access.
2. When it is granted, `hf auth login` (or export `HF_TOKEN`).

Without it `prepare` fails on the tokenizer download and you never reach
`tune`. This is the only place in the codelab that needs a token — the
`.litertlm` the app itself downloads comes from the ungated
`sasha-denisov/function-gemma-270M-it`, and no step of the app asks you to log
in.

`step_04_finetune/` is not a Flutter app — it has no `pubspec.yaml`, so the
codelab gate does not analyze or build it. What it holds is the two inputs a
[litetune](https://github.com/DenisovAV/litetune) run needs, for the three
tools this codelab declares.

### What litetune is

It takes a Hugging Face checkpoint through LoRA fine-tuning, merges, exports to
`.litertlm`, and bundles the result with metadata — five commands, because each
stage fails differently and a single `run` would hide which one you are in.

**This is alpha software**, and its own statement of what has been measured is
worth quoting: *measured end to end on `google/functiongemma-270m-it` and
function calling only*. That is precisely the model and the task you have been
running since Step 2 — so this codelab is inside the one path the tool has
actually been measured on. Its other scorer and its other base models are not.

```bash
pip install litetune
```

**Linux or macOS**, Python 3.10–3.12. Python 3.13 runs `prepare`, `tune` and
`bundle` but not `convert` or `verify`: the export toolchain pins
`numpy==2.0.2`, and that stops publishing wheels after 3.12. Windows is
untried. On Linux you also need `libvulkan1` — `litert-lm` `dlopen()`s a
Vulkan-linked library even for the CPU backend, and without it every
invocation, `--help` included, dies in under a second:

```bash
sudo apt-get install -y libvulkan1     # Debian/Ubuntu
```

It runs on CPU, which is workable at 270M. Each stage builds and caches its own
environment, and they are not small: `convert` pulls about 1.6 GB and `tune`
588 MB. `litetune env` shows what is on disk, `litetune env --clean` removes
it. Colab works out of the box.

### Your data declares the task

One JSON object per line, and **the shape of the target is how you say what
kind of task this is**. An object with a `name` is a tool call:

```json
{"prompt": "set an alarm for 7", "target": {"name": "set_alarm", "args": {"hour": "7"}}}
```

A bare string is the answer itself, and that is `exact-text` rather than
function calling. Two shapes rather than a target plus a `--target-kind`,
because those two could disagree and a shape cannot disagree with itself. You
match it with `--scorer tool-call` at `verify`.

`step_04_finetune/raw.jsonl` is 72 rows in that shape, for `multiply`,
`get_current_time` and `get_device_info` — the three tools `complete/`
declares:

```json
{"prompt": "how much is 1234 * 5678?", "target": {"name": "multiply", "args": {"a": "1234", "b": "5678"}}}
```

Seventy-two rows are enough to run all five commands end to end and get a file
out. They are not enough to move a quality number: litetune's own published
figures come from thousands of examples, and `prepare` holds half of any file
back for scoring. Treat this run as a rehearsal of the pipeline and bring your
own data when you want a result.

### The five commands

Run them from `step_04_finetune/`.

```bash
# 1. Split, and reject rows that cannot be scored. Seconds.
litetune prepare --data raw.jsonl --output-dir data --context-length 1024 \
                 --tokenizer google/functiongemma-270m-it

# 2. Fine-tune. CPU is fine at this size.
litetune tune --model google/functiongemma-270m-it --data data/train.jsonl \
              --output-dir tuned --prompt-mode prerendered --method lora

# 3. Convert, sweeping recipes rather than trusting a default.
litetune convert --model tuned/model --output-dir artifacts \
                 --recipe dynamic_wi8_afp32 --recipe weight_only_wi8_afp32

# 4. Measure what the conversion cost, against the float twin.
#    `convert` names the artifact; look the filename up rather than build it.
litetune verify --model artifacts/weight_only_wi8_afp32/<name>.litertlm \
                --reference tuned/model --data data/heldout.jsonl \
                --json > manifest.json

# 5. Package the artifact with what was measured about it.
litetune bundle --output-dir bundle \
                --model artifacts/weight_only_wi8_afp32/<name>.litertlm \
                --declarations tools.json --prompt-mode prerendered \
                --base-model google/functiongemma-270m-it \
                --base-model-revision <commit-sha> \
                --adapter tuned/adapter \
                --train-metrics tuned/metrics.json \
                --verify-manifest manifest.json
```

Four of those flags decide something, and it is worth knowing which.

**`--prompt-mode prerendered`** because that is what this app does. For
`ModelType.functionGemma`, `InferenceChat` renders the declarations into the
prompt itself — you read the code that does it in Step 2 — so the runtime must
not template them again. The value has to be the **same** in `tune` and
`bundle`, and the wrong one produces a fluent wrong answer rather than an
error.

**`prepare` splits by content hash**, into `train.jsonl` and `heldout.jsonl`,
and rejects rows it cannot score. The held-out half is never trained on:
scoring a model on rows it was fitted to measures memorisation, not whether it
answers new inputs. Re-running `prepare` puts the same rows on the same side.

**`--reference` is the float twin** — the same weights before conversion. That
is what makes the difference between the two sides the *conversion cost*,
rather than a mixture of that and whatever training did. Point it at an untuned
base instead and both numbers come back unavailable, because one measurement
cannot separate two effects.

**`--recipe` has no default**, and litetune's own line for why is the right one
to keep: *"A sweep of one is not a comparison."* Two of its four recipes have
been measured (`dynamic_wi8_afp32`, `weight_only_wi8_afp32`) and two have not.
The two artifacts a sweep produces are 0.04% apart in bytes; nothing in file
size, exit code or logs separates them, and running both against held-out data
is the only thing that does.

Command 3 in that list — not this codelab's Step 3 — already gives you
something shippable: one `.litertlm` per recipe under `artifacts/<recipe>/`.
Commands 4 and 5 are what let you say anything about it.

### Then open it in the app

Here is the punchline, and it is a small one on purpose. Run `complete/`,
choose **Open a .litertlm from disk**, paste the absolute path that `convert`
printed, and the app runs your model.

Not one line of Dart changes. The `.litertlm` you produced is a `.litertlm`,
and the only thing that differs is where the bytes are:

```dart
  /// Points an install at wherever this model's bytes are.
  ///
  /// The two branches are the whole difference between a model you downloaded
  /// and a model you tuned: `fromNetwork` fetches the file, `fromFile`
  /// registers one that is already here. Everything after this line — the
  /// session, the tools, the loop — cannot tell them apart.
  InferenceInstallationBuilder locate(InferenceInstallationBuilder builder) =>
      path != null ? builder.fromFile(path!) : builder.fromNetwork(url!);
```

`fromFile` does not copy. It checks the file exists, registers the path, and
marks it protected — so `getModelPath` later hands back your own
`artifacts/` directory, and moving or deleting the file takes the model with
it. It is also why the delete button in `complete/` is safe on a tuned model:
`uninstallModel` skips the file for a `FileSource` install and only forgets the
metadata. The app never owned that file.

On the web there is no path to give — the browser arm of `fromFile` registers a
URL, not a file — so `complete/` says so instead of offering a text field that
cannot work.

**If you skip this step**, nothing downstream breaks. `complete/` ships two
models it can download and works on either.

## Step 5: Three tools, toolChoice, and thinking
Duration: 12

`complete/` is the finished app: a model list, three tools, and two session
settings you can change while it runs.

### Three tools cost the loop nothing

```dart
/// Everything the model is told it can call.
const toolbox = <Tool>[multiplyTool, clockTool, deviceTool];
```

The loop did not change to accept them, because it dispatches by name:

```dart
Map<String, dynamic> runTool(FunctionCallResponse call) {
  final runner = toolRunners[call.name];
  if (runner == null) {
    return {'error': 'This app has no tool named "${call.name}".'};
  }
  return runner(call.args);
}
```

Two collections, and the reason they are two rather than a `switch`:

```dart
const toolRunners = <String, ToolRunner>{
  'multiply': runMultiply,
  'get_current_time': runClock,
  'get_device_info': runDeviceInfo,
};
```

A declaration with no runner is a call the app answers with an error forever
and the model never finds out why; a runner with no declaration is code the
model is never told about. Two collections can be compared, and
`test/widget_test.dart` does:

```dart
  test('every declared tool has a runner, and no runner is undeclared', () {
    expect(
      toolbox.map((t) => t.name).toSet(),
      toolRunners.keys.toSet(),
      reason: 'toolbox and toolRunners must name the same tools',
    );
  });
```

The other two tools are the device clock and the platform name, for the same
reason `multiply` was arithmetic: you can check both by eye, and neither needs
a network. A tool with no arguments still declares `parameters`, which is worth
knowing —

```dart
const clockTool = Tool(
  name: 'get_current_time',
  description:
      'Return the current local date and time on this device. Use this '
      'whenever the answer depends on what time it is now.',
  parameters: {'type': 'object', 'properties': <String, dynamic>{}},
);
```

— because FunctionGemma's rendered declaration gates the whole `parameters`
block on that map. Drop it and the model reads a declaration that was cut off.

### toolChoice, and the models that cannot obey it

`ToolChoice` has three values, and what each one is worth depends on **who
renders the declarations** for the model you picked:

```dart
        // Whether the model may, must, or must not call — and how much of that
        // lands depends on who renders the declarations. On FunctionGemma the
        // SDK renders them into the prompt, so `none` leaves them out and the
        // model never learns the tools exist. On Gemma 4 the runtime renders
        // them from `tools_json`, which `createChat` passes whatever you
        // choose here — so `none` cannot take them back out. What it does
        // switch off there is the SDK's suppression of tool-call JSON, which
        // is why a call made under `none` can arrive as raw JSON in the bubble.
        toolChoice: _toolChoice,
```

Switch to `none` on **FunctionGemma** and ask the multiplication question
again: the declarations are gone from the prompt, you get the model's own
arithmetic, and that is the demonstration.

On **Gemma 4** the same switch is weaker than its name. Its declarations are
carried by the session — `createChat` forwards `tools` to `createSession`
without consulting `toolChoice` — so `none` cannot unsay them. All it does
there is turn off the SDK's swallowing of a tool-call turn, so if the model
calls anyway you see the raw `{"role":"assistant","tool_calls":[…]}` in the
reply bubble instead of prose. Worth trying once, because it is the clearest
possible look at what the passthrough format actually puts on the wire.

Switch to `required` and **neither** model obeys it. The app says so rather
than leaving you to wonder:

```dart
      _notice =
          _toolChoice == ToolChoice.required &&
              !widget.model.supportsRequiredToolChoice
          ? '${widget.model.label} cannot be forced to call a tool — nothing '
                'in the prompt it is given can say "you must", so `required` '
                'behaves as "auto".'
          : null;
```

That is not a bug in either model, and the two reasons are different.
FunctionGemma's prompt format has no way to express "you must call a function",
and honouring `required` would mean inventing tokens it was never trained on —
so `InferenceChat` logs a warning and behaves as `auto`. Gemma 4 never reaches
that code: the only "you must" text the SDK owns lives on the Dart-injection
path, which passthrough models skip by design, and the `tools_json` handed to
the runtime carries no `tool_choice` field at all. So there `required` is
silently `auto` — not even a warning.

Which is why the answer is recorded per checkpoint rather than assumed from
size. Today it is `false` for both, and the bigger model is not the exception:

```dart
  /// Can this model be *forced* to call a tool?
  ///
  /// `ToolChoice.required` needs a way to say "you must call a function" in
  /// the prompt the model actually reads, and neither of these has one.
  /// FunctionGemma's format cannot express it, so the SDK logs a warning and
  /// behaves as `auto`. Gemma 4's declarations go to the runtime as
  /// `tools_json`, which carries no `tool_choice` — so `required` is `auto`
  /// there too, without even the warning. Reasonable behaviour on the SDK's
  /// part, and very confusing to watch if the app does not say so.
  final bool supportsRequiredToolChoice;
```

### Thinking mode, and what the 2.59 GB buys

Gemma 4 E2B can reason before it chooses. FunctionGemma cannot — 270M
parameters specialised for one skill, and reasoning is not it. One flag:

```dart
        // Reason first, then answer. On weights with no thinking training this
        // buys nothing, which is why the switch is disabled for those.
        isThinking: _thinking,
```

With it on, the stream carries a third kind of chunk:

```dart
          case ThinkingResponse(:final content):
            // These reach the stream only because the chat was opened with
            // `isThinking: true`; with it false the SDK drops them before this
            // loop ever sees one.
            _thought.write(content);
            if (mounted) setState(_paintThinking);
```

`isThinking: false` is not a display choice — the SDK filters `ThinkingResponse`
out of the stream entirely, so an app that ignores the case sees nothing either
way. And the reasoning goes *above* the answer, because that is the order it
happened in:

```dart
  void _paintThinking() {
    if (_thinkAt < 0) {
      _turns.insert(_replyAt, const _Turn('', kind: _TurnKind.thinking));
      _thinkAt = _replyAt;
      _replyAt += 1;
    }
    _turns[_thinkAt] = _Turn(_thought.toString(), kind: _TurnKind.thinking);
  }
```

Thinking is generated text and comes out of the same budget as the answer,
which is why the session asks for more room when it is on:

```dart
        maxOutputTokens: _thinking ? 512 : 256,
```

### Both settings belong to the session

Neither `toolChoice` nor `isThinking` can be changed on a live chat. One
decides whether the declarations are rendered into the prompt; the other
switches on a generation channel. Both are settled when the session is created,
so changing either closes the chat and opens another — and the transcript goes
with it:

```dart
  /// Rebuilds the session because a session setting changed.
  ///
  /// There is no way to change `toolChoice` or `isThinking` on a live chat:
  /// both are decided when the session is created — one renders the
  /// declarations into the prompt, the other switches on a generation channel
  /// — so the honest thing is to close this one and open another. The
  /// transcript goes with it, because the new session's history is empty and a
  /// transcript that survived would be describing a conversation the model can
  /// no longer remember.
```

### Three models, one container

`complete/` opens with a list rather than a single constant, because by now
there are three things it can run: two downloads and whatever came out of Step
4. All three share one application identity, so `install()` being idempotent is
not enough — the gate has to say which model it *means*:

```dart
  Future<bool> _check() async {
    if (!await FlutterGemma.isModelInstalled(widget.model.fileName)) {
      return false;
    }
    await widget.model
        .locate(
          FlutterGemma.installModel(
            modelType: widget.model.modelType,
            fileType: ModelFileType.litertlm,
          ),
        )
        .install();
    return true;
  }
```

A model you added from disk turns up in that list again on the next launch,
without the app storing anything of its own — `listInstalledModels` returns the
ids, and `getModelPath` turns one back into where the file actually is:

```dart
  Future<List<ModelChoice>> _findYourOwn() async {
    final shipped = {for (final m in Models.downloadable) m.fileName};
    final installed = await FlutterGemma.listInstalledModels();
    final yours = <ModelChoice>[];
    for (final id in installed) {
      if (shipped.contains(id)) continue;
      yours.add(ModelChoice.fromDisk(await FlutterGemma.getModelPath(id)));
    }
    return yours;
  }
```

One simplification stated out loud: a model opened from disk is assumed to be a
fine-tuned FunctionGemma, because that is what Step 4 produces and nothing on
disk records which family a `.litertlm` belongs to. Tune a different base and
`ModelChoice.fromDisk` is the line to change.

### Where this runs

| | Android | iOS device | iOS Simulator | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|---|
| Function calling | yes | yes | CPU only | yes | yes | yes | **no** (Gemma 4) |
| Thinking (Gemma 4) | yes | yes | CPU only | yes | yes | yes | see below |
| Open a file from disk | yes | yes | yes | yes | yes | yes | **no** |

**The web** builds and runs, and text chat works. Function calling on **Gemma
4** does not, and this is known from the source rather than merely untried: the
browser `.litertlm` runtime does not override `createChat`, so it inherits the
base implementation, whose session factory never passes `tools:` on. Gemma 4's
declarations travel *with the session*, so on web they never arrive — the model
is told nothing about your functions and answers 1234 × 5678 out of its own
head. FunctionGemma's declarations are rendered into the prompt by
`InferenceChat` instead, so they are not lost the same way, but nothing in this
codelab was run on web against either model, so treat that half as unverified.
Thinking is unverified for the same reason: the browser runtime types its
`extra_context` as opaque JSON and its thinking channel has never been
confirmed end to end. The 2.59 GB model is in any case not a browser download,
and the from-disk path is genuinely absent: `fromFile` in a browser registers a
URL, because a browser has no path to give.

**The iOS Simulator** runs CPU-only — Metal's simulator implementation caps a
single allocation at 256 MB, below Gemma 4's weights. FunctionGemma at 284 MB
is comfortable there; Gemma 4 will crawl if it loads at all, and hardware is
the answer.

### Try it end to end

`complete/` ships an integration test that downloads Gemma 4, opens one chat
with all three declarations, and asks a question the model cannot answer on its
own. It needs a device and a 2.59 GB download, so it is not part of CI:

```bash
cd codelabs/function-calling-flutter-gemma/complete
flutter test integration_test/function_calling_test.dart -d <device-id>
```

What it asserts is worth reading, because "the reply is not empty" would not
have caught anything:

```dart
    // Ground truth, taken from the call the model actually made rather than
    // from what it was asked: `isNotEmpty` on the reply would not tell a model
    // that used the tool from one that invented a plausible number and ignored
    // it. Whatever arguments it chose, the product in the reply must be the
    // one THIS app computed for them.
```

## What's next
Duration: 2

A declaration, a function, and a loop that knows when to stop — plus a model
you tuned yourself, if you spent the CPU time.

* **On-device RAG** gives the model documents instead of functions: embed your
  own text, search it, and ground the answer
* **`flutter_gemma_agent`** builds on exactly this loop — skills written as
  Markdown, JavaScript or native intents, driven by the same
  function-calling machinery
* **Multimodal** ([Vision and Audio on Device](/codelabs/multimodal-flutter-gemma))
  is the other thing a session flag switches on, and the codelab where the flag
  really does have to go in two places

### Reference

* [flutter_gemma on pub.dev](https://pub.dev/packages/flutter_gemma) — the full
  platform support matrix and the model table
* [litetune](https://github.com/DenisovAV/litetune) — the fine-tuning pipeline
  Step 4 uses, including what it has and has not measured
* [Source and this codelab's code](https://github.com/DenisovAV/flutter_gemma)
