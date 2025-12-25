# FunctionGemma Implementation in flutter_gemma

Complete technical documentation of how FunctionGemma function calling works in the flutter_gemma plugin.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        flutter_gemma                             │
├─────────────────────────────────────────────────────────────────┤
│  InferenceChat (lib/core/chat.dart)                             │
│    ├── Tools prompt generation                                   │
│    ├── Message formatting                                        │
│    ├── Response streaming                                        │
│    └── Function call detection                                   │
├─────────────────────────────────────────────────────────────────┤
│  FunctionCallParser (lib/core/function_call_parser.dart)        │
│    ├── FunctionGemma format parsing                              │
│    ├── JSON format parsing (DeepSeek, Qwen, etc.)               │
│    └── Streaming detection                                       │
├─────────────────────────────────────────────────────────────────┤
│  ModelType & Extensions (lib/core/model.dart, extensions.dart)  │
│    ├── Model-specific turn markers                               │
│    ├── FunctionGemma special tokens                              │
│    └── Prompt formatting                                         │
├─────────────────────────────────────────────────────────────────┤
│  Native Layer (MediaPipe LLM Inference)                         │
│    ├── iOS: MediaPipeTasksGenAI                                  │
│    ├── Android: MediaPipe GenAI                                  │
│    └── Web: @mediapipe/tasks-genai WASM                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Model Types

### ModelType Enum (lib/core/model.dart)

```dart
enum ModelType {
  gemmaIt,       // Standard Gemma instruction-tuned
  gemma,         // Base Gemma
  functionGemma, // FunctionGemma 270M (special format)
  deepSeek,      // DeepSeek (JSON format + thinking)
  qwen,          // Qwen (JSON format)
  llama,         // Llama (JSON format)
  hammer,        // Hammer (JSON format)
  phi,           // Phi (JSON format)
  general,       // Generic model
}
```

### FunctionGemma vs JSON Models

| Feature | FunctionGemma | JSON Models (DeepSeek, Qwen, etc.) |
|---------|---------------|-----------------------------------|
| Format | Custom tags | Standard JSON |
| Declarations | Required at runtime | Optional (in prompt) |
| Output | `<start_function_call>call:name{params}` | `{"name": "...", "parameters": {...}}` |
| Stop token | `<start_function_response>` | End of JSON |

---

## FunctionGemma Special Tokens (lib/core/extensions.dart)

```dart
// Turn markers
const String startTurn = '<start_of_turn>';
const String endTurn = '<end_of_turn>';

// Role prefixes
const String userPrefix = 'user';
const String modelPrefix = 'model';
const String developerPrefix = 'developer';  // NOT 'system'!

// FunctionGemma specific
const String functionGemmaStartDecl = '<start_function_declaration>';
const String functionGemmaEndDecl = '<end_function_declaration>';
const String functionGemmaStartCall = '<start_function_call>';
const String functionGemmaEndCall = '<end_function_call>';
const String functionGemmaStartResponse = '<start_function_response>';
const String functionGemmaEndResponse = '<end_function_response>';
const String functionGemmaEscape = '<escape>';
```

---

## Tools Prompt Generation (lib/core/chat.dart)

### Routing by ModelType

```dart
String _createToolsPrompt() {
  if (tools.isEmpty) return '';

  return switch (modelType) {
    ModelType.functionGemma => _createFunctionGemmaToolsPrompt(),
    _ => _createJsonToolsPrompt(),  // All other models use JSON
  };
}
```

### FunctionGemma Tools Prompt

```dart
String _createFunctionGemmaToolsPrompt() {
  final toolsPrompt = StringBuffer();

  // Developer turn (NOT system!)
  toolsPrompt.write('$startTurn$developerPrefix\n');
  toolsPrompt.writeln(
    'You are a model that can do function calling with the following functions'
  );

  for (final tool in tools) {
    // Start declaration
    toolsPrompt.write(functionGemmaStartDecl);
    toolsPrompt.write('declaration:${tool.name}{');

    // Description with escape tokens
    toolsPrompt.write(
      'description:$functionGemmaEscape${tool.description}$functionGemmaEscape'
    );

    // Parameters in FunctionGemma format
    final properties = tool.parameters['properties'] as Map<String, dynamic>?;
    if (properties != null && properties.isNotEmpty) {
      toolsPrompt.write(',parameters:{properties:{');

      final paramEntries = <String>[];
      properties.forEach((name, schema) {
        final type = (schema['type'] as String?)?.toUpperCase() ?? 'STRING';
        final desc = schema['description'];
        if (desc != null) {
          paramEntries.add(
            '$name:{description:$functionGemmaEscape$desc$functionGemmaEscape,'
            'type:$functionGemmaEscape$type$functionGemmaEscape}'
          );
        } else {
          paramEntries.add('$name:{type:$functionGemmaEscape$type$functionGemmaEscape}');
        }
      });

      toolsPrompt.write(paramEntries.join(','));
      toolsPrompt.write('},type:${functionGemmaEscape}OBJECT$functionGemmaEscape}');
    }

    toolsPrompt.writeln('}$functionGemmaEndDecl');
  }

  toolsPrompt.write('$endTurn\n');
  return toolsPrompt.toString();
}
```

**Generated prompt example:**
```
<start_of_turn>developer
You are a model that can do function calling with the following functions
<start_function_declaration>declaration:change_background_color{description:<escape>Changes background color<escape>,parameters:{properties:{color:{description:<escape>The color name<escape>,type:<escape>STRING<escape>}},type:<escape>OBJECT<escape>}}<end_function_declaration>
<end_of_turn>
```

### JSON Tools Prompt (other models)

```dart
String _createJsonToolsPrompt() {
  final toolsPrompt = StringBuffer();
  toolsPrompt.writeln(
    'You have access to functions. ONLY call a function when the user '
    'explicitly requests an action or command.'
  );
  toolsPrompt.writeln(
    'When you do need to call a function, respond with ONLY the JSON: '
    '{"name": function_name, "parameters": {argument: value}}'
  );
  toolsPrompt.writeln('<tool_code>');
  for (final tool in tools) {
    toolsPrompt.writeln(
      '${tool.name}: ${tool.description} Parameters: ${jsonEncode(tool.parameters)}'
    );
  }
  toolsPrompt.writeln('</tool_code>');
  return toolsPrompt.toString();
}
```

---

## Message Handling with Tools

### First Message with Tools (lib/core/chat.dart)

```dart
Future<void> addQueryChunk(Message message, [bool noTool = false]) async {
  var messageToSend = message;

  // Only add tools prompt for FIRST user text message
  if (message.isUser &&
      message.type == MessageType.text &&
      !_toolsInstructionSent &&
      tools.isNotEmpty &&
      !noTool &&
      supportsFunctionCalls) {

    _toolsInstructionSent = true;
    final toolsPrompt = _createToolsPrompt();

    // FunctionGemma: manually construct full prompt with turn markers
    if (modelType == ModelType.functionGemma) {
      final newText = '$toolsPrompt$startTurn$userPrefix\n${message.text}\n$endTurn\n$startTurn$modelPrefix\n';
      messageToSend = message.copyWith(text: newText);
    } else {
      // Other models: prepend tools prompt
      final newText = '$toolsPrompt\n${message.text}';
      messageToSend = message.copyWith(text: newText);
    }
  }

  await session.addQueryChunk(messageToSend);
  _fullHistory.add(messageToSend);
  _modelHistory.add(messageToSend);
}
```

### Full FunctionGemma Conversation Flow

```
1. User sends: "make it red"

2. Plugin constructs:
   <start_of_turn>developer
   You are a model that can do function calling with the following functions
   <start_function_declaration>declaration:change_background_color{...}<end_function_declaration>
   <end_of_turn>
   <start_of_turn>user
   make it red
   <end_of_turn>
   <start_of_turn>model

3. Model responds:
   <start_function_call>call:change_background_color{color:<escape>red<escape>}<end_function_call><start_function_response>

4. Model STOPS at <start_function_response> (configured as stop token in .task)

5. Plugin parses function call, executes it, returns result

6. Plugin sends function response:
   <start_function_response>{"result": "Background changed to red"}<end_function_response>
   <end_of_turn>
   <start_of_turn>model

7. Model generates natural language response
```

---

## Function Call Parsing (lib/core/function_call_parser.dart)

### Parser Entry Point

```dart
class FunctionCallParser {
  static FunctionCallResponse? parse(
    String response, {
    required ModelType modelType,
  }) {
    return switch (modelType) {
      ModelType.functionGemma => _parseFunctionGemmaFormat(response),
      _ => _parseJsonFormat(response),
    };
  }
}
```

### FunctionGemma Format Parsing

**Input format:**
```
<start_function_call>call:change_background_color{color:<escape>red<escape>}<end_function_call>
```

**Parsing logic:**
```dart
static FunctionCallResponse? _parseFunctionGemmaFormat(String response) {
  // Extract content between tags
  final startTag = '<start_function_call>';
  final endTag = '<end_function_call>';

  final startIndex = response.indexOf(startTag);
  if (startIndex == -1) return null;

  final endIndex = response.indexOf(endTag, startIndex);
  final content = response.substring(
    startIndex + startTag.length,
    endIndex != -1 ? endIndex : response.length,
  );

  // Parse "call:function_name{params}"
  if (!content.startsWith('call:')) return null;

  final colonIndex = content.indexOf('{');
  if (colonIndex == -1) return null;

  final functionName = content.substring(5, colonIndex);  // After "call:"
  final paramsStr = content.substring(colonIndex);

  // Parse FunctionGemma params format to Map
  final parameters = _parseFunctionGemmaParams(paramsStr);

  return FunctionCallResponse(
    name: functionName,
    parameters: parameters,
  );
}
```

### FunctionGemma Parameters Parsing

**Input:** `{color:<escape>red<escape>}`
**Output:** `{"color": "red"}`

```dart
static Map<String, dynamic> _parseFunctionGemmaParams(String paramsStr) {
  final result = <String, dynamic>{};

  // Remove outer braces
  var content = paramsStr.trim();
  if (content.startsWith('{')) content = content.substring(1);
  if (content.endsWith('}')) content = content.substring(0, content.length - 1);

  // Split by comma (but not inside nested braces)
  final pairs = _splitParams(content);

  for (final pair in pairs) {
    final colonIndex = pair.indexOf(':');
    if (colonIndex == -1) continue;

    final key = pair.substring(0, colonIndex).trim();
    var value = pair.substring(colonIndex + 1).trim();

    // Remove <escape> tokens
    value = value.replaceAll('<escape>', '');

    result[key] = value;
  }

  return result;
}
```

### JSON Format Parsing (DeepSeek, Qwen, etc.)

```dart
static FunctionCallResponse? _parseJsonFormat(String response) {
  // Find JSON object in response
  final jsonStart = response.indexOf('{');
  final jsonEnd = response.lastIndexOf('}');

  if (jsonStart == -1 || jsonEnd == -1) return null;

  try {
    final jsonStr = response.substring(jsonStart, jsonEnd + 1);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;

    // Expected format: {"name": "...", "parameters": {...}}
    final name = json['name'] as String?;
    final parameters = json['parameters'] as Map<String, dynamic>?;

    if (name == null) return null;

    return FunctionCallResponse(
      name: name,
      parameters: parameters ?? {},
    );
  } catch (e) {
    return null;
  }
}
```

### Streaming Detection

```dart
static bool isFunctionCallComplete(String buffer, {required ModelType modelType}) {
  return switch (modelType) {
    ModelType.functionGemma =>
      buffer.contains('<end_function_call>') ||
      buffer.contains('<start_function_response>'),
    _ => _isJsonComplete(buffer),
  };
}

static bool _isJsonComplete(String buffer) {
  final trimmed = buffer.trim();
  if (!trimmed.startsWith('{')) return false;

  int braceCount = 0;
  for (final char in trimmed.runes) {
    if (char == '{'.codeUnitAt(0)) braceCount++;
    if (char == '}'.codeUnitAt(0)) braceCount--;
  }

  return braceCount == 0 && trimmed.endsWith('}');
}
```

---

## Streaming Response Handling (lib/core/chat.dart)

### Stream Processing with Function Detection

```dart
Stream<ModelResponse> generateChatResponseAsync() async* {
  final buffer = StringBuffer();
  String funcBuffer = '';  // Buffer for potential function call

  await for (final response in filteredStream) {
    if (response is TextResponse) {
      final token = response.token;

      if (tools.isNotEmpty && supportsFunctionCalls) {
        if (funcBuffer.isNotEmpty) {
          // Already buffering potential function call
          funcBuffer += token;

          // Check if complete
          if (FunctionCallParser.isFunctionCallComplete(funcBuffer, modelType: modelType)) {
            final functionCall = FunctionCallParser.parse(funcBuffer, modelType: modelType);
            if (functionCall != null) {
              yield functionCall;  // Emit function call
              funcBuffer = '';
              continue;
            }
          }

          // Buffer too long without completion - flush as text
          if (funcBuffer.length > 150) {
            yield TextResponse(funcBuffer);
            funcBuffer = '';
          }
          continue;
        } else {
          // Check if token starts JSON/function call
          if (token.contains('{') || token.contains('```')) {
            funcBuffer = token;  // Start buffering
            continue;
          }
        }
      }

      // Normal text - emit immediately
      yield response;
      buffer.write(token);
    }
  }

  // End of stream - process remaining buffer
  if (funcBuffer.isNotEmpty) {
    final functionCall = FunctionCallParser.parse(funcBuffer, modelType: modelType);
    if (functionCall != null) {
      yield functionCall;
    } else {
      yield TextResponse(funcBuffer);
    }
  }
}
```

---

## Model Response Types (lib/core/model_response.dart)

```dart
sealed class ModelResponse {
  const ModelResponse();
}

class TextResponse extends ModelResponse {
  final String token;
  const TextResponse(this.token);
}

class FunctionCallResponse extends ModelResponse {
  final String name;
  final Map<String, dynamic> parameters;

  const FunctionCallResponse({
    required this.name,
    required this.parameters,
  });
}

class ThinkingResponse extends ModelResponse {
  final String content;
  const ThinkingResponse(this.content);
}
```

---

## Tool Definition (lib/core/tool.dart)

```dart
class Tool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;  // JSON Schema format

  const Tool({
    required this.name,
    required this.description,
    required this.parameters,
  });
}
```

**Usage example:**
```dart
final tools = [
  Tool(
    name: 'change_background_color',
    description: 'Changes the app background color',
    parameters: {
      'type': 'object',
      'properties': {
        'color': {
          'type': 'string',
          'description': 'The color name (red, green, blue, etc.)',
        },
      },
      'required': ['color'],
    },
  ),
];
```

---

## Example App Integration (example/lib/models/model.dart)

### FunctionGemma Model Definition

```dart
functionGemma_270M(
  baseUrl: 'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task',
  filename: 'functiongemma-270M-it.task',
  displayName: 'FunctionGemma 270M IT',
  size: '284MB',
  needsAuth: false,
  preferredBackend: PreferredBackend.gpu,
  modelType: ModelType.functionGemma,  // CRITICAL: Enables FunctionGemma parsing
  temperature: 1.0,
  topK: 64,
  topP: 0.95,
  maxTokens: 1024,
  supportsFunctionCalls: true,  // Enables function calling UI
),
```

### Chat Screen Usage

```dart
// Create chat with tools
final chat = await model.createChat(
  tools: [
    Tool(name: 'change_background_color', ...),
    Tool(name: 'show_alert', ...),
  ],
);

// Send message
await chat.addQuery(Message.text(text: userInput, isUser: true));

// Get response (may be text or function call)
await for (final response in chat.generateChatResponseAsync()) {
  if (response is TextResponse) {
    // Display text
    appendToUI(response.token);
  } else if (response is FunctionCallResponse) {
    // Execute function
    final result = await executeFunction(response.name, response.parameters);

    // Send result back to model
    await chat.addQuery(Message.toolResponse(
      toolName: response.name,
      result: result,
    ));

    // Get model's natural language response
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) appendToUI(r.token);
    }
  }
}
```

---

## Platform-Specific Notes

### iOS
- MediaPipeTasksGenAI framework
- Minimum iOS 16.0
- GPU acceleration via Metal

### Android
- MediaPipe GenAI library
- GPU via OpenCL (optional)
- CPU fallback available

### Web
- @mediapipe/tasks-genai WASM
- v0.10.25 CDN
- WebGL acceleration

---

## Debugging

### Enable logging in chat.dart

```dart
debugPrint('--- Sending to Native ---');
debugPrint('History:\n$historyForLogging');
debugPrint('Current Message:\n${messageToSend.text}');
debugPrint('-------------------------');
```

### Common Issues

1. **Model not calling functions**
   - Check `supportsFunctionCalls: true` in model config
   - Check `modelType: ModelType.functionGemma`
   - Verify tools prompt is being sent

2. **Function call not parsed**
   - Check model output format matches expected
   - FunctionGemma: `<start_function_call>call:name{params}`
   - JSON: `{"name": "...", "parameters": {...}}`

3. **Streaming issues**
   - Buffer may be flushed prematurely (>150 chars)
   - Check `isFunctionCallComplete` logic

---

## Tests (test/function_gemma_parser_test.dart)

```dart
void main() {
  group('FunctionCallParser', () {
    test('parses FunctionGemma format', () {
      final response = '<start_function_call>call:change_background_color{color:<escape>red<escape>}<end_function_call>';
      final result = FunctionCallParser.parse(response, modelType: ModelType.functionGemma);

      expect(result, isNotNull);
      expect(result!.name, equals('change_background_color'));
      expect(result.parameters['color'], equals('red'));
    });

    test('parses JSON format', () {
      final response = '{"name": "show_alert", "parameters": {"message": "hello"}}';
      final result = FunctionCallParser.parse(response, modelType: ModelType.qwen);

      expect(result, isNotNull);
      expect(result!.name, equals('show_alert'));
      expect(result.parameters['message'], equals('hello'));
    });
  });
}
```
