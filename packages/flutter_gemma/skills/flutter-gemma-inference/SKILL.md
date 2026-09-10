---
name: flutter-gemma-inference
description: Use whenever writing flutter_gemma code — installing a model, calling FlutterGemma.initialize/getActiveModel/createSession, or generating text. Core registers no engine by default, maxTokens is the context window and NOT the reply length, and Message.isUser defaults to false; all three fail quietly.
---

# Running a model with flutter_gemma

This is the path from an empty app to a generated token. Four defaults on it
produce wrong behaviour rather than an error — start with those.

## 1. Core ships no engine — register one

`flutter_gemma` is the contracts, the registry and the platform shells. It has
no inference runtime. Adding only `flutter_gemma` compiles fine and throws on
the first `getActiveModel()`.

| Package | Handles |
| --- | --- |
| `flutter_gemma_litertlm` | `.litertlm` — the main path, all six platforms |
| `flutter_gemma_mediapipe` | `.task`, `.bin` — mobile + web |
| `flutter_gemma_builtin_ai` | the OS model, no file to install |
| `flutter_gemma_onnx` | ONNX / ORT-GenAI |

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
```

Every capability is opt-in the same way and defaults to an empty list —
`embeddingBackends`, `sttBackends`, `ttsBackends`, `huggingFaceResolvers`. If a
list is empty, the matching first call throws a `StateError` naming the package
to add. Read that message rather than guessing.

## 2. The engine is chosen by the DECLARED file type, never the filename

`installModel` defaults to `ModelFileType.task`. A `.litertlm` file installed
without declaring its type is routed to MediaPipe, which cannot read it.

```dart
// WRONG — the name says .litertlm, the declaration says .task,
// and the declaration is what routes it.
await FlutterGemma.installModel(modelType: ModelType.gemma4)
    .fromNetwork(url).install();

// RIGHT
await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
).fromNetwork(url).install();
```

`modelType` is a separate axis: it drives the chat template and the model's
capabilities (`gemma4`, `gemma3`, `qwen3`, `deepSeek`, `general`, …). Getting it
wrong also fails quietly — the model generates, with the wrong prompt format.

Sources: `.fromNetwork(url, token:)`, `.fromAsset(path)`, `.fromFile(file)`, and
`.fromHuggingFace(repo)` when a resolver is registered.

## 3. maxTokens is the CONTEXT WINDOW, not the reply length

`maxTokens` is the whole KV-cache budget: system prompt + history + the current
message + everything generated. It is not "how long the answer may be".

Setting it small to get a short answer is the most common mistake with this
package, and on `.litertlm` it does not truncate — it crashes, with a message
naming an internal executor file and nothing else.

```dart
// WRONG — meant "a 100-token reply", actually a 100-token context.
final model = await FlutterGemma.getActiveModel(maxTokens: 100);

// RIGHT — roomy context, capped output.
final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
final session = await model.createSession(maxOutputTokens: 100);
```

Use 4096+ for vision or audio — one image is worth hundreds of tokens.

## 4. Message.isUser defaults to false

```dart
const Message(text: 'Hello')                  // WRONG — empty response
const Message(text: 'Hello', isUser: true)    // RIGHT
```

No error is raised. The response is just empty.

## Generating

```dart
final session = await model.createSession(
  temperature: 0.8,
  topK: 40,
  maxOutputTokens: 256,
);
try {
  await session.addQueryChunk(
    const Message(text: 'Explain isolates briefly.', isUser: true),
  );
  final answer = await session.getResponse();
  // streaming: await for (final chunk in session.getResponseAsync()) …
} finally {
  await session.close();
}
await model.close();
```

Sessions and models hold native resources — an isolate, a compiled model, GPU
buffers. Always close them, in a `finally`.

## Multi-turn

`InferenceChat` keeps history and applies the model's chat template:

```dart
final chat = await model.createChat(tokenBuffer: 256, maxOutputTokens: 512);
try {
  await chat.addQueryChunk(const Message(text: 'Hi', isUser: true));
  final response = await chat.generateChatResponse();
  if (response is TextResponse) print(response.token);
} finally {
  await chat.close();
}
```

`generateChatResponse()` returns a `ModelResponse`, not a `String`. With tools
enabled it may be a function call — see the `flutter-gemma-tools` skill.

Thinking models (Qwen3, DeepSeek R1) emit `<think>` blocks; pass
`isThinking: true` to surface them as `ThinkingResponse`, or `false` to have
them stripped.

## Multimodal

Declare support at model creation, then attach bytes:

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  supportImage: true,
);
await session.addQueryChunk(
  Message(text: 'What is in this photo?', isUser: true, imageBytes: bytes),
);
```

## Cost model

Loading a model is expensive; creating a session is cheap. Load once, keep the
model, create and close a session per interaction. Never call `getActiveModel`
per message.

`getActiveModel` returns a process-wide singleton. Calling it again with
different runtime arguments rebuilds it and closes the previous instance — a
handle you are still holding becomes unusable. Decide the runtime configuration
once.

## Engine-specific rules

Platform floors, backend selection and format quirks live with each engine:
`flutter-gemma-litertlm`, `flutter-gemma-mediapipe`, `flutter-gemma-onnx`,
`flutter-gemma-builtin-ai`. Read the one for the engine in use — this skill
covers only what is common to all of them.
