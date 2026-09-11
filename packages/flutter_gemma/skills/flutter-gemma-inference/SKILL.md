---
name: flutter-gemma-inference
description: Use when adding on-device LLM inference to a Flutter app with flutter_gemma — offline chat, running Gemma, Qwen or Phi locally, streaming replies, image prompts — or setting up the default .litertlm engine on Android, iOS, macOS, Windows, Linux or web. Also use when a reply comes back empty, maxTokens does not shorten replies, getActiveModel throws "No inference engine can handle this model", or .litertlm fails to load on Android. For function calling, RAG, speech, .task files, ONNX or the OS built-in model, also use the matching flutter-gemma-* skill.
---

# Running a model with flutter_gemma

## Rules

1. Register an engine in `FlutterGemma.initialize(inferenceEngines: [...])`. Core ships none.
2. Declare `fileType` on `installModel`. It defaults to `ModelFileType.task`, and the declaration — never the file name — picks the engine.
3. `maxTokens` is the context window. Cap the reply with `maxOutputTokens` on the session.
4. Pass `isUser: true` on every user `Message`.
5. Close every session, chat and model in a `finally`.
6. Never put a Hugging Face token in source. Read it with `String.fromEnvironment`.
7. On Android, set `minSdk 30` for anything built on `.litertlm` — inference, embeddings, speech.

## Setup — the default engine (.litertlm)

```dart
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

const hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  huggingFaceToken: hfToken.isEmpty ? null : hfToken, // gated repos only
);

await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
).fromNetwork(url).install();

final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
```

Build with `--dart-define=HUGGINGFACE_TOKEN=hf_...` when the model repo is gated.

When a Hugging Face repo publishes a deployment manifest, one call picks the variant and its tested runtime settings. The engine carries its own resolver, so registering `LiteRtLmEngine` is enough:

```dart
final install = await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.litertlm,
).fromHuggingFace('litert-community/LFM2.5-230M').install();

final model = await FlutterGemma.getActiveModel(defaults: install.runtime);
```

Other sources on the same builder: `.fromAsset(path)` for a model bundled in the app, `.fromFile(path)` for one already on disk, `.fromBundled(name)` for a platform-bundled resource.

`modelType` sets the chat template. Gemma 3 and Gemma 3n are `ModelType.gemmaIt` — there is no `gemma3`. The full set: `general`, `gemmaIt`, `gemma4`, `deepSeek`, `qwen`, `qwen3`, `llama`, `hammer`, `functionGemma`, `phi`. A wrong type still generates, with the wrong prompt format.

## Traps

**No engine registered**
- Symptom: `StateError: No inference engine can handle this model (ModelFileType.litertlm). Add the engine package to pubspec.yaml and pass it in inferenceEngines: of FlutterGemma.initialize(...)`
- Fix: add the engine package and register its provider — or fix `fileType` if the wrong engine is registered.

**`maxTokens` used as a reply length**

```dart
// WRONG — asks for a 100-token context, not a 100-token reply
final model = await FlutterGemma.getActiveModel(maxTokens: 100);
```

- Symptom: replies are as long as ever. On `.litertlm` the value is raised to 1024, the smallest context those models support, and only a debug-mode log says so.
- Fix:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
final session = await model.createSession(maxOutputTokens: 100);
```

Use 4096 or more with images or audio — one image costs hundreds of tokens.

**`isUser` left out**
- Symptom: an empty response, no error. `Message.isUser` defaults to `false`, so the prompt is read as the model's own turn.
- Fix: `Message(text: prompt, isUser: true)`.

**Same reply every time**
- Symptom: identical output for identical input. `createSession` defaults to `topK: 1`, which is greedy decoding.
- Fix: pass `topK` (e.g. 40) and a `temperature`.

## Generate

```dart
final session = await model.createSession(
  temperature: 0.8,
  topK: 40,
  maxOutputTokens: 256,
);
try {
  await session.addQueryChunk(Message(text: prompt, isUser: true));
  final reply = await session.getResponse();
} finally {
  await session.close();
}
```

Streaming:

```dart
await session.addQueryChunk(Message(text: prompt, isUser: true));
await for (final token in session.getResponseAsync()) {
  stdout.write(token);
}
```

To stop early, call `await session.stopGeneration()`. Cancelling the stream subscription detaches Dart but does not stop native decoding on every engine.

## Multi-turn chat

```dart
final chat = await model.createChat(tokenBuffer: 256, maxOutputTokens: 512);
try {
  await chat.addQueryChunk(Message(text: prompt, isUser: true));
  final response = await chat.generateChatResponse();
  if (response is TextResponse) print(response.token);
} finally {
  await chat.close();
}
```

`generateChatResponse()` returns a sealed `ModelResponse`: `TextResponse`, `FunctionCallResponse`, `ParallelFunctionCallResponse` or `ThinkingResponse`.

## Two conversations at once

`createSession` and `createChat` fill a single slot on the model: a second call replaces the first, and the two chats corrupt each other. For concurrent conversations use `openSession` / `openChat`, and close each one.

```dart
final summariser = await model.openChat();
final assistant = await model.openChat();
try {
  await summariser.addQueryChunk(Message(text: chunk, isUser: true));
  await assistant.addQueryChunk(Message(text: question, isUser: true));
} finally {
  await summariser.close();
  await assistant.close();
}
```

## Thinking models

Gemma 4, Qwen3 and DeepSeek R1 can emit reasoning. Pass `isThinking: true` to `createChat`. Reasoning arrives as `ThinkingResponse` only from `generateChatResponseAsync()`; `generateChatResponse()` strips it. Not available on web.

```dart
final chat = await model.createChat(isThinking: true, modelType: ModelType.qwen3);
await chat.addQueryChunk(Message(text: question, isUser: true));
await for (final r in chat.generateChatResponseAsync()) {
  switch (r) {
    case ThinkingResponse(:final content):
      print('reasoning: $content');
    case TextResponse(:final token):
      stdout.write(token);
    case FunctionCallResponse() || ParallelFunctionCallResponse():
      break;
  }
}
await chat.close();
```

## Images

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096, supportImage: true);
final chat = await model.createChat(supportImage: true);
await chat.addQueryChunk(
  Message(text: 'What is in this photo?', isUser: true, imageBytes: bytes),
);
```

## The model is a singleton

`getActiveModel` returns one model per process. Calling it again with different runtime arguments rebuilds it and closes the previous one — a handle you still hold stops working. Load once at startup, then create and close sessions per interaction.

## Backends

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 1024,
  preferredBackend: PreferredBackend.gpu,
);
print(model.activeBackend); // what actually loaded
```

| `preferredBackend` | Tried in order |
| --- | --- |
| `null` or `gpu` | GPU, then CPU |
| `npu` | NPU, GPU, CPU |
| `cpu` | CPU only |

Read `activeBackend` rather than assuming the requested one loaded. NPU needs a Snapdragon (Android) or Intel Lunar/Panther Lake (Windows). The iOS Simulator is CPU-only; web is GPU-only.

## Platform setup

Android needs `minSdk 30` and ships `arm64-v8a` only. iOS and macOS need Podfile and entitlement entries; web needs script tags in `web/index.html`. Read `references/platform-setup.md` before building for iOS, macOS or web — without those entries the model fails to load or the app runs out of memory.
