---
name: flutter-gemma-inference
description: Use when adding on-device LLM inference to a Flutter app with flutter_gemma — offline chat, running Gemma, Qwen or Phi locally, downloading and installing a model from Hugging Face (gated repos included), streaming replies, a system prompt, image or audio prompts — or setting up the recommended .litertlm engine (ModelFileType.litertlm) on Android, iOS, macOS, Windows, Linux or web. Also use when a reply comes back empty, maxTokens does not shorten replies, FlutterGemma is an undefined name, getActiveModel throws "No inference engine can handle this model", a session throws "Session is closed", or .litertlm fails to load on Android. For .task or .bin models (ModelFileType.task), use flutter-gemma-mediapipe.
---

# Running a model with flutter_gemma

## Rules

1. Depend on `flutter_gemma` and an engine package, and import both. Engine packages do not re-export core.
2. Register the engine in `FlutterGemma.initialize(inferenceEngines: [...])`. Core ships none.
3. Declare `fileType` on `installModel`. It defaults to `ModelFileType.task`, and the declaration — never the file name — picks the engine.
4. `maxTokens` is the context window. Cap the reply with `maxOutputTokens` on the session or chat.
5. Pass `isUser: true` on every user `Message`.
6. Close a session or chat when its conversation ends. Keep the model while the feature is in use, and close it when the app no longer needs it.
7. Keep Hugging Face tokens out of source: read them with `String.fromEnvironment`. That keeps a token out of git, not out of the app — it is compiled into the binary, and on web into `main.dart.js`. A shipped app should download from a repo that needs no token.
8. On Android, set `minSdk 30` for anything built on `.litertlm` — inference, embeddings, speech.

## Setup — the recommended engine (.litertlm)

```sh
flutter pub add flutter_gemma flutter_gemma_litertlm
```

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
)
    .fromNetwork(
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    )
    .withProgress((int percent) => print('downloading: $percent%'))
    .install();

final InferenceModel model = await FlutterGemma.getActiveModel(maxTokens: 1024);
```

Gemma 4 E2B is 2.6 GB and needs no token. On web use `gemma-4-E2B-it-web.litertlm` from the same repo (2.0 GB).

`install()` skips the download when the file is already on disk, so calling it at every launch is safe. The latest install becomes the model `getActiveModel` loads.

A gated repo needs a token, given once:

```dart
const hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  huggingFaceToken: hfToken.isEmpty ? null : hfToken,
);
```

Build with `--dart-define=HUGGINGFACE_TOKEN=hf_...`.

When a Hugging Face repo publishes a deployment manifest, one call picks the variant and its tested runtime settings. The engine carries its own resolver, so registering `LiteRtLmEngine` is enough:

```dart
final install = await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.litertlm,
).fromHuggingFace('litert-community/LFM2.5-230M').install();

final model = await FlutterGemma.getActiveModel(defaults: install.runtime);
```

Other sources on the same builder: `.fromAsset(path)` for a model bundled in the app, `.fromFile(path)` for one already on disk, `.fromBundled(name)` for a platform-bundled resource.

`modelType` tells flutter_gemma how the model writes tool calls and reasoning, and on some engines it also picks the prompt format. Gemma 3 and Gemma 3n are `ModelType.gemmaIt` — there is no `gemma3`. The full set: `general`, `gemmaIt`, `gemma4`, `deepSeek`, `qwen`, `qwen3`, `llama`, `hammer`, `functionGemma`, `phi`. A wrong type still generates text; tool calls and reasoning then arrive as raw text.

## Traps

**Core not imported**
- Symptom: `Undefined name 'FlutterGemma'`, `Undefined class 'InferenceModel'`, with only the engine package imported.
- Fix: `import 'package:flutter_gemma/flutter_gemma.dart';` as well.

**No engine registered**
- Symptom: `StateError: No inference engine can handle this model (ModelFileType.litertlm). Add the engine package to pubspec.yaml and pass it in inferenceEngines: of FlutterGemma.initialize(...)`
- Fix: add the engine package and register its provider — or fix `fileType` if the wrong engine is registered.

**`maxTokens` used as a reply length**

```dart
// WRONG — asks for a 100-token context, not a 100-token reply
final model = await FlutterGemma.getActiveModel(maxTokens: 100);
```

- Symptom: replies are as long as ever. On native `.litertlm` the value is raised to 1024, the smallest context those models support, and only a debug-mode log says so. The web `.litertlm` engine does not take the value at all; on MediaPipe it is the real limit.
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
- Symptom: identical output for identical input. `createSession` and `createChat` default to `topK: 1`, which is greedy decoding.
- Fix: pass `topK` (e.g. 40) and a `temperature`. Set them on the first session after `getActiveModel` — on `.litertlm` the first session's sampler settings can stay in effect for later ones.

**`Session is closed`**
- Symptom: `StateError: Session is closed` from a session or chat that is still in use.
- Cause: `createSession` and `createChat` fill one slot per model; creating another closes the one before.
- Fix: one conversation at a time, or `openSession` / `openChat` for several (below). On web the `.litertlm` engine holds a single session — close the current chat before creating the next.

## Generate

```dart
final InferenceModelSession session = await model.createSession(
  temperature: 0.8,
  topK: 40,
  maxOutputTokens: 256,
);
try {
  await session.addQueryChunk(Message(text: prompt, isUser: true));
  final String reply = await session.getResponse();
} finally {
  await session.close();
}
```

Streaming:

```dart
final reply = StringBuffer();
await session.addQueryChunk(Message(text: prompt, isUser: true));
await for (final token in session.getResponseAsync()) {
  reply.write(token); // update the UI here
}
```

To stop early, call `await session.stopGeneration()` — `chat.stopGeneration()` on a chat. Cancelling the stream subscription detaches Dart but does not stop native decoding on every engine.

## Multi-turn chat

```dart
final InferenceChat chat = await model.createChat(
  systemInstruction: 'You are a concise assistant.',
  temperature: 0.8,
  topK: 40,
  maxOutputTokens: 512,
);
try {
  await chat.addQueryChunk(Message(text: prompt, isUser: true));
  final reply = StringBuffer();
  await for (final r in chat.generateChatResponseAsync()) {
    switch (r) {
      case TextResponse(:final token):
        reply.write(token);
      case ThinkingResponse() || FunctionCallResponse() || ParallelFunctionCallResponse():
        break;
    }
  }
} finally {
  await chat.close();
}
```

The chat keeps the history: add the next user message and generate again. `generateChatResponse()` returns the whole reply as one sealed `ModelResponse` — `TextResponse`, `FunctionCallResponse`, `ParallelFunctionCallResponse` or `ThinkingResponse` — and a `switch` over it must cover all four.

## Two conversations at once

`createSession` and `createChat` fill a single slot on the model, so a second one closes the first. For concurrent conversations use `openSession` / `openChat`, and close each one.

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

Gemma 4, Qwen3 and DeepSeek R1 can emit reasoning. Pass `isThinking: true` to `createChat`. Reasoning arrives as `ThinkingResponse` only from `generateChatResponseAsync()`; `generateChatResponse()` strips it. On web Gemma 4 has no thinking; Qwen3 and DeepSeek R1 reasoning is still separated out of the text.

```dart
final chat = await model.createChat(isThinking: true, modelType: ModelType.qwen3);
final answer = StringBuffer();
await chat.addQueryChunk(Message(text: question, isUser: true));
await for (final r in chat.generateChatResponseAsync()) {
  switch (r) {
    case ThinkingResponse(:final content):
      print('reasoning: $content');
    case TextResponse(:final token):
      answer.write(token);
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

## Audio

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096, supportAudio: true);
final chat = await model.createChat(supportAudio: true);
await chat.addQueryChunk(
  Message(text: 'What is said in this recording?', isUser: true, audioBytes: bytes),
);
```

`audioBytes` is a whole WAV file — 16 kHz mono, header included. The speech package is the opposite: `transcribe` takes raw PCM with no header. Audio input needs Gemma 4 or Gemma 3n, on Android, iOS or desktop; the `.litertlm` web engine takes no audio.

## The model is a singleton

`getActiveModel` returns one model per process. Calling it again with different runtime arguments rebuilds it and closes the previous one — a handle still held stops working. Load it once, then create and close sessions per conversation.

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

Read `activeBackend` rather than assuming the requested one loaded; the web `.litertlm` engine reports `null`. NPU needs a Snapdragon (Android) or Intel Lunar/Panther Lake (Windows) and a model compiled for that NPU. The iOS Simulator is CPU-only. On web, MediaPipe is GPU-only.

## Platform setup

Android needs `minSdk 30` and the internet permission in release builds, and ships `arm64-v8a` only. iOS needs Podfile or Xcode settings and memory entitlements; macOS needs entitlements and a Podfile build phase; web needs script tags in `web/index.html`. Read `references/platform-setup.md` before building for any of them — without those entries the model fails to load or the app runs out of memory.
