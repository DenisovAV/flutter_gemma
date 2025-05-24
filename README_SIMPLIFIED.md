# Flutter Gemma with Gemma 3 Nano Support

**Run Gemma AI models locally on Flutter apps with official MediaPipe GenAI v0.10.24**

Supports: [Gemma 2B](https://huggingface.co/google/gemma-2b-it), [Gemma 7B](https://huggingface.co/google/gemma-7b-it), [Gemma-2 2B](https://huggingface.co/google/gemma-2-2b-it), [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT), **[Gemma 3 Nano 1.5B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview)** ✨

## ✅ What's New in v0.8.5

- 🚀 **Full Gemma 3 Nano Support** with MediaPipe GenAI v0.10.24
- ⚡ **Official CocoaPods** - No custom pods needed!
- 🎯 **GPU/CPU Backend Selection** works correctly
- 🛡️ **Fixed `input_pos != nullptr` errors**
- 📱 **iOS & Android Compatible**

## Quick Start

### 1. Installation

```yaml
dependencies:
  flutter_gemma: ^0.8.5
```

### 2. iOS Setup (Automatic)

The plugin automatically uses official MediaPipe CocoaPods:
- `MediaPipeTasksGenAI: 0.10.24`
- `MediaPipeTasksGenAIC: 0.10.24`

No manual pod configuration needed! 🎉

### 3. Android Setup (Automatic)

Uses official MediaPipe GenAI:
- `com.google.mediapipe:tasks-genai:0.10.24`

### 4. Basic Usage

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
  temperature: 0.8,
  topK: 40,
  topP: 0.9,
);

// Generate response
await chat.addQueryChunk(Message(text: "Hello!", isUser: true));
final response = await chat.generateChatResponse();
```

## 🎯 Gemma 3 Nano Models

All models work with official MediaPipe CocoaPods:

| Model | Size | Backend | Download |
|-------|------|---------|----------|
| Gemma 3n E2B | 1.5B | CPU/GPU | [HuggingFace](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) |
| Gemma 3n E4B | 1.5B | CPU/GPU | [HuggingFace](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview) |

## 🔧 MediaPipe Dependencies

This plugin uses **official MediaPipe CocoaPods**:

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
```

## 🚀 Why This Works

- ✅ **Official MediaPipe Support** - No custom frameworks
- ✅ **Version 0.10.24** - Includes Gemma 3 Nano support
- ✅ **Automatic Integration** - Flutter handles CocoaPods/Gradle
- ✅ **Cross-Platform** - Same API for iOS/Android

## 📝 Example

Check the [example app](example/) for a complete implementation with Gemma 3 Nano models.

## 🛟 Troubleshooting

**iOS Pod Issues:**
```bash
cd ios && pod install --repo-update
```

**Android Build Issues:**
```bash
flutter clean && flutter pub get
```

## 📄 License

MIT License - Use official MediaPipe CocoaPods with confidence!

---

**BRO-GRRAMMER APPROVED** ✅ - Simple, clean, uses official MediaPipe!