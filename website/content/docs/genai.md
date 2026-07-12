---
title: genai_primitives
description: Use the Flutter team's genai_primitives ChatMessage types with flutter_gemma — sendMessage, generateContent, streaming, tools, and thinking.
image: https://fluttergemma.dev/images/og-image.png
---

[genai_primitives](https://pub.dev/packages/genai_primitives) is the Flutter
team's set of standard chat types — `ChatMessage`, `TextPart`, `DataPart`,
`ToolPart`, and friends. flutter_gemma speaks them directly, so you can drive an
on-device chat with the same message types you'd use anywhere else in the
Flutter AI ecosystem, and move a conversation between providers without
rewriting it.

The surface is a small extension on `InferenceChat`. Import the side barrel:

```dart
import 'package:flutter_gemma/genai.dart';
```

That one import re-exports the genai_primitives types too, so you don't need to
add `genai_primitives` to your own `pubspec.yaml` — `ChatMessage`, `TextPart`,
and the rest come with it.

## The four entry points

`genai.dart` adds these to any `InferenceChat`:

- `sendMessage(ChatMessage)` — send one turn, get the whole model turn back as a
  `role: model` `ChatMessage`.
- `sendMessageStream(ChatMessage)` — the same, streamed as partial
  `ChatMessage`s, one per delta.
- `generateContent(List<ChatMessage>)` — stage a whole list of turns into the
  chat, then generate once.
- `generateContentStream(List<ChatMessage>)` — the streamed variant.

Every method returns (or yields) `ChatMessage`s with `role: model`. Read the
answer out of its parts.

## Text

```dart
final chat = await model.createChat();

final reply = await chat.sendMessage(
  ChatMessage.user('Say hello in one word.'),
);

final text = reply.parts.whereType<TextPart>().map((p) => p.text).join();
print(text);
```

Streaming is the same call, awaited over:

```dart
await for (final chunk in chat.sendMessageStream(
  ChatMessage.user('Count to three.'),
)) {
  final token = chunk.parts.whereType<TextPart>().map((p) => p.text).join();
  print(token);
}
```

## Images and audio

Attach media as parts. Inline bytes go in a `DataPart` with a matching MIME
type; a `LinkPart` is fetched for you (`data:`, `file:`, and `http(s):` URLs are
supported). Create the chat with the capability the model needs, or the send
throws rather than silently dropping the media.

```dart
final chat = await model.createChat(supportImage: true);

final reply = await chat.sendMessage(
  ChatMessage.user(
    '',
    parts: [
      TextPart('Describe this image briefly'),
      DataPart(imageBytes, mimeType: 'image/jpeg'),
    ],
  ),
);
```

Audio is identical with `supportAudio: true` and an `audio/*` MIME type. One
audio part per message.

## Thinking

Create the chat with `isThinking: true`. The model turn comes back with its
reasoning in a `ThinkingPart` alongside the answer's `TextPart`:

```dart
final chat = await model.createChat(isThinking: true);

final reply = await chat.sendMessage(
  ChatMessage.user('Why is the sky blue?'),
);

final thinking = reply.parts.whereType<ThinkingPart>().map((p) => p.text).join();
final answer = reply.parts.whereType<TextPart>().map((p) => p.text).join();
```

When you feed a prior model turn back in as history, its `ThinkingPart` is
stripped automatically — the model is re-fed the answer, not the reasoning, so
you can pass a returned turn straight back into `generateContent`.

## Tool calls

Create the chat with your tools, then read tool calls out of the reply's
`ToolPart`s and send the result back as a `ToolPart.result`:

```dart
final chat = await model.createChat(
  supportsFunctionCalls: true,
  tools: const [getWeatherTool],
  modelType: ModelType.gemma4,
);

final reply = await chat.sendMessage(
  ChatMessage.user('What is the weather like in Berlin?'),
);

final calls = reply.parts
    .whereType<ToolPart>()
    .where((p) => p.kind == ToolPartKind.call)
    .toList();

if (calls.isNotEmpty) {
  final call = calls.first;
  // ... run the tool, then return its result as the next turn:
  final followUp = await chat.sendMessage(
    ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        ToolPart.result(
          callId: call.callId,
          toolName: call.toolName,
          result: const {'temperature_c': 18, 'condition': 'partly cloudy'},
        ),
      ],
    ),
  );
}
```

## Staging a batch

`generateContent` stages a list of turns into the chat before generating — use
it to seed prior context in one call:

```dart
final reply = await chat.generateContent([
  ChatMessage.user('Remember the number 7.'),
  ChatMessage.model('Got it.'),
  ChatMessage.user('What number did I say?'),
]);
```

## Rules and edge cases

- `sendMessage` takes **user input**. Passing a `role: model` message throws —
  a model turn is output; stage prior model turns with `generateContent`.
- A `ThinkingPart` on a **user** message throws (thoughts are model output); on
  a **model** turn it is stripped as history.
- A `system`-role message throws — set the system prompt via
  `createChat(systemInstruction: ...)` instead.
- Missing capability throws: sending an image to a chat created without
  `supportImage`, audio without `supportAudio`, or a tool part without
  `supportsFunctionCalls` fails loudly rather than dropping the content.

This surface lives behind its own `genai.dart` barrel so genai_primitives'
pre-1.0 churn stays contained — the rest of flutter_gemma's API is unaffected by
it.
