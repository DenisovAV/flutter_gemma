    # Flutter Gemma

**The plugin supports not only Gemma, but also other models. Here's the full list of supported models:** [Gemma 2B](https://huggingface.co/google/gemma-2b-it) & [Gemma 7B](https://huggingface.co/google/gemma-7b-it), [Gemma-2 2B](https://huggingface.co/google/gemma-2-2b-it), [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT), [Gemma 3 270M](https://huggingface.co/litert-community/gemma-3-270m-it), [Gemma 3 Nano 2B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview), [Gemma 3 Nano 4B](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview), [TinyLlama 1.1B](https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0), [Hammer 2.1 0.5B](https://huggingface.co/litert-community/Hammer2.1-0.5b), [Llama 3.2 1B](https://huggingface.co/litert-community/Llama-3.2-1B-Instruct), Phi-2, Phi-3 , [Phi-4](https://huggingface.co/litert-community/Phi-4-mini-instruct), [DeepSeek](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B), [Qwen2.5-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct), Falcon-RW-1B, StableLM-3B.

*Note: Currently, the flutter_gemma plugin supports Gemma-3, Gemma 3 270M, Gemma 3 Nano (with **multimodal vision support**), TinyLlama, Hammer 2.1, Llama 3.2, Phi-4, DeepSeek and Qwen2.5.

[Gemma](https://ai.google.dev/gemma) is a family of lightweight, state-of-the art open models built from the same research and technology used to create the Gemini models

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma3.png" alt="gemma_github_cover">
</p>

Bring the power of Google's lightweight Gemma language models directly to your Flutter applications. With Flutter Gemma, you can seamlessly incorporate advanced AI capabilities into your iOS and Android apps, all without relying on external servers.

There is an example of using:

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma.gif" alt="gemma_github_gif">
</p>

## Features

- **Local Execution:** Run Gemma models directly on user devices for enhanced privacy and offline functionality.
- **Platform Support:** Compatible with iOS, Android, and Web platforms.
- **🖼️ Multimodal Support:** Text + Image input with Gemma 3 Nano vision models (NEW!)
- **🛠️ Function Calling:** Enable your models to call external functions and integrate with other services (supported by select models)
- **🧠 Thinking Mode:** View the reasoning process of DeepSeek models with <think> blocks (NEW!)
- **🛑 Stop Generation:** Cancel text generation mid-process on Android devices (NEW!)
- **⚙️ Backend Switching:** Choose between CPU and GPU backends for each model individually in the example app (NEW!)
- **🔍 Advanced Model Filtering:** Filter models by features (Multimodal, Function Calls, Thinking) with expandable UI (NEW!)
- **📊 Model Sorting:** Sort models alphabetically, by size, or use default order in the example app (NEW!)
- **LoRA Support:** Efficient fine-tuning and integration of LoRA (Low-Rank Adaptation) weights for tailored AI behavior.
- **📥 Enhanced Downloads:** Smart retry logic and ETag handling for reliable model downloads from HuggingFace CDN
- **🔧 Download Reliability:** Automatic resume/restart logic for interrupted downloads with exponential backoff
- **🔧 Model Replace Policy:** Configurable model replacement system (keep/replace) with automatic model switching

## Model File Types

Flutter Gemma supports two types of model files:

- **`.task` files:** MediaPipe-optimized format with built-in chat templates
- **`.bin/.tflite` files:** Standard format requiring manual chat template formatting

The plugin automatically detects the file type and applies appropriate formatting.

## Model Capabilities

The example app offers a curated list of models, each suited for different tasks. Here's a breakdown of the models available and their capabilities:

| Model Family | Best For | Function Calling | Thinking Mode | Vision | Languages | Size |
|---|---|:---:|:---:|:---:|---|---|
| **Gemma 3 Nano** | On-device multimodal chat and image analysis. | ✅ | ❌ | ✅ | Multilingual | 3-6GB |
| **DeepSeek R1** | High-performance reasoning and code generation. | ✅ | ✅ | ❌ | Multilingual | 1.7GB |
| **Qwen 2.5** | Strong multilingual chat and instruction following. | ✅ | ❌ | ❌ | Multilingual | 1.6GB |
| **Hammer 2.1** | Lightweight action model for tool usage. | ✅ | ❌ | ❌ | Multilingual | 0.5GB |
| **Gemma 3 1B** | Balanced and efficient text generation. | ✅ | ❌ | ❌ | Multilingual | 0.5GB |
| **Gemma 3 270M**| Ideal for fine-tuning (LoRA) for specific tasks | ❌ | ❌ | ❌ | Multilingual | 0.3GB |
| **TinyLlama 1.1B**| Extremely compact, general-purpose chat. | ❌ | ❌ | ❌ | English-focused | 1.2GB |
| **Llama 3.2 1B** | Efficient instruction following | ❌ | ❌ | ❌ | Multilingual | 1.1GB |

## Installation

1.  Add `flutter_gemma` to your `pubspec.yaml`:

    ```yaml
    dependencies:
      flutter_gemma: latest_version
    ```

2.  Run `flutter pub get` to install.

## Setup

1. **Download Model and optionally LoRA Weights:** Obtain a pre-trained Gemma model (recommended: 2b or 2b-it) [from Kaggle](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/)
* For **multimodal support**, download [Gemma 3 Nano models](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) that support vision input
* Optionally, [fine-tune a model for your specific use case]( https://www.kaggle.com/code/juanmerinobermejo/llm-pr-fine-tuning-with-gemma-2b?scriptVersionId=169776634)
* If you have LoRA weights, you can use them to customize the model's behavior without retraining the entire model.
* [There is an article that described all approaches](https://medium.com/@denisov.shureg/fine-tuning-gemma-with-lora-for-on-device-inference-android-ios-web-with-separate-lora-weights-f05d1db30d86)
2. **Platform specific setup:**

**iOS**

* **Set minimum iOS version** in `Podfile`:
```ruby
platform :ios, '16.0'  # Required for MediaPipe GenAI
```

* **Enable file sharing** in `Info.plist`:
```plist
<key>UIFileSharingEnabled</key>
<true/>
```

* **Add network access description** in `Info.plist` (for development):
```plist
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access for model inference services.</string>
```

* **Enable performance optimization** in `Info.plist` (optional):
```plist
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

* **Add memory entitlements** in `Runner.entitlements` (for large models):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.kernel.extended-virtual-addressing</key>
	<true/>
	<key>com.apple.developer.kernel.increased-memory-limit</key>
	<true/>
	<key>com.apple.developer.kernel.increased-debugging-memory-limit</key>
	<true/>
</dict>
</plist>
```

* **Change the linking type** of pods to static in `Podfile`:
```ruby
use_frameworks! :linkage => :static
```

**Android**

* If you want to use a GPU to work with the model, you need to add OpenGL support in the manifest.xml. If you plan to use only the CPU, you can skip this step.

Add to 'AndroidManifest.xml' above tag `</application>`

```AndroidManifest.xml
 <uses-native-library
     android:name="libOpenCL.so"
     android:required="false"/>
 <uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
 <uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

**Web**

* Web currently works only GPU backend models, CPU backend models are not supported by MediaPipe yet
* **Multimodal support** (images) is in development for web platform

* Add dependencies to `index.html` file in web folder
```html
  <script type="module">
  import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai';
  window.FilesetResolver = FilesetResolver;
  window.LlmInference = LlmInference;
  </script>
```

## Usage

The new API splits functionality into two parts:

* **ModelFileManager**: Manages model and LoRA weights file handling.
* **InferenceModel**: Handles model initialization and response generation.

The updated API splits the functionality into two main parts:

* Import and access the plugin:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

final gemma = FlutterGemmaPlugin.instance;
```

* Managing Model Files with ModelFileManager

```dart
final modelManager = gemma.modelManager;
```

Place the model in the assets or upload it to a network drive, such as Firebase.
#### ATTENTION!! You do not need to load the model every time the application starts; it is stored in the system files and only needs to be done once. Please carefully review the example application. You should use loadAssetModel and loadNetworkModel methods only when you need to upload the model to device

## Usage
1.**Loading Models from assets (available only in debug mode):**

Don't forget to add your model to pubspec.yaml

1) Loading from assets (loraUrl is optional)
```dart
    await modelManager.installModelFromAsset('model.bin', loraPath: 'lora_weights.bin');
```

2) Loading from assets with Progress Status (loraUrl is optional)
```dart
    modelManager.installModelFromAssetWithProgress('model.bin', loraPath: 'lora_weights.bin').listen(
    (progress) {
      print('Loading progress: $progress%');
    },
    onDone: () {
      print('Model loading complete.');
    },
    onError: (error) {
      print('Error loading model: $error');
    },
  );
```

2.**Loading Models from network:**

* For web usage, you will also need to enable CORS (Cross-Origin Resource Sharing) for your network resource. To enable CORS in Firebase, you can follow the guide in the Firebase documentation: [Setting up CORS](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)

    1) Loading from the network (loraUrl is optional).
```dart
   await modelManager.downloadModelFromNetwork('https://example.com/model.bin', loraUrl: 'https://example.com/lora_weights.bin');
```

2) Loading from the network with Progress Status (loraUrl is optional)
```dart
    modelManager.downloadModelFromNetworkWithProgress('https://example.com/model.bin', loraUrl: 'https://example.com/lora_weights.bin').listen(
    (progress) {
      print('Loading progress: $progress%');
    },
    onDone: () {
      print('Model loading complete.');
    },
    onError: (error) {
      print('Error loading model: $error');
    },
);
```

3. **Loading LoRA Weights**

1) Loading LoRA weight from the network.
```dart
await modelManager.downloadLoraWeightsFromNetwork('https://example.com/lora_weights.bin');
```

2) Loading LoRA weight from assets.
```dart
await modelManager.installLoraWeightsFromAsset('lora_weights.bin');
```

4. **Model Management**
   You can set model and weights paths manually
```dart
await modelManager.setModelPath('model.bin');
await modelManager.setLoraWeightsPath('lora_weights.bin');
```

**Model Replace Policy** (NEW!)

Configure how the plugin handles switching between different models:

```dart
// Set policy to keep all models (default behavior)
await modelManager.setReplacePolicy(ModelReplacePolicy.keep);

// Set policy to replace old models (saves storage space)
await modelManager.setReplacePolicy(ModelReplacePolicy.replace);

// Check current policy
final currentPolicy = modelManager.replacePolicy;
```

**Automatic Model Management** (NEW!)

Use `ensureModelReady()` for seamless model switching that handles all scenarios automatically:

```dart
// Handles all cases:
// - Same model already loaded: does nothing
// - Different model with KEEP policy: loads new model, keeps old one
// - Different model with REPLACE policy: deletes old model, loads new one
// - Corrupted/invalid model: re-downloads automatically
await modelManager.ensureModelReady(
  'gemma-3n-E4B-it-int4.task',
  'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task'
);
```

You can delete the model and weights from the device. Deleting the model or LoRA weights will automatically close and clean up the inference. This ensures that there are no lingering resources or memory leaks when switching models or updating files.
```dart
await modelManager.deleteModel();
await modelManager.deleteLoraWeights();
```

5.**Initialize:**

Before performing any inference, you need to create a model instance. This ensures that your application is ready to handle requests efficiently.

**Text-Only Models:**
```dart
final inferenceModel = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt, // Required, model type to create
  preferredBackend: PreferredBackend.gpu, // Optional, backend type, default is PreferredBackend.gpu
  maxTokens: 512, // Optional, default is 1024
  loraRanks: [4, 8], // Optional, LoRA rank configuration for fine-tuned models
);
```

**🖼️ Multimodal Models (NEW!):**
```dart
final inferenceModel = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt, // Required, model type to create
  preferredBackend: PreferredBackend.gpu, // Optional, backend type
  maxTokens: 4096, // Recommended for multimodal models
  supportImage: true, // Enable image support
  maxNumImages: 1, // Optional, maximum number of images per message
  loraRanks: [4, 8], // Optional, LoRA rank configuration for fine-tuned models
);
```

6.**Using Sessions for Single Inferences:**

If you need to generate individual responses without maintaining a conversation history, use sessions. Sessions allow precise control over inference and must be properly closed to avoid memory leaks.

1) **Text-Only Session:**

```dart
final session = await inferenceModel.createSession(
  temperature: 1.0, // Optional, default: 0.8
  randomSeed: 1, // Optional, default: 1
  topK: 1, // Optional, default: 1
  // topP: 0.9, // Optional nucleus sampling parameter
  // loraPath: 'path/to/lora.bin', // Optional LoRA weights path
  // enableVisionModality: true, // Enable vision for multimodal models
);

await session.addQueryChunk(Message.text(text: 'Tell me something interesting', isUser: true));
String response = await session.getResponse();
print(response);

await session.close(); // Always close the session when done
```

2) **🖼️ Multimodal Session (NEW!):**

```dart
import 'dart:typed_data'; // For Uint8List

final session = await inferenceModel.createSession(
  enableVisionModality: true, // Enable image processing
);

// Text + Image message
final imageBytes = await loadImageBytes(); // Your image loading method
await session.addQueryChunk(Message.withImage(
  text: 'What do you see in this image?',
  imageBytes: imageBytes,
  isUser: true,
));

// Note: session.getResponse() returns String directly
String response = await session.getResponse();
print(response);

await session.close();
```

3) **Asynchronous Response Generation:**

```dart
final session = await inferenceModel.createSession();
await session.addQueryChunk(Message.text(text: 'Tell me something interesting', isUser: true));

// Note: session.getResponseAsync() returns Stream<String>
session.getResponseAsync().listen((String token) {
  print(token);
}, onDone: () {
  print('Stream closed');
}, onError: (error) {
  print('Error: $error');
});

await session.close(); // Always close the session when done
```

7.**Chat Scenario with Automatic Session Management**

For chat-based applications, you can create a chat instance. Unlike sessions, the chat instance manages the conversation context and refreshes sessions when necessary.

**Text-Only Chat:**
```dart
final chat = await inferenceModel.createChat(
  temperature: 0.8, // Controls response randomness, default: 0.8
  randomSeed: 1, // Ensures reproducibility, default: 1
  topK: 1, // Limits vocabulary scope, default: 1
  // topP: 0.9, // Optional nucleus sampling parameter
  // tokenBuffer: 256, // Token buffer size, default: 256
  // loraPath: 'path/to/lora.bin', // Optional LoRA weights path
  // supportImage: false, // Enable image support, default: false
  // tools: [], // List of available tools, default: []
  // supportsFunctionCalls: false, // Enable function calling, default: false
  // isThinking: false, // Enable thinking mode, default: false
  // modelType: ModelType.gemmaIt, // Model type, default: ModelType.gemmaIt
);
```

**🖼️ Multimodal Chat (NEW!):**
```dart
final chat = await inferenceModel.createChat(
  temperature: 0.8, // Controls response randomness
  randomSeed: 1, // Ensures reproducibility
  topK: 1, // Limits vocabulary scope
  supportImage: true, // Enable image support in chat
  // tokenBuffer: 256, // Token buffer size for context management
);
```

**🧠 Thinking Mode Chat (DeepSeek Models):**
```dart
final chat = await inferenceModel.createChat(
  temperature: 0.8,
  randomSeed: 1,
  topK: 1,
  isThinking: true, // Enable thinking mode for DeepSeek models
  modelType: ModelType.deepSeek, // Specify DeepSeek model type
  // supportsFunctionCalls: true, // Enable function calling for DeepSeek models
);
```

1) **Synchronous Chat:**

```dart
await chat.addQueryChunk(Message.text(text: 'User: Hello, who are you?', isUser: true));
ModelResponse response = await chat.generateChatResponse();
if (response is TextResponse) {
  print(response.token);
}

await chat.addQueryChunk(Message.text(text: 'User: Are you sure?', isUser: true));
ModelResponse response2 = await chat.generateChatResponse();
if (response2 is TextResponse) {
  print(response2.token);
}
```

2) **🖼️ Multimodal Chat Example:**

```dart
// Add text message
await chat.addQueryChunk(Message.text(text: 'Hello!', isUser: true));
ModelResponse response1 = await chat.generateChatResponse();
if (response1 is TextResponse) {
  print(response1.token);
}

// Add image message
final imageBytes = await loadImageBytes();
await chat.addQueryChunk(Message.withImage(
  text: 'Can you analyze this image?',
  imageBytes: imageBytes,
  isUser: true,
));
ModelResponse response2 = await chat.generateChatResponse();
if (response2 is TextResponse) {
  print(response2.token);
}

// Add image-only message
await chat.addQueryChunk(Message.imageOnly(imageBytes: imageBytes, isUser: true));
ModelResponse response3 = await chat.generateChatResponse();
if (response3 is TextResponse) {
  print(response3.token);
}
```

3) **Asynchronous Chat (Streaming):**

```dart
await chat.addQueryChunk(Message.text(text: 'User: Hello, who are you?', isUser: true));

chat.generateChatResponseAsync().listen((ModelResponse response) {
  if (response is TextResponse) {
    print(response.token);
  } else if (response is FunctionCallResponse) {
    print('Function call: ${response.name}');
  } else if (response is ThinkingResponse) {
    print('Thinking: ${response.content}');
  }
}, onDone: () {
  print('Chat stream closed');
}, onError: (error) {
  print('Chat error: $error');
});
```

8. **🛠️ Function Calling**

Enable your models to call external functions and integrate with other services. **Note: Function calling is only supported by specific models - see the [Model Support](#model-function-calling-support) section below.**

**Step 1: Define Tools**

Tools define the functions your model can call:

```dart
final List<Tool> _tools = [
  const Tool(
    name: 'change_background_color',
    description: "Changes the background color of the app. The color should be a standard web color name like 'red', 'blue', 'green', 'yellow', 'purple', or 'orange'.",
    parameters: {
      'type': 'object',
      'properties': {
        'color': {
          'type': 'string',
          'description': 'The color name',
        },
      },
      'required': ['color'],
    },
  ),
  const Tool(
    name: 'show_alert',
    description: 'Shows an alert dialog with a custom message and title.',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {
          'type': 'string',
          'description': 'The title of the alert dialog',
        },
        'message': {
          'type': 'string',
          'description': 'The message content of the alert dialog',
        },
      },
      'required': ['title', 'message'],
    },
  ),
];
```

**Step 2: Create Chat with Tools**

```dart
final chat = await inferenceModel.createChat(
  temperature: 0.8,
  randomSeed: 1,
  topK: 1,
  tools: _tools, // Pass your tools
  supportsFunctionCalls: true, // Enable function calling (required for tools)
  // tokenBuffer: 256, // Adjust if needed for function calling
);
```

**Step 3: Handle Different Response Types**

The model can now return two types of responses:

```dart
// Add user message
await chat.addQueryChunk(Message.text(text: 'Change the background to blue', isUser: true));

// Handle async responses
chat.generateChatResponseAsync().listen((response) {
  if (response is TextResponse) {
    // Regular text token from the model
    print('Text: ${response.token}');
    // Update your UI with the text
  } else if (response is FunctionCallResponse) {
    // Model wants to call a function
    print('Function Call: ${response.name}(${response.args})');
    _handleFunctionCall(response);
  }
});
```

**Step 4: Execute Function and Send Response Back**

```dart
Future<void> _handleFunctionCall(FunctionCallResponse functionCall) async {
  // Execute the requested function
  Map<String, dynamic> toolResponse;
  
  switch (functionCall.name) {
    case 'change_background_color':
      final color = functionCall.args['color'] as String?;
      // Your implementation here
      toolResponse = {'status': 'success', 'message': 'Color changed to $color'};
      break;
    case 'show_alert':
      final title = functionCall.args['title'] as String?;
      final message = functionCall.args['message'] as String?;
      // Show alert dialog
      toolResponse = {'status': 'success', 'message': 'Alert shown'};
      break;
    default:
      toolResponse = {'error': 'Unknown function: ${functionCall.name}'};
  }
  
  // Send the tool response back to the model
  final toolMessage = Message.toolResponse(
    toolName: functionCall.name,
    response: toolResponse,
  );
  await chat.addQueryChunk(toolMessage);
  
  // The model will then generate a final response explaining what it did
  final finalResponse = await chat.generateChatResponse();
  if (finalResponse is TextResponse) {
    print('Model: ${finalResponse.token}');
  }
}
```

**Function Calling Best Practices:**

- Use descriptive function names and clear descriptions
- Specify required vs optional parameters
- Always handle function execution errors gracefully
- Send meaningful responses back to the model
- The model will only call functions when explicitly requested by the user

9. **🧠 Thinking Mode (DeepSeek Models)**

DeepSeek models support "thinking mode" where you can see the model's reasoning process before it generates the final response. This provides transparency into how the model approaches problems.

**Enable Thinking Mode:**

```dart
final chat = await inferenceModel.createChat(
  temperature: 0.8,
  randomSeed: 1,
  topK: 1,
  isThinking: true, // Enable thinking mode
  modelType: ModelType.deepSeek, // Required for DeepSeek models
  supportsFunctionCalls: true, // DeepSeek also supports function calls
  tools: _tools, // Optional: add tools for function calling
  // tokenBuffer: 256, // Token buffer for context management
);
```

**Handle Thinking Responses:**

```dart
chat.generateChatResponseAsync().listen((response) {
  if (response is ThinkingResponse) {
    // Model's reasoning process
    print('Model is thinking: ${response.content}');
    // Show thinking bubble in UI
    _showThinkingBubble(response.content);
    
  } else if (response is TextResponse) {
    // Final response after thinking
    print('Final answer: ${response.token}');
    _updateFinalResponse(response.token);
    
  } else if (response is FunctionCallResponse) {
    // DeepSeek can also call functions while thinking
    print('Function call: ${response.name}');
    _handleFunctionCall(response);
  }
});
```

**Thinking Mode Features:**
- ✅ **Transparent Reasoning**: See how the model thinks through problems
- ✅ **Interactive UI**: Show/hide thinking bubbles with expandable content
- ✅ **Streaming Support**: Thinking content streams in real-time
- ✅ **Function Integration**: Models can think before calling functions
- ✅ **DeepSeek Optimized**: Designed specifically for DeepSeek model architecture

**Example Thinking Flow:**
1. User asks: "Change the background to blue and explain why blue is calming"
2. Model thinks: "I need to change the color first, then explain the psychology"
3. Model calls: `change_background_color(color: 'blue')`
4. Model explains: "Blue is calming because it's associated with sky and ocean..."

10. **Checking Token Usage**
You can check the token size of a prompt before inference. The accumulated context should not exceed maxTokens to ensure smooth operation.

```dart
int tokenCount = await session.sizeInTokens('Your prompt text here');
print('Prompt size in tokens: $tokenCount');
```

11. **Closing the Model**

When you no longer need to perform any further inferences, call the close method to release resources:

```dart
await inferenceModel.close();
```

If you need to use the inference again later, remember to call `createModel` again before generating responses.

## 🖼️ Message Types (NEW!)

The plugin now supports different types of messages:

```dart
// Text only
final textMessage = Message.text(text: "Hello!", isUser: true);

// Text + Image
final multimodalMessage = Message.withImage(
  text: "What's in this image?",
  imageBytes: imageBytes,
  isUser: true,
);

// Image only
final imageMessage = Message.imageOnly(imageBytes: imageBytes, isUser: true);

// Tool response (for function calling)
final toolMessage = Message.toolResponse(
  toolName: 'change_background_color',
  response: {'status': 'success', 'color': 'blue'},
);

// System information message
final systemMessage = Message.systemInfo(text: "Function completed successfully");

// Thinking content (for DeepSeek models)
final thinkingMessage = Message.thinking(text: "Let me analyze this problem...");

// Check if message contains image
if (message.hasImage) {
  print('This message contains an image');
}

// Create a copy of message
final copiedMessage = message.copyWith(text: "Updated text");
```

## 💬 Response Types (NEW!)

The model can return different types of responses depending on capabilities:

```dart
// Handle different response types
chat.generateChatResponseAsync().listen((response) {
  if (response is TextResponse) {
    // Regular text token from the model
    print('Text token: ${response.token}');
    // Use response.token to update your UI incrementally
    
  } else if (response is FunctionCallResponse) {
    // Model wants to call a function (Gemma 3 Nano, DeepSeek, Qwen2.5)
    print('Function: ${response.name}');
    print('Arguments: ${response.args}');
    
    // Execute the function and send response back
    _handleFunctionCall(response);
  } else if (response is ThinkingResponse) {
    // Model's reasoning process (DeepSeek models only)
    print('Thinking: ${response.content}');
    
    // Show thinking process in UI
    _showThinkingBubble(response.content);
  }
});
```

**Response Types:**
- **`TextResponse`**: Contains a text token (`response.token`) for regular model output
- **`FunctionCallResponse`**: Contains function name (`response.name`) and arguments (`response.args`) when the model wants to call a function
- **`ThinkingResponse`**: Contains the model's reasoning process (`response.content`) for DeepSeek models with thinking mode enabled


## 🎯 Supported Models

### Text-Only Models
- [Gemma 2B](https://huggingface.co/google/gemma-2b-it) & [Gemma 7B](https://huggingface.co/google/gemma-7b-it)
- [Gemma-2 2B](https://huggingface.co/google/gemma-2-2b-it)
- [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT)
- [Gemma 3 270M](https://huggingface.co/litert-community/gemma-3-270m-it) - Ultra-compact model
- [TinyLlama 1.1B](https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0) - Lightweight chat model
- [Hammer 2.1 0.5B](https://huggingface.co/litert-community/Hammer2.1-0.5b) - Action model with function calling
- [Llama 3.2 1B](https://huggingface.co/litert-community/Llama-3.2-1B-Instruct) - Instruction-tuned model
- [Phi-4](https://huggingface.co/litert-community/Phi-4-mini-instruct)
- [DeepSeek](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B)
- Phi-2, Phi-3, Falcon-RW-1B, StableLM-3B

### 🖼️ Multimodal Models (Vision + Text)
- [Gemma 3 Nano E2B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) - 1.5B parameters with vision support
- [Gemma 3 Nano E4B](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview) - 1.5B parameters with vision support

## 🛠️ Model Function Calling Support

Function calling is currently supported by the following models:

### ✅ Models with Function Calling Support
- **Gemma 3 Nano** models (E2B, E4B) - Full function calling support
- **Hammer 2.1 0.5B** - Action model with strong function calling capabilities  
- **DeepSeek** models - Function calling + thinking mode support
- **Qwen** models - Full function calling support

### ❌ Models WITHOUT Function Calling Support
- **Gemma 3 1B** models - Text generation only
- **Gemma 3 270M** - Text generation only
- **TinyLlama 1.1B** - Text generation only
- **Llama 3.2 1B** - Text generation only
- **Phi** models - Text generation only

**Important Notes:**
- When using unsupported models with tools, the plugin will log a warning and ignore the tools
- Models will work normally for text generation even if function calling is not supported
- Check the `supportsFunctionCalls` property in your model configuration

## 🌐 Platform Support

| Feature | Android | iOS | Web |
|---------|---------|-----|-----|
| Text Generation | ✅ | ✅ | ✅ |
| Image Input | ✅ | ✅ | ⚠️ |
| Function Calling | ✅ | ✅ | ✅ |
| GPU Acceleration | ✅ | ✅ | ✅ |
| Streaming Responses | ✅ | ✅ | ✅ |
| LoRA Support | ✅ | ✅ | ✅ |

- ✅ = Fully supported
- ⚠️ = In development

The full and complete example you can find in `example` folder

## **Important Considerations**

* **Model Size:** Larger models (such as 7b and 7b-it) might be too resource-intensive for on-device inference.
* **Function Calling Support:** Gemma 3 Nano and DeepSeek models support function calling. Other models will ignore tools and show a warning.
* **Thinking Mode:** Only DeepSeek models support thinking mode. Enable with `isThinking: true` and `modelType: ModelType.deepSeek`.
* **Multimodal Models:** Gemma 3 Nano models with vision support require more memory and are recommended for devices with 8GB+ RAM.
* **iOS Memory Requirements:** Large models require memory entitlements in `Runner.entitlements` and minimum iOS 16.0.
* **LoRA Weights:** They provide efficient customization without the need for full model retraining.
* **Development vs. Production:** For production apps, do not embed the model or LoRA weights within your assets. Instead, load them once and store them securely on the device or via a network drive.
* **Web Models:** Currently, Web support is available only for GPU backend models. Multimodal support is in development.
* **Image Formats:** The plugin automatically handles common image formats (JPEG, PNG, etc.) when using `Message.withImage()`.

## **🛟 Troubleshooting**

**Multimodal Issues:**
- Ensure you're using a multimodal model (Gemma 3 Nano E2B/E4B)
- Set `supportImage: true` when creating model and chat
- Check device memory - multimodal models require more RAM

**Performance:**
- Use GPU backend for better performance with multimodal models
- Consider using CPU backend for text-only models on lower-end devices

**Memory Issues:**
- **iOS**: Ensure `Runner.entitlements` contains memory entitlements (see iOS setup)
- **iOS**: Set minimum platform to iOS 16.0 in Podfile
- Reduce `maxTokens` if experiencing memory issues
- Use smaller models (1B-2B parameters) for devices with <6GB RAM
- Close sessions and models when not needed
- Monitor token usage with `sizeInTokens()`

**iOS Build Issues:**
- Ensure minimum iOS version is set to 16.0 in Podfile
- Use static linking: `use_frameworks! :linkage => :static`
- Clean and reinstall pods: `cd ios && pod install --repo-update`
- Check that all required entitlements are in `Runner.entitlements`

## Advanced Usage

### ModelThinkingFilter (Advanced)

For advanced users who need to manually process model responses, the `ModelThinkingFilter` class provides utilities for cleaning model outputs:

```dart
import 'package:flutter_gemma/core/extensions.dart';

// Clean response based on model type
String cleanedResponse = ModelThinkingFilter.cleanResponse(
  rawResponse, 
  ModelType.deepSeek
);

// The filter automatically removes model-specific tokens like:
// - <end_of_turn> tags (Gemma models)
// - Special DeepSeek tokens
// - Extra whitespace and formatting
```

This is automatically handled by the chat API, but can be useful for custom inference implementations.

## **🚀 What's New**

✅ **🛠️ Advanced Function Calling** - Enable your models to call external functions and integrate with other services (Gemma 3 Nano, Hammer 2.1, DeepSeek, and Qwen2.5 models)  
✅ **🧠 Thinking Mode** - View the reasoning process of DeepSeek models with interactive thinking bubbles  
✅ **💬 Enhanced Response Types** - New `TextResponse`, `FunctionCallResponse`, and `ThinkingResponse` types for better handling  
✅ **🖼️ Multimodal Support** - Text + Image input with Gemma 3 Nano models  
✅ **📨 Enhanced Message API** - Support for different message types including tool responses  
✅ **⚙️ Backend Switching** - Choose between CPU and GPU backends individually for each model in the example app  
✅ **🔍 Advanced Model Filtering** - Filter models by features (Multimodal, Function Calls, Thinking) with expandable UI  
✅ **📊 Model Sorting** - Sort models alphabetically, by size, or use default order  
✅ **🚀 New Models** - Added Gemma 3 270M, TinyLlama 1.1B, Hammer 2.1 0.5B, and Llama 3.2 1B support  
✅ **🌐 Cross-Platform** - Works on Android, iOS, and Web (text-only)  
✅ **💾 Memory Optimization** - Better resource management for multimodal models

**Coming Soon:**
- Full Multimodal Web Support
- Text Embedder & On-Device RAG Pipelines
- Desktop Support (macOS, Windows, Linux)
- Audio & Video Input
- Audio Output (Text-to-Speech)