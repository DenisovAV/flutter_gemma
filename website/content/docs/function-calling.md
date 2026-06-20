---
title: Function Calling
description: Let on-device models call external functions and integrate with other services.
image: https://fluttergemma.dev/images/og-image.png
---

Function calling lets a model request that your app run an external function —
for example, changing the UI, querying a database, or calling another service —
and then continue the conversation with the result.

## Supported models

### Models with function calling support

- **Gemma 4** (E2B, E4B) — full support (native function-call tokens).
- **Gemma3n** (E2B, E4B) — full support.
- **Gemma 3 1B** — function calling support.
- **FunctionGemma 270M** — Google's specialized function-calling model.
- **DeepSeek R1** — function calling + thinking mode.
- **Qwen** models (0.5B, 0.6B, 1.5B) — full support.
- **Phi-4 Mini** — advanced reasoning with function calling.

### Models without function calling support

- **Gemma 3 270M** — text generation only.
- **SmolLM 135M** — text generation only.
- **FastVLM 0.5B** — vision model, no function calling.

<Info>
When you pass tools to an unsupported model, the plugin logs a warning and
ignores the tools — the model still works normally for text generation. Check the
`supportsFunctionCalls` property in your model configuration.
</Info>

## Handling function calls

When the model wants to call a function, the response stream emits a
`FunctionCallResponse` with the function name and arguments. Execute it, then send
a `Message.toolResponse(...)` back to the model:

```dart
chat.generateChatResponseAsync().listen((response) {
  if (response is TextResponse) {
    // Regular text token
    print('Text token: ${response.token}');
  } else if (response is FunctionCallResponse) {
    // Model wants to call a function
    print('Function: ${response.name}');
    print('Arguments: ${response.args}');
    _handleFunctionCall(response);
  }
});
```

Send the function result back to the model so it can continue:

```dart
final toolMessage = Message.toolResponse(
  toolName: 'change_background_color',
  response: {'status': 'success', 'color': 'blue'},
);
await chat.addQueryChunk(toolMessage);
final followUp = await chat.generateChatResponse();
```

## Platform support

Function calling is supported on **Android, iOS, Web, and Desktop**. For Gemma 4,
the native function-call tokens are routed through the LiteRT-LM SDK chat-template
path (use `ModelType.gemma4`).

<Warning>
Function calling / tool calls are **not** supported on the web `.litertlm` path
(`@litert-lm/core` early preview). For function calling on web, use MediaPipe
`.task` web models. See [Troubleshooting](/docs/troubleshooting).
</Warning>

See [Models](/docs/models#modeltype-reference) for the correct `ModelType` per
model family.
