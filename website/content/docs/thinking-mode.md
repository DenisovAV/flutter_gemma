---
title: Thinking Mode
description: View the reasoning process of DeepSeek, Gemma 4, Qwen3, SmolLM3, and Phi-4 Mini Reasoning models with thinking blocks.
image: https://fluttergemma.dev/images/og-image.png
---

Thinking mode exposes the model's internal reasoning process as a separate
response channel, so you can show a "thinking" bubble in your UI before the final
answer.

## Supported models

- **Gemma 4** (E2B, E4B) — `ModelType.gemma4`
- **DeepSeek R1** — `ModelType.deepSeek`
- **Qwen3 0.6B** — `ModelType.qwen3`; generates thinking by default, tags are stripped when `isThinking: false`.

Enable it with `isThinking: true` and the matching `ModelType`.

<Warning>
The reasoning channel is parsed per `ModelType`, and `ModelType.general` has no
parser at all. Models that reason but run as `general` — **SmolLM3 3B**,
**Phi-4 Mini Reasoning** — emit no `ThinkingResponse`, and their thinking tags
are not stripped either: the raw blocks arrive inside the answer as ordinary
`TextResponse` tokens. Strip them yourself, or don't advertise a thinking UI for
those models.
</Warning>

## Handling thinking responses

The model emits a `ThinkingResponse` (with `response.content`) for its reasoning,
alongside regular `TextResponse` tokens for the final answer:

```dart
chat.generateChatResponseAsync().listen((response) {
  if (response is ThinkingResponse) {
    // Model's reasoning process
    print('Thinking: ${response.content}');
    _showThinkingBubble(response.content);
  } else if (response is TextResponse) {
    // The final answer
    print('Text token: ${response.token}');
  }
});
```

You can also create a thinking message manually:

```dart
final thinkingMessage = Message.thinking(text: "Let me analyze this problem...");
```

## Platform support

| Platform | Thinking Mode |
|---|---|
| Android | ✅ Full |
| iOS | ✅ Full |
| Desktop (macOS/Windows/Linux) | ✅ Full |
| Web | ⚠️ Qwen3 / DeepSeek R1 only |

<Warning>
On web, Qwen3 and DeepSeek R1 reasoning **is** separated out of the token
stream: that split is pure Dart and runs on every platform. Gemma 4's thinking
is different — it needs the native `extraContext` channel. MediaPipe `.task` web
has no such hook and warns that `enableThinking` is ignored; the web `.litertlm`
path does pass `extra_context` to `@litert-lm/core`, but it has never been
verified end to end, so treat Gemma 4 thinking on web as unsupported until it
is.
</Warning>

## Advanced: ModelThinkingFilter

For custom inference implementations, `ModelThinkingFilter` cleans model outputs —
removing model-specific tokens. This is handled automatically by the chat API,
but is available if you need it:

```dart
import 'package:flutter_gemma/core/extensions.dart';

String cleanedResponse = ModelThinkingFilter.cleanResponse(
  rawResponse,
  isThinking: true,
  modelType: ModelType.deepSeek,
  fileType: ModelFileType.task,
);

// The filter removes model-specific tokens like:
// - <end_of_turn> tags (Gemma models)
// - <think>...</think> blocks (DeepSeek)
// - <|channel>thought\n...<channel|> blocks (Gemma 4 E2B/E4B)
// - extra whitespace and formatting
```
