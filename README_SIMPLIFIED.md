# Flutter Gemma with Gemma 3 Nano & Multimodal Support

**Run Gemma AI models locally on Flutter apps with official MediaPipe GenAI v0.10.24**

Supports: [Gemma 2B](https://huggingface.co/google/gemma-2b-it), [Gemma 7B](https://huggingface.co/google/gemma-7b-it), [Gemma-2 2B](https://huggingface.co/google/gemma-2-2b-it), [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT), **[Gemma 3 Nano 1.5B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview)** ✨

## ✅ What's New in v0.9.0

- 🛠️ **Function Calling** - Models can call external functions (Gemma 3 Nano, DeepSeek)
- 🧠 **Thinking Mode** - View reasoning process with DeepSeek models
- 🖼️ **Multimodal Support** - Text + Image input with vision models
- 🚀 **Full Gemma 3 Nano Support** with MediaPipe GenAI v0.10.24
- ⚡ **Official CocoaPods** - No custom pods needed!
- 🎯 **GPU/CPU Backend Selection** works correctly
- 📱 **iOS & Android Compatible**

## Quick Start

### 1. Installation

```yaml
dependencies:
  flutter_gemma: ^0.9.0
```

### 2. iOS Setup

**Automatic Dependencies:**
The plugin automatically uses official MediaPipe CocoaPods:
- `MediaPipeTasksGenAI: 0.10.24`
- `MediaPipeTasksGenAIC: 0.10.24`

**Required iOS Configuration:**

1. **Set minimum iOS version** in `ios/Podfile`:
```ruby
platform :ios, '16.0'  # Required for MediaPipe GenAI
```

2. **Add memory entitlements** for large models in `ios/Runner/Runner.entitlements`:
```xml
<key>com.apple.developer.kernel.extended-virtual-addressing</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

3. **Enable file sharing** in `ios/Runner/Info.plist`:
```plist
<key>UIFileSharingEnabled</key>
<true/>
```

### 3. Android Setup (Automatic)

Uses official MediaPipe GenAI:
- `com.google.mediapipe:tasks-genai:0.10.24`
- `com.google.mediapipe:tasks-vision:0.10.24` (for multimodal support)

### 4. Basic Text Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// Initialize
final gemma = FlutterGemmaPlugin.instance;

// Set model path
await gemma.modelManager.setModelPath('path/to/gemma-3n-model.task');

// Create model with Gemma 3n optimized settings
final model = await gemma.createModel(
  modelType: ModelType.gemmaIt,
  preferredBackend: PreferredBackend.gpu, // or cpu
  maxTokens: 2048,
);

// Create chat
final chat = await model.createChat(
  temperature: 0.8, // default: 0.8
  randomSeed: 1, // default: 1
  topK: 40, // default: 1
  topP: 0.9, // optional nucleus sampling
  // tokenBuffer: 256, // default: 256
);

// Generate response
await chat.addQueryChunk(Message.text(text: "Hello!", isUser: true));
final response = await chat.generateChatResponse();
if (response is TextResponse) {
  print(response.token);
}
```

### 5. 🖼️ Multimodal Usage (NEW!)

```dart
import 'dart:typed_data'; // For Uint8List

// Create model with image support
final model = await gemma.createModel(
  modelType: ModelType.gemmaIt,
  supportImage: true, // Enable multimodal support
  maxNumImages: 1,
  maxTokens: 4096,
);

// Create chat with image support
final chat = await model.createChat(
  temperature: 0.8,
  randomSeed: 1,
  topK: 1,
  supportImage: true, // Enable images in chat
);

// Send text + image message
final imageBytes = await loadImageBytes(); // Your image loading method
await chat.addQueryChunk(Message.withImage(
  text: "What's in this image?",
  imageBytes: imageBytes,
  isUser: true,
));

final response = await chat.generateChatResponse();
if (response is TextResponse) {
  print(response.token);
}
```

### 6. 🛠️ Function Calling (NEW!)

```dart
// 1. Define tools (functions the model can call)
final List<Tool> tools = [
  const Tool(
    name: 'change_color',
    description: 'Changes the background color',
    parameters: {
      'type': 'object',
      'properties': {
        'color': {'type': 'string', 'description': 'Color name'},
      },
      'required': ['color'],
    },
  ),
];

// 2. Create chat with tools (works with Gemma 3 Nano and DeepSeek models)
final chat = await model.createChat(
  temperature: 0.8,
  randomSeed: 1,
  topK: 1,
  tools: tools,
  supportsFunctionCalls: true, // Auto-detected for supported models
  isThinking: true, // Enable thinking mode for DeepSeek
  modelType: ModelType.deepSeek, // Specify model type for DeepSeek
);

// 3. Handle different response types
chat.generateChatResponseAsync().listen((response) {
  if (response is TextResponse) {
    // Regular text from model
    print('Text: ${response.token}');
  } else if (response is FunctionCallResponse) {
    // Model wants to call a function
    print('Function: ${response.name}');
    print('Args: ${response.args}');
    
    // Execute function and send response back
    _handleFunctionCall(response);
  } else if (response is ThinkingResponse) {
    // Model's reasoning process (DeepSeek only)
    print('Thinking: ${response.content}');
    
    // Show thinking bubble in UI
    _showThinkingBubble(response.content);
  }
});
```

### 7. 🧠 Thinking Mode (DeepSeek Models)

```dart
// Create model with thinking support
final model = await gemma.createModel(
  modelType: ModelType.deepSeek,
  maxTokens: 2048,
);

// Create chat with thinking mode enabled
final chat = await model.createChat(
  temperature: 0.8,
  randomSeed: 1,
  topK: 1,
  isThinking: true, // Enable thinking mode
  modelType: ModelType.deepSeek, // Required for DeepSeek
);

// Handle thinking responses
chat.generateChatResponseAsync().listen((response) {
  if (response is ThinkingResponse) {
    // Show model's reasoning process
    print('Model thinking: ${response.content}');
    _showThinkingBubble(response.content);
    
  } else if (response is TextResponse) {
    // Final answer after thinking
    print('Final answer: ${response.token}');
    _updateResponse(response.token);
  }
});
```

**Thinking Mode Features:**
- ✅ See the model's reasoning process in real-time
- ✅ Interactive thinking bubbles in UI
- ✅ Works with function calling
- ✅ DeepSeek models only

### 8. 📱 Message Types

```dart
// Text only
final textMsg = Message.text(text: "Hello!", isUser: true);

// Text + Image
final multimodalMsg = Message.withImage(
  text: "Describe this image",
  imageBytes: imageBytes,
  isUser: true,
);

// Image only
final imageMsg = Message.imageOnly(imageBytes: imageBytes, isUser: true);

// Check if message has image
if (message.hasImage) {
  print('Message contains an image');
}
```

## 🎯 Supported Models

### Text-Only Models
| Model | Size | Backend | Function Calls | Thinking Mode | Download |
|-------|------|---------|----------------|---------------|----------|
| Gemma 2B | 2B | CPU/GPU | ❌ | ❌ | [HuggingFace](https://huggingface.co/google/gemma-2b-it) |
| Gemma 7B | 7B | CPU/GPU | ❌ | ❌ | [HuggingFace](https://huggingface.co/google/gemma-7b-it) |
| Gemma-2 2B | 2B | CPU/GPU | ❌ | ❌ | [HuggingFace](https://huggingface.co/google/gemma-2-2b-it) |
| Gemma-3 1B | 1B | CPU/GPU | ❌ | ❌ | [HuggingFace](https://huggingface.co/litert-community/Gemma3-1B-IT) |
| DeepSeek R1 | 1.5B | CPU/GPU | ✅ | ✅ | [HuggingFace](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B) |

### 🖼️ Multimodal Models (Vision + Text)
| Model | Size | Backend | Vision Support | Function Calls | Thinking Mode | Download |
|-------|------|---------|----------------|----------------|---------------|----------|
| Gemma 3n E2B | 1.5B | CPU/GPU | ✅ | ✅ | ❌ | [HuggingFace](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) |
| Gemma 3n E4B | 1.5B | CPU/GPU | ✅ | ✅ | ❌ | [HuggingFace](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview) |

## 🔧 MediaPipe Dependencies

This plugin uses **official MediaPipe libraries**:

**iOS:**
```ruby
# Automatically included in your Podfile
pod 'MediaPipeTasksGenAI', '0.10.24'
pod 'MediaPipeTasksGenAIC', '0.10.24'
```

**Android:**
```gradle
# Automatically included
implementation 'com.google.mediapipe:tasks-genai:0.10.24'
implementation 'com.google.mediapipe:tasks-vision:0.10.24' # For multimodal support
```

**Web:**
```javascript
// Automatically loaded from CDN
https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm
```

## 🌐 Platform Support

| Feature | Android | iOS | Web |
|---------|---------|-----|-----|
| Text Generation | ✅ | ✅ | ✅ |
| Function Calling | ✅ | ✅ | ✅ |
| Thinking Mode | ✅ | ✅ | ✅ |
| Image Input | ✅ | ⚠️ | ⚠️ |
| GPU Acceleration | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ |

- ✅ = Fully supported
- ⚠️ = Coming soon / Limited support

## 🚀 Why This Works

- ✅ **Official MediaPipe Support** - No custom frameworks
- ✅ **Version 0.10.24** - Includes Gemma 3 Nano + vision support
- ✅ **Function Calling** - External function integration (Gemma 3 Nano, DeepSeek)
- ✅ **Thinking Mode** - Transparent AI reasoning (DeepSeek models)
- ✅ **Automatic Integration** - Flutter handles CocoaPods/Gradle
- ✅ **Cross-Platform** - Same API for iOS/Android/Web
- ✅ **Multimodal Ready** - Text + Image input support
- ✅ **Simple API** - One parameter to enable images/functions/thinking

## 🖼️ Multimodal Examples

### Basic Image Analysis
```dart
final model = await gemma.createModel(
  modelType: ModelType.gemmaIt,
  supportImage: true,
);

final session = await model.createSession();
await session.addQueryChunk(Message.withImage(
  text: "What do you see in this image?",
  imageBytes: imageBytes,
  isUser: true,
));

// Note: session.getResponse() returns String directly
final response = await session.getResponse();
print(response);
await session.close();
```

### Chat with Images
```dart
final chat = await model.createChat(
  temperature: 0.8,
  supportImage: true,
);

// Add text message
await chat.addQueryChunk(Message.text(text: "Hello!", isUser: true));
final textResponse = await chat.generateChatResponse();
if (textResponse is TextResponse) {
  print(textResponse.token);
}

// Add image message
await chat.addQueryChunk(Message.withImage(
  text: "Can you analyze this image?",
  imageBytes: imageBytes,
  isUser: true,
));
final imageResponse = await chat.generateChatResponse();
if (imageResponse is TextResponse) {
  print(imageResponse.token);
}
```

## 📝 Example

Check the [example app](example/) for a complete implementation with Gemma 3 Nano models and multimodal support.

## 🛟 Troubleshooting

**iOS Setup Issues:**
```bash
# Clean and reinstall pods
cd ios && pod install --repo-update

# If memory issues occur, ensure entitlements are added
# Check ios/Runner/Runner.entitlements contains memory entitlements
```

**Memory Issues on iOS:**
- Ensure `Runner.entitlements` contains memory entitlements
- Use smaller models (1B-2B parameters) for devices with <6GB RAM
- Enable GPU backend for better performance: `PreferredBackend.gpu`

**Android Build Issues:**
```bash
flutter clean && flutter pub get
```

**Image Support Issues:**
- Ensure you're using a multimodal model (Gemma 3n E2B/E4B)
- Set `supportImage: true` when creating model and chat
- Images are automatically processed when included in `Message.withImage()`

**Web Platform:**
- Image support is in development for web platform
- Text-only models work fully on web

## 📄 License

MIT License - Use official MediaPipe libraries with confidence!

---

**BRO-GRRAMMER APPROVED** ✅ - Simple, clean, uses official MediaPipe with multimodal support!