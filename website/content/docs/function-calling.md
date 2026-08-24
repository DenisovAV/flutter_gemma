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
- **SmolLM3 3B** — text generation with reasoning, no function calling.
- **Phi-4 Mini Reasoning** — reasoning model, no function calling.
- **FastVLM 0.5B** — vision model, no function calling.
- **Qwen2-VL 2B** — vision model, no function calling.
- **SmolVLM2 500M** — vision model, no function calling.
- **LLaVA-OneVision 0.5B** — vision model, no function calling.

<Info>
When you pass tools to an unsupported model, the plugin logs a warning and
ignores the tools — the model still works normally for text generation. Check the
`supportsFunctionCalls` property in your model configuration.
</Info>

### Built-in AI (OS models)

[Built-in AI](/docs/builtin-ai) models — Gemini Nano (Android), Apple Foundation
Models (iOS/macOS), and the Chrome Prompt API (Web) — also support function
calling, but it is **prompt-based**: these OS models don't expose a usable
structured tool API, so core `InferenceChat` weaves the tool definitions into
the prompt and parses the calls back out of the model's text. You declare tools
the same way (see below). Gemini Nano handles single-turn tool calls; multi-turn
agent chaining is **not** supported on Web.

## Declaring tools

Describe each function as a `Tool` — a `name`, a `description`, and a
JSON-Schema `parameters` map — then pass the list to `createChat` (or
`createSession`) together with `supportsFunctionCalls: true`:

```dart
final tools = [
  const Tool(
    name: 'change_background_color',
    description: 'Change the app background color.',
    parameters: {
      'type': 'object',
      'properties': {
        'color': {'type': 'string', 'description': 'A CSS color name.'},
      },
      'required': ['color'],
    },
  ),
];

final chat = await model.createChat(
  tools: tools,
  supportsFunctionCalls: true,
  toolChoice: ToolChoice.auto,
);
```

`ToolChoice` controls whether the model may call a tool:

- `ToolChoice.auto` (default) — the model decides.
- `ToolChoice.required` — the model must respond with a function call.
- `ToolChoice.none` — the model must not call any tool, even when tools are passed.

<Info>
`ToolChoice.required` is not supported by FunctionGemma — its prompt format has
no way to express the constraint, so it degrades to `auto` and logs a warning.
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

<Info>
A model can also request **several** calls at once — the stream then emits a
`ParallelFunctionCallResponse` carrying a `calls` list of `FunctionCallResponse`s.
`generateChatResponseWithTools` (below) handles this internally; a manual
listener must handle it too:

```dart
} else if (response is ParallelFunctionCallResponse) {
  for (final call in response.calls) {
    _handleFunctionCall(call);
  }
}
```
</Info>

Send the function result back to the model so it can continue:

```dart
final toolMessage = Message.toolResponse(
  toolName: 'change_background_color',
  response: {'status': 'success', 'color': 'blue'},
);
await chat.addQueryChunk(toolMessage);
final followUp = await chat.generateChatResponse();
```

### Or drive the whole loop in one call (recommended)

`InferenceChat.generateChatResponseWithTools` runs that whole cycle for you — it
streams the reply, and whenever the model calls a tool it invokes your
`onToolCall`, feeds the result back as a `Message.toolResponse`, and continues
until the model produces a final call-free answer (bounded by `maxToolTurns`).
You only implement the tools; the parse → execute → feed-back loop is handled.

```dart
final stream = chat.generateChatResponseWithTools(
  onToolCall: (call) async {
    // Run whatever tool the model asked for; return its result map.
    return switch (call.name) {
      'change_background_color' => {'status': 'success', 'color': call.args['color']},
      _ => {'error': 'unknown tool ${call.name}'},
    };
  },
  maxToolTurns: 8,           // safety cap on tool round-trips
  isCancelled: () => false,  // optional: return true to stop (e.g. barge-in)
);

await for (final response in stream) {
  if (response is TextResponse) print(response.token); // final-answer tokens
}
```

This is the same driver the voice loop uses: `VoiceSession.fromChat(…, onToolCall:)`
runs function calls inside a spoken turn through it (see
[Speech → Tool calling in the voice loop](/docs/speech#tool-calling-in-the-voice-loop)).

## Platform support

Function calling is supported on **Android, iOS, Web, and Desktop**. For Gemma 4,
the native function-call tokens are routed through the LiteRT-LM SDK chat-template
path (use `ModelType.gemma4`).

With the [Built-in AI](/docs/builtin-ai) engine (`flutter_gemma_builtin_ai`)
function calling is prompt-based rather than a native tool API — Gemini Nano
(Android) and Apple Foundation Models (iOS/macOS) handle single-turn tool calls;
on Web (Chrome Prompt API) multi-turn agent chaining is not supported.

<Warning>
Function calling / tool calls are **not** supported on the web `.litertlm` path
(`@litert-lm/core` early preview). For function calling on web, use MediaPipe
`.task` web models. See [Troubleshooting](/docs/troubleshooting).
</Warning>

See [Models](/docs/models#modeltype-reference) for the correct `ModelType` per
model family.
