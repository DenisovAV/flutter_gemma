---
name: flutter-gemma-tools
description: Use when giving a flutter_gemma model access to functions — declaring Tool objects, calling createChat with tools, handling FunctionCallResponse, or feeding a tool result back. Both supportsFunctionCalls and modelType are required or the tools are dropped with no error.
---

# Function calling with flutter_gemma

## Three arguments, not one

Passing `tools` alone does nothing. Without `supportsFunctionCalls` the tools
are dropped with a debug-only warning; without `modelType` the correct call
format cannot be derived. All three are required:

```dart
final chat = await model.createChat(
  tools: myTools,
  supportsFunctionCalls: true,
  modelType: ModelType.gemma4,
);
```

Get this wrong and the model answers in prose, describing what it would do
instead of calling anything. That looks like "the model is bad at tools" and is
actually a missing argument.

## Declaring a tool

`parameters` is a JSON Schema object:

```dart
const changeColor = Tool(
  name: 'change_color',
  description: 'Change the UI background colour.',
  parameters: {
    'type': 'object',
    'properties': {
      'color': {'type': 'string', 'description': 'A colour name like red.'},
    },
    'required': ['color'],
  },
);
```

The `description` is what the model matches the user's intent against. Write it
as an action, and describe every parameter — a bare `{'type': 'string'}` gives
the model nothing to reason with.

## The response is a type, not a string

`generateChatResponse()` returns `ModelResponse`. Switch on it:

```dart
final response = await chat.generateChatResponse();

switch (response) {
  case FunctionCallResponse(:final name, :final args):
    final result = await runTool(name, args);
    await chat.addQueryChunk(
      Message.toolResponse(toolName: name, response: result),
    );
    final followUp = await chat.generateChatResponse();

  case ParallelFunctionCallResponse(:final calls):
    // several calls in one turn — run them, then feed each result back
    for (final call in calls) { /* … */ }

  case TextResponse(:final token):
    // the model chose to answer directly, which is a valid outcome
}
```

Treat a plain `TextResponse` as normal. A model that calls a tool for every
message is worse than one that decides.

Streaming works the same way — `generateChatResponseAsync()` yields
`ModelResponse` events, and a `FunctionCallResponse` arrives as one of them.
Raw `<|tool_call>` markers must never appear in the text stream; if they do,
the model type is wrong.

## Feeding the result back

```dart
Message.toolResponse(
  toolName: 'change_color',
  response: {'status': 'success', 'applied_color': 'purple'},
)
```

The response map is serialised into the transcript, so keep it small and
factual. Return an error field rather than throwing — the model can recover
from `{'error': 'unknown colour'}` and cannot recover from an exception.

## Not every model supports tools

Check the package README's support table before enabling them. Gemma 4, Gemma
3 1B, FunctionGemma, Phi-4 Mini, Qwen 2.5/3 and DeepSeek R1 do; Gemma 3 270M
and SmolLM do not. Enabling tools on a model that cannot use them produces
prose, not an error.

## Escaped tokens in arguments

Some runtimes emit `<|"|>` escape markers inside argument strings. The package
strips them before the call reaches you, so `args` values should be clean —
if you see them, report it rather than stripping them yourself.

## Web

Function calling on the `.litertlm` web path works, but the constrained-decoding
grammar does not reset after a completed tool-call block: any subsequent turn in
that same chat aborts with `Invalid token at state N`. Until the upstream fix
lands, treat a tools-enabled web chat as single-turn — create a fresh chat after
a call. A conversation that never emits a call is unaffected.
