---
title: Thinking Mode
description: View the reasoning process of DeepSeek, Gemma 4, Qwen3, SmolLM3, and Phi-4 Mini Reasoning models with thinking blocks.
image: https://fluttergemma.dev/images/og-image.png
---

Thinking mode exposes the model's internal reasoning process as a separate
response channel, so you can show a "thinking" bubble in your UI before the final
answer.

## Supported models

- **Gemma 4** (E2B, E4B)
- **DeepSeek R1**
- **Qwen3 0.6B** — generates thinking by default; tags are stripped when `isThinking: false`.
- **SmolLM3 3B** — multilingual small LLM with a reasoning mode.
- **Phi-4 Mini Reasoning** — Phi-4 Mini tuned for step-by-step reasoning.

Enable it with `isThinking: true` on the matching `ModelType`.

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
| Web | ❌ Not supported |

<Warning>
Thinking mode is **not supported on Web yet**. MediaPipe `.task` web has no
`extraContext` hook, and the web `.litertlm` path (`@litert-lm/core`) does not
wire the `extraContext` thinking channel. Thinking mode for Gemma 4 is available
on Android, iOS, and Desktop only.
</Warning>

## Advanced: ModelThinkingFilter

For custom inference implementations, `ModelThinkingFilter` cleans model outputs —
removing model-specific tokens. This is handled automatically by the chat API,
but is available if you need it:

```dart
import 'package:flutter_gemma/core/extensions.dart';

String cleanedResponse = ModelThinkingFilter.cleanResponse(
  rawResponse,
  ModelType.deepSeek,
);

// The filter removes model-specific tokens like:
// - <end_of_turn> tags (Gemma models)
// - <think>...</think> blocks (DeepSeek)
// - <|channel>thought\n...<channel|> blocks (Gemma 4 E2B/E4B)
// - extra whitespace and formatting
```
