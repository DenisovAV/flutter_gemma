---
title: Getting Started
description: Run Gemma and other on-device LLMs in your Flutter app — Android, iOS, Web, and Desktop.
image: https://fluttergemma.dev/images/og-image.png
---

Bring the power of Google's lightweight Gemma language models and other on-device
LLMs directly to your Flutter applications. With **flutter_gemma** you can
seamlessly incorporate advanced AI capabilities into your apps — all without
relying on external servers.

[Gemma](https://ai.google.dev/gemma) is a family of lightweight, state-of-the-art
open models built from the same research and technology used to create the Gemini
models. The plugin supports not only Gemma, but also Qwen, DeepSeek, Phi, FastVLM,
SmolLM and more — see [Models](/docs/models) for the full list.

## Features

- **Local Execution:** Run Gemma and other LLMs (Qwen, DeepSeek, Phi, FastVLM, SmolLM, …) directly on user devices for enhanced privacy and offline functionality.
- **Platform Support:** Compatible with iOS, Android, Web, macOS, Windows, and Linux.
- **Desktop Support:** Native desktop apps with GPU acceleration via LiteRT-LM, called directly from Dart through `dart:ffi` — no JVM/JRE bundling. See [Desktop Support](/docs/desktop).
- **Multimodal Support:** Text + image input with Gemma 4, Gemma3n, and FastVLM vision models. See [Multimodal](/docs/multimodal).
- **Audio Input:** Record and send audio messages with Gemma 4 and Gemma3n models (Android, iOS device, Desktop).
- **Function Calling:** Let models call external functions and integrate with other services. See [Function Calling](/docs/function-calling).
- **Thinking Mode:** View the reasoning process of DeepSeek, Gemma 4, and Qwen3 models. See [Thinking Mode](/docs/thinking-mode).
- **Stop Generation:** Cancel text generation mid-process on Android, iOS, Web, and Desktop.
- **Backend Switching:** Choose between CPU and GPU backends for each model individually.
- **LoRA Support:** Efficient fine-tuning and integration of LoRA (Low-Rank Adaptation) weights.
- **Enhanced Downloads:** Smart retry logic with exponential backoff and automatic restart of interrupted downloads.
- **Android Foreground Service:** Large downloads (>500MB) automatically use a foreground service to bypass the 9-minute timeout.
- **Text Embeddings & RAG:** Generate vector embeddings (EmbeddingGemma, Gecko) and run on-device RAG. See [Embeddings & RAG](/docs/embeddings-and-rag).
- **Web Persistent Caching:** Models persist across browser restarts using the Cache API (Web only).

## What's new in 1.0

- **Modular package split** — the monolith is now a small **core** (`flutter_gemma`) plus **opt-in** packages, so your app ships only the native weight it uses: `flutter_gemma_litertlm` (.litertlm), `flutter_gemma_mediapipe` (.task/.bin), `flutter_gemma_embeddings`, `flutter_gemma_rag_qdrant`, `flutter_gemma_rag_sqlite`. See [Packages](/docs/packages).
- **New `FlutterGemma.initialize(...)` registration** — pass `inferenceEngines`, `embeddingBackends`, `vectorStore` for the packages you added. See [Installation](/docs/installation).
- **Every model / session / chat / embedding / RAG API is unchanged** — migrating is just adding packages + the initialize call. See [Migration](/docs/migration).
- **Legacy sqlite + local_hnsw vector store removed** — native RAG runs on qdrant-edge (`flutter_gemma_rag_qdrant`); web on wa-sqlite (`flutter_gemma_rag_sqlite`).

See the [CHANGELOG](https://github.com/DenisovAV/flutter_gemma/blob/main/CHANGELOG.md) for the full release history.

## Quick Start

<Warning>
Complete the [platform setup](/docs/installation) before running this code.
</Warning>

### 1. Install a Model (One Time)

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// Install model. The URL below uses the .litertlm variant so the same code
// works on Desktop (Windows/macOS/Linux) and mobile/web. For web only, the
// `.task` / `-web.task` variants of the same model also work.
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
).fromNetwork(
  'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
  token: 'your_hf_token',
).withProgress((progress) {
  print('Downloading: $progress%');
}).install();
```

<Info>
**Mobile/Web shortcut:** if you don't target Desktop, you can substitute the URL
with the `.task` build of the same model. Desktop targets need the `.litertlm`
build — `.task` and `.bin` are MediaPipe-only.
</Info>

### 2. Create and Use a Model (Multiple Times)

```dart
// Create model with specific configuration
final model = await FlutterGemma.getActiveModel(
  maxTokens: 2048,
  preferredBackend: PreferredBackend.gpu,
);

// Use model
final chat = await model.createChat();
await chat.addQueryChunk(Message.text(
  text: 'Explain quantum computing',
  isUser: true,
));
final response = await chat.generateChatResponse();

// Cleanup
await model.close();
```

<Warning>
`Message.isUser` defaults to `false`. Always pass `isUser: true` for user
messages, or the model returns an empty response. Always `close()` sessions and
models when you're done with them.
</Warning>

### System Instructions

Control model behavior with a system-level instruction:

```dart
final chat = await model.createChat(
  systemInstruction: 'You are a concise assistant. Always respond in bullet points.',
);
```

**Platform support:**

- **Android `.litertlm` / Desktop**: passed natively via `ConversationConfig.systemInstruction`.
- **Android `.task` / iOS / Web**: prepended to the first user message as a fallback.

### Multiple Instances from the Same Model

```dart
// Install once
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url).install();

// Create multiple instances
final quickModel = await FlutterGemma.getActiveModel(maxTokens: 512);
final deepModel = await FlutterGemma.getActiveModel(maxTokens: 4096);
// Both use the SAME model file!
```

### Concurrent Sessions (`openSession`)

A single loaded model can serve several **independent** dialogues at once.
`openSession()` returns a session with its own conversation history, detached
from the legacy `model.session` singleton; `openChat()` is the same for the
higher-level chat API.

The model weights (the big, expensive part — hundreds of MB to several GB) are
loaded **once** and shared across every session; each session only adds its own
lightweight conversation context.

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 1024);

final chatA = await model.openChat(); // independent context A
final chatB = await model.openChat(); // independent context B

await chatA.addQueryChunk(Message(text: 'My name is Alice.', isUser: true));
await chatA.generateChatResponse();

await chatB.addQueryChunk(Message(text: 'My name is Bob.', isUser: true));
await chatB.generateChatResponse();

// Each remembers only its own context.
await chatA.addQueryChunk(Message(text: 'What is my name?', isUser: true));
print(await chatA.generateChatResponse()); // "Alice"

model.sessions;               // all live sessions (legacy + open)
await chatA.session.close();  // closing one leaves the others usable
```

<Warning>
**Concurrent contexts, serialized inference.** The sessions are logically
independent, but **only one session generates at a time** — calling
`generateResponse()` on a second session while another is still running blocks
until the first finishes. Generation is *not* parallel. This is intentional:
parallel on-device inference would contend for the accelerator and risk OOM.
</Warning>

**Memory:** each open session holds its own context (~100–500 MB depending on
model + `maxTokens`). On phones with large models (Gemma 4 E2B+), several
concurrent sessions can OOM. Cap the count with `maxConcurrentSessions:` on
`getActiveModel(...)` — `openSession()` throws `StateError` past the cap.

If you only ever have one conversation at a time, stick with the simpler
`createSession()` / `createChat()` singleton API — you don't need this.

## Message Types

```dart
// Text only
final textMessage = Message.text(text: "Hello!", isUser: true);

// Text + Image
final multimodalMessage = Message.withImages(
  text: "What's in this image?",
  imageBytes: [imageBytes],
  isUser: true,
);

// Image only
final imageMessage = Message.imagesOnly(imageBytes: [imageBytes], isUser: true);

// Tool response (for function calling)
final toolMessage = Message.toolResponse(
  toolName: 'change_background_color',
  response: {'status': 'success', 'color': 'blue'},
);

// System information message
final systemMessage = Message.systemInfo(text: "Function completed successfully");

// Thinking content (for DeepSeek models)
final thinkingMessage = Message.thinking(text: "Let me analyze this problem...");

// Check if a message contains an image
if (message.hasImage) {
  print('This message contains an image');
}
```

## Response Types

The model can return different types of responses depending on its capabilities:

```dart
chat.generateChatResponseAsync().listen((response) {
  if (response is TextResponse) {
    // Regular text token from the model
    print('Text token: ${response.token}');
  } else if (response is FunctionCallResponse) {
    // Model wants to call a function
    print('Function: ${response.name}');
    print('Arguments: ${response.args}');
    _handleFunctionCall(response);
  } else if (response is ThinkingResponse) {
    // Model's reasoning process
    print('Thinking: ${response.content}');
    _showThinkingBubble(response.content);
  }
});
```

- **`TextResponse`** — contains a text token (`response.token`) for regular model output.
- **`FunctionCallResponse`** — contains function name (`response.name`) and arguments (`response.args`). See [Function Calling](/docs/function-calling).
- **`ThinkingResponse`** — contains the model's reasoning process (`response.content`). See [Thinking Mode](/docs/thinking-mode).

## Next Steps

- [Installation](/docs/installation) — per-platform setup and engine registration.
- [Models](/docs/models) — supported models, file formats, and capabilities.
- [Migration (0.x → 1.0)](/docs/migration) — upgrade from the monolith.
