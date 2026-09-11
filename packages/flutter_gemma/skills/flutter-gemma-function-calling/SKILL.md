---
name: flutter-gemma-function-calling
description: Use when adding function calling (tool calling) to a flutter_gemma chat — letting an on-device model call the app's own functions, declaring Tool objects, handling FunctionCallResponse, returning results with Message.toolResponse, or running the built-in tool loop. Also use when the model describes an action in prose instead of calling the tool, or a switch over ModelResponse fails to compile. For plain chat, use flutter-gemma-inference.
---

# Function calling with flutter_gemma

## Rules

1. `createChat` needs three arguments: `tools`, `supportsFunctionCalls: true` and `modelType`. Without the flag the tools are dropped with a debug-only warning; without the type the call format cannot be derived.
2. Switch over all four `ModelResponse` subtypes. It is sealed — a switch that leaves out `ThinkingResponse` does not compile.
3. Return tool results as data, errors included. Never throw from a tool.
4. Prefer `generateChatResponseWithTools` to a hand-written loop.
5. Use a tool-capable model: Gemma 4, Gemma 3 1B, FunctionGemma, Phi-4 Mini, Qwen 2.5, Qwen3, DeepSeek R1. Gemma 3 270M and SmolLM cannot call tools.

## Declare a tool

`parameters` is a JSON Schema object. The model matches the user's intent against `description`, so write it as an action and describe every parameter.

```dart
const changeColor = Tool(
  name: 'change_color',
  description: 'Change the app background colour.',
  parameters: {
    'type': 'object',
    'properties': {
      'color': {'type': 'string', 'description': 'A colour name, e.g. red.'},
    },
    'required': ['color'],
  },
);
```

## Open the chat

```dart
final chat = await model.createChat(
  tools: myTools,
  supportsFunctionCalls: true,
  modelType: ModelType.gemma4,
);
```

## The built-in loop

It calls your handler for each tool call, feeds the result back, and continues until the model answers in text or `maxToolTurns` is reached.

```dart
await chat.addQueryChunk(Message(text: prompt, isUser: true));
await for (final r in chat.generateChatResponseWithTools(
  onToolCall: (call) => runTool(call.name, call.args),
  maxToolTurns: 8,
)) {
  if (r is TextResponse) stdout.write(r.token);
}
```

## Handling calls yourself

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
    for (final call in calls) {
      final result = await runTool(call.name, call.args);
      await chat.addQueryChunk(
        Message.toolResponse(toolName: call.name, response: result),
      );
    }
    final afterAll = await chat.generateChatResponse();
  case TextResponse(:final token):
    print(token); // the model chose to answer directly — a valid outcome
  case ThinkingResponse():
    break;
}
```

## Errors are results

```dart
await chat.addQueryChunk(
  Message.toolResponse(
    toolName: 'change_color',
    response: {'error': 'unknown colour: mauvish'},
  ),
);
```

The model can recover from an error it can read. An exception thrown out of a tool ends the turn instead.

## Traps

**Model answers in prose**
- Symptom: "I would change the colour to red" instead of a call.
- Fix: check `supportsFunctionCalls: true` and `modelType`, then check the model is tool-capable.

**Raw markers in the text**
- Symptom: `<|tool_call>` or `<tool_call|>` appears in `TextResponse` tokens.
- Fix: `modelType` does not match the installed model.

## Web

Function calling works on the `.litertlm` web engine. Close each chat before creating the next one: a chat left open makes the following one fail with `Invalid token at state N`.

```dart
await chat.close();
final next = await model.createChat(
  tools: myTools,
  supportsFunctionCalls: true,
  modelType: ModelType.gemma4,
);
```
