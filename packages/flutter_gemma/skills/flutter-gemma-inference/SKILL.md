---
name: flutter-gemma-inference
description: Use when generating text with flutter_gemma — sessions, chats, streaming, tools, or anything involving maxTokens. maxTokens is the context window and NOT the reply length; setting it low crashes .litertlm models, and Message.isUser defaults to false.
---

# Generating with flutter_gemma

Three defaults in this API produce wrong behaviour rather than errors. They
account for most of the issues filed against the package.

## maxTokens is the CONTEXT WINDOW, not the reply length

`maxTokens` on `getActiveModel` / `createModel` is the whole KV-cache budget:
system prompt + history + the current message + everything generated. It is not
"how long the answer may be".

Setting it small to get a short answer is the single most common mistake, and on
`.litertlm` it does not merely truncate — it crashes. Every supported
`.litertlm` model bakes `kv_cache_max_len = 1024`; below that the native
KV-cache resize underflows and tensor allocation fails at generation time with a
message that names an internal executor file and nothing else.

```dart
// WRONG — meant "a 100-token reply", actually a 100-token context.
final model = await FlutterGemma.getActiveModel(maxTokens: 100);

// RIGHT — roomy context, capped output.
final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
final session = await model.createSession(maxOutputTokens: 100);
```

Measured on a Pixel 8a (CPU): 100 / 256 / 512 crash; 1024 and 4096 work. The
litertlm engine now clamps values below 1024 upward and logs a warning, but do
not rely on that — say what you mean.

`maxOutputTokens` is `.litertlm` only. MediaPipe `.task` has no session-level
output cap and logs that the value was ignored.

## Message.isUser defaults to false

```dart
// WRONG — silently treated as an assistant message, so the model has
// nothing to answer and returns an empty string.
const Message(text: 'Hello')

// RIGHT
const Message(text: 'Hello', isUser: true)
```

There is no error. The response is just empty. Always pass `isUser`
explicitly.

## Always close sessions and models

Both hold native resources — an isolate, a compiled model, GPU buffers. Leaking
them exhausts memory and, on some backends, wedges the next load.

```dart
final session = await model.createSession();
try {
  // …
} finally {
  await session.close();
}
await model.close();
```

## One-shot generation

```dart
final session = await model.createSession(
  temperature: 0.8,
  randomSeed: 1,
  topK: 40,
  maxOutputTokens: 256,
);
try {
  await session.addQueryChunk(
    const Message(text: 'Explain isolates in one paragraph.', isUser: true),
  );
  final answer = await session.getResponse();
} finally {
  await session.close();
}
```

Streaming, same session shape:

```dart
await for (final chunk in session.getResponseAsync()) {
  stdout.write(chunk);
}
```

## Multi-turn conversation

`InferenceChat` keeps the history and applies the model's chat template.

```dart
final chat = await model.createChat(
  tokenBuffer: 256,
  maxOutputTokens: 512,
);
try {
  await chat.addQueryChunk(const Message(text: 'Hi', isUser: true));
  final reply = await chat.generateChatResponse();
} finally {
  await chat.close();
}
```

`generateChatResponse()` returns a `ModelResponse`, not a `String`. Switch on
it — with tools enabled it may be a function call:

```dart
switch (response) {
  case TextResponse(:final token): // plain text
  case FunctionCallResponse(:final name, :final args): // one tool call
  case ParallelFunctionCallResponse(:final calls): // several at once
}
```

## Function calling

Two arguments beyond `tools` are load-bearing. Without `supportsFunctionCalls`
the tools are dropped with a warning; without `modelType` the correct call
format cannot be derived.

```dart
final chat = await model.createChat(
  tools: [
    const Tool(
      name: 'change_color',
      description: 'Change the UI background colour.',
      parameters: {
        'type': 'object',
        'properties': {
          'color': {'type': 'string', 'description': 'A colour name.'},
        },
        'required': ['color'],
      },
    ),
  ],
  supportsFunctionCalls: true,
  modelType: ModelType.gemma4,
);

final response = await chat.generateChatResponse();
if (response is FunctionCallResponse) {
  final result = await runTool(response.name, response.args);
  await chat.addQueryChunk(
    Message.toolResponse(toolName: response.name, response: result),
  );
  final followUp = await chat.generateChatResponse();
}
```

Not every model supports tools — check the package README's support table before
enabling them.

## Thinking models

Qwen3 and DeepSeek R1 emit reasoning in `<think>` tags. Pass `isThinking` so the
tags are handled rather than shown to the user:

```dart
final chat = await model.createChat(isThinking: true, modelType: ModelType.qwen3);
```

With `isThinking: false` on Qwen3 the tags are stripped automatically.

## Vision and audio

Declare support at model creation, then attach bytes to a message:

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  supportImage: true,
);
await session.addQueryChunk(
  Message(text: 'What is in this photo?', isUser: true, imageBytes: bytes),
);
```

Multimodal models need a much larger context than text-only ones — an image is
worth hundreds of tokens. Start at 4096.

## Sessions are not free

Model loading is expensive; session creation is cheap by comparison. Load the
model once and keep it, create and close a session per interaction. Do not call
`getActiveModel` per message.

`getActiveModel` returns a process-wide singleton. Calling it again with
different runtime arguments rebuilds it and closes the previous instance — so a
handle you are still holding becomes unusable. Decide the runtime configuration
once.
