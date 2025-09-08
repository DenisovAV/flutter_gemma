The Dawn of Offline AI Agents in Your Pocket
Complete Guide to flutter_gemma Plugin
Prologue
In my previous article "Fine-Tuning Gemma with LoRA for On-Device Inference (Android, iOS, Web) with Separate LoRA Weights", I walked you through fine-tuning Gemma models with LoRA for on-device inference. We covered the theoretical foundations and got our models ready for mobile deployment. Now, it's time for the exciting part - actually building Flutter applications that leverage these powerful AI capabilities.
After months of developing and refining the flutter_gemma plugin, I've learned what works (and what doesn't) when it comes to on-device AI in mobile apps. Today, I'm sharing everything I've discovered about creating production-ready AI features that users actually want to use.
We're entering a new era of mobile development. With flutter_gemma, you're no longer building apps that merely connect to AI services - you're creating fully autonomous, multimodal AI agents that live entirely on your users' devices.
Think about what this means. Your app can now:
See and understand the world through the camera, analyzing images and documents without sending a single byte to the cloud
Reason and think through complex problems, showing its thought process transparently to users
Take actions by calling functions and integrating with device capabilities, becoming a true digital assistant
Work everywhere - on airplanes, in remote areas, or simply for users who value their privacy

This isn't just about adding AI features to apps. It's about fundamentally reimagining what mobile applications can be. An educational app becomes a personal tutor that understands handwritten homework. An accessibility app becomes an AI companion that sees the world alongside users with visual impairments. A productivity app becomes an intelligent agent that not only understands requests but can execute them.

## What You'll Learn

By the end of this article, you'll know how to:
- What flutter_gemma is and how to set up it in your existing Flutter projects
- Choose the right model for your specific use case
- Build multimodal apps that understand both text and images
- Create AI assistants that can call external functions
- Implement "thinking mode" to show AI reasoning process
- Handle the unique challenges of mobile AI (memory, performance, UX)
- Deploy AI-powered apps to production

Let's dive in.

---

## Getting Started: Your First AI-Powered Flutter App

My journey began with a simple goal: to run modern AI models directly inside a Flutter app, completely offline. I explored various options. There are powerful tools like `llama.cpp`, which my colleague Georgy brilliantly demonstrated for Android in his [article on running Gemma with it](https://medium.com/@farmaker47/run-gemma-and-vlms-on-mobile-with-llama-cpp-dbb6e1b19a93). However, for my specific needs with Flutter, I found that many existing solutions, including `llama.cpp` wrappers, often lacked the stability and seamless integration required for a production-ready, cross-platform application.

The breakthrough came when I discovered Google's MediaPipe. It was powerful and optimized for on-device tasks, but there was one major problem: it had no official support for Flutter. Seeing this gap, I decided to bridge it myself. That's how `flutter_gemma` was born.

`flutter_gemma` is a Flutter plugin that brings the power of Google's Gemma family and other Small Language Models (SLMs) to your apps via MediaPipe, allowing you to run them locally on iOS, Android, and Web. Since its creation, it has been adopted by many developers looking for a stable and efficient way to build on-device AI features.

The first time you get it running feels like magic, but it requires careful attention to detail.

The full, up-to-date installation instructions are always in the project's [README.md](https://github.com/DenisovAV/flutter_gemma/blob/main/README.md). **It is crucial to follow the platform-specific steps for iOS, Android, and Web precisely.** A small mistake in the `Podfile` for iOS or a missing entitlement can prevent the app from running.

If you run into any trouble, the repository includes a complete [example application](https://github.com/DenisovAV/flutter_gemma/tree/main/example) that is guaranteed to work. You can always use it as a reference to compare your own setup.

### The Model Distribution Challenge

Before we dive into code, let's address the elephant in the room: how do you actually get a 1-6GB AI model onto your users' devices?

When I first started with flutter_gemma, I thought this would be straightforward. I was wrong. The first question everyone asks after seeing the demos is: "This is cool, but how do I deliver the model to production users?"

**The Manual Approach (Don't Do This)**

Technically, you can manually place models on devices for testing:

- **Android**: Use ADB to push model files: `adb push model.task /sdcard/Android/data/your.app.id/files/`
- **iOS**: Use Xcode's device window or iTunes file sharing to copy models to the app's documents directory
- **Web**: Host the model file and provide a direct download link

But asking users to manually download and install AI models before using your app? That's not exactly what I'd call a production-ready user experience. Imagine telling someone: "Hey, download our chat app! Oh, and also please manually download this 3GB file and put it in the right folder on your phone." 

Yeah, that's not happening.

**Enter ModelManager: The Solution**

Fortunately, the flutter_gemma plugin includes a powerful `ModelManager` class that abstracts away all the complexity of model distribution. It handles platform-specific file operations, progress tracking, and error recovery automatically.

The `ModelManager` gives you three main approaches to get models onto devices:
1. **Asset bundling** - for small models and development
2. **Network download** - for production apps (recommended)
3. **Custom paths** - for advanced integration scenarios

Let me walk you through each approach and when to use them:

**The Asset Bundle Approach (Limited Use Only)**

Flutter lets you bundle assets with your app, and initially, I thought this was the solution:

```dart
// Don't do this for large models
await modelManager.installModelFromAsset('assets/models/gemma_1b.task');
```

This works great for not very big models, but there are two major problems:

1. **Platform Limitations**: Both iOS and Android have strict limits on asset bundle sizes. iOS apps larger than 4GB [won't process properly during App Store submission](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size), and Android has its own constraints: [App Bundles can be up to 4GB total](https://support.google.com/googleplay/android-developer/answer/9859372), but the compressed download size for any single device configuration is limited to 200MB, with legacy APKs capped at just 100MB.

2. **App Store Rejection**: An app with size more than 4GB [exceeds Apple's 4GB maximum app size limit](https://developer.apple.com/help/app-store-connect/reference/maximum-build-file-sizes/) and will be automatically rejected during submission. Users won't download it either - mobile users expect apps to be small and download quickly.

There is a "proper" way!

**The Production Approach: Smart Model Loading**

The solution I've refined over dozens of apps is what I call "progressive model loading." Here's how it works:

```dart
class ProductionModelManager {
  static const String MODEL_URL = 'https://your-cdn.com/models/qwen25_1_5b.task';
  static const String MODEL_FILENAME = 'qwen25_1_5b.task';
  
  Future<void> ensureModelReady() async {
    final modelManager = FlutterGemmaPlugin.instance.modelManager;
    
    // Check if model is already downloaded
    if (await modelManager.isModelInstalled) {
      return; // We're good to go
    }
    
    // Show download UI to user
    await _downloadModelWithProgress();
  }
  
  Future<void> _downloadModelWithProgress() async {
    final modelManager = FlutterGemmaPlugin.instance.modelManager;
    
    // This is where the magic happens - with real-time progress updates
    await modelManager.downloadModelFromNetwork(
      MODEL_URL,
      onProgress: (progress) {
        // progress is a double from 0.0 to 1.0
        final percentage = (progress * 100).toStringAsFixed(1);
        print('Download progress: $percentage%');
        
        // Update UI with download progress
        setState(() {
          _downloadProgress = progress;
          _downloadStatus = 'Downloading AI model... $percentage%';
        });
      },
    );
  }
  
  // UI method to show download progress
  void _updateDownloadProgress(double progress) {
    setState(() {
      _downloadProgress = progress;
      if (progress >= 1.0) {
        _downloadStatus = 'AI model ready!';
      } else {
        final percentage = (progress * 100).toStringAsFixed(1);
        _downloadStatus = 'Downloading AI model... $percentage%';
      }
    });
  }
}
```


**Why Network Download is the Production Standard**

 Here are the key benefits of this approach:

1. **Small App Size**: Your app downloads in seconds, not minutes
2. **Model Updates**: You can update AI models without app store releases
3. **Dynamic Personalization with LoRA**: Instantly apply different fine-tuned behaviors to the base model by downloading small LoRA adapter files (a few megabytes) on the fly.
4. **Device-Specific Optimization**: Serve different model variants based on device capabilities
5. **Cost Control**: Users only download what they need, when they need it
6. **A/B Testing**: Test different models with different user segments

To ensure downloads are fast and reliable, the plugin utilizes the [`background_downloader`](https://pub.dev/packages/background_downloader) package for optimized performance.

**The First-Run Experience**

Here's the user flow I've found works best:

1. User downloads your app (small, fast download)
2. App opens to an onboarding screen explaining AI features
3. User taps "Enable AI Features" 
4. App downloads model with progress indicator
5. User can start using AI features immediately after download

This approach gets users engaged quickly while the model downloads in the background.

**[Screenshot Placeholder: Model download progress screen showing AI brain icon, progress bar at 67%, and encouraging status messages]**

The key UX insights I've learned:
- **Always show progress** - users need to know something is happening
- **Show file size context** - "3.2MB of 1.2GB" helps users understand the wait
- **Handle errors gracefully** - offer retry options, not just error messages

Okay, we've figured out how to deliver models to devices. Let's move on to inference.

### Understanding Inference Types: Chat vs. Single Responses

The `flutter_gemma` plugin offers two distinct modes for interacting with the AI, each optimized for a different purpose. Choosing the right one is key to building an efficient and effective app: **Single Inference** is for one-off, stateless requests, while the **Chat Interface** is for stateful, ongoing conversations.

#### Single Inference: For Stateless, One-Shot Tasks

Think of Single Inference as asking a question to a fresh instance of the model every single time. The model has no memory of past interactions. This mode is perfect for transactional tasks where context isn't needed from one request to the next.

**Use it for:**
- **Text Summarization:** Giving the model a long article and asking for a concise summary.
- **Data Extraction:** Analyzing a block of text to pull out specific information like names, dates, or sentiment.
- **Simple Q&A:** Answering a single, self-contained question like "What is the capital of France?"
- **Image Analysis:** Describing the contents of a single image when using a vision-capable model.

    Here’s how you could use it to summarize a piece of text:

```dart
// 1. Create a model instance
final model = await gemma.createModel(modelType: ModelType.general);

// 2. Create a stateless session
final session = await model.createSession();

// 3. Generate a single, streaming response
final article = "Your long article text goes here...";
final prompt = "Summarize the following article in three sentences: $article";
String summary = '';
await for (final token in session.generateResponseAsync(prompt)) {
  summary += token;
  // Update your UI with the streaming summary in real-time
}

print(summary);

// 4. Clean up the session
await session.close();
```

#### Chat Interface: For Stateful, Conversational AI

The Chat Interface is designed for building conversational experiences. It automatically manages the conversation history, so each new message is understood within the context of everything that has been said before. This is the mode you'll use to build chatbots, assistants, and any feature that requires a back-and-forth dialogue.

**Use it for:**
- **Customer Support Chatbots:** Assisting users with problems over multiple turns.
- **AI Tutors:** Engaging in a continuous, evolving dialogue to help a user learn.
- **Multi-step Task Execution:** Guiding a user through a process where the AI needs to remember previous answers.

Here’s a simple example of a multi-turn conversation:

```dart
// 1. Create a model and a stateful chat instance
final model = await gemma.createModel(modelType: ModelType.general);
final chat = await model.createChat();

// 2. Send the first user message
await chat.addQuery(Message.text(text: "I'm planning a trip to Japan. What's a good city for a first-time visitor?", isUser: true));

// 3. Stream the AI's response
String aiResponse1 = '';
await for (final response in chat.generateChatResponseAsync()) {
  if (response is TextResponse) {
    aiResponse1 += response.token;
  }
}
print("AI: $aiResponse1"); // e.g., "Tokyo is a great choice..."

// 4. Ask a follow-up question. The AI remembers the context (Japan, Tokyo).
await chat.addQuery(Message.text(text: "What's the best way to get around there?", isUser: true));

// 5. Stream the second response
String aiResponse2 = '';
await for (final response in chat.generateChatResponseAsync()) {
  if (response is TextResponse) {
    aiResponse2 += response.token;
  }
}
print("AI: $aiResponse2"); // e.g., "The subway system in Tokyo is fantastic..."
```

The key difference is simple: **Single Inference** is for memoryless, transactional requests, while the **Chat Interface** is for building context and relationships over time.

### Your First AI Chat

Now that we've covered the core concepts, the best way to see them in action is to look at a complete, working example. Instead of a minimal code snippet here, I encourage you to explore the example app included in the repository.

It features a fully implemented, simple chat screen that demonstrates how to manage model state, handle user input, and display streaming responses from an offline AI bot. It's the perfect starting point and a reliable reference.

You can find the full implementation in the [example application folder](https://github.com/DenisovAV/flutter_gemma/tree/main/example).

The key insight I learned: always show loading states. Model initialization can take 10-30 seconds on mobile devices, and users need to know something is happening.

---

Now that you know how to implement the chat, it's time for a crucial decision: choosing the right AI partner for your app.

## Understanding Model Capabilities: Choosing Your AI Partner

Not all models are created equal. The example app offers a curated list of models, each suited for different tasks. Here’s a breakdown of the models available and their capabilities to help you choose a starting point:

| Model Family | Best For | Function Calling | Thinking Mode | Vision | Size |
|---|---|:---:|:---:|:---:|---|
| **Gemma 3 Nano** | On-device multimodal chat and image analysis. | ✅ | ❌ | ✅ | 3-6GB |
| **DeepSeek R1** | High-performance reasoning and code generation. | ✅ | ✅ | ❌ | 1.7GB |
| **Qwen 2.5** | Strong multilingual chat and instruction following. | ✅ | ❌ | ❌ | 1.6GB |
| **Hammer 2.1** | Lightweight action model for tool usage. | ✅ | ❌ | ❌ | 0.5GB |
| **Gemma 3 1B** | Balanced and efficient text generation. | ✅ | ❌ | ❌ | 0.5GB |
| **TinyLlama 1.1B**| Extremely compact, general-purpose chat. | ❌ | ❌ | ❌ | 1.2GB |
| **Llama 3.2 1B** | Efficient, multilingual instruction following. | ❌ | ❌ | ❌ | 1.1GB |

**[Screenshot Placeholder: Model selection interface showing performance benchmarks, memory usage, and feature comparison]**

### Real-World Model Selection Example

When we built LiveCaptionsXR (an AI accessibility platform for real-time captioning), I needed fast inference, vision capabilities to process screen content, and a reasonable memory footprint. I chose **Gemma 3 Nano** because it was the only model that met all the criteria, especially vision support.

Instead of a single "best" model, the key is to choose based on your primary use case. Here’s a quick guide:

- **For pure function calling:** If your app's main goal is to translate user commands into actions (like a smart assistant), **Hammer 2.1** is purpose-built for this. It excels at tool usage with minimal overhead.
- **For general chat with function calls:** If you need a good conversationalist that can also reliably use tools, **Qwen 2.5** is an excellent choice.
- **For simple, lightweight chat:** When you just need a solid conversational AI without advanced features, **Gemma 3 1B** is my go-to. At just 500MB, it's incredibly fast to download and initialize.
- **To see the AI's reasoning:** If you want to expose the model's thought process, **DeepSeek** is the only option that supports the 'Thinking Mode'.
- **For highly specific, fine-tuned tasks:** When you have a very narrow task and want maximum efficiency, the ultra-compact **Gemma 3 270M** is the perfect candidate for fine-tuning with LoRA. You can create a highly specialized expert model with a tiny footprint.

I will break down the implementation for some of these specific examples later on. But before we get to that, we need to cover a few core concepts of the `flutter_gemma` API that you'll use in every implementation.

---

## Core Concepts: Messages, Responses, and Streaming

The `flutter_gemma` API is built around a few core concepts that are essential to understand before building your UI. Moving beyond simple text strings to structured data is the key to unlocking the plugin's most powerful features.

### Message Types: More Than Just Text

First, every piece of information you send *to* the model is wrapped in a `Message` object. This is the fundamental building block of the conversation history. Instead of just sending a raw string, you create a `Message` that describes the nature of the input. This object-oriented approach is what enables advanced features like multimodal input and function calling.

The code below shows the different kinds of messages you can construct:

```dart
// Text-only message - the most common type
final textMsg = Message.text(text: "Hello AI!", isUser: true);

// Image + text (multimodal) - for vision-capable models
final imageMsg = Message.withImage(
  text: "What's in this image?",
  imageBytes: await getImageBytes(),
  isUser: true,
);

// Tool response - to feed the result of a function call back to the model
final toolMsg = Message.toolResponse(
  toolName: 'get_weather',
  response: {'temperature': 72, 'condition': 'sunny'},
);

// System information - for displaying info in the UI that isn't sent to the model
final systemMsg = Message.systemInfo(text: "Function completed");

// Thinking content - for displaying the model's reasoning process (DeepSeek only)
final thinkingMsg = Message.thinking(text: "Let me analyze this...");
```

### Response Types: Understanding AI Output

Just as your input is structured, the model's output is too. The model doesn't just return a final block of text. Instead, it returns a stream of `ModelResponse` objects, where each object represents a different kind of output. The model might be generating plain text, or it might decide it needs to call one of your functions. Your application's logic must be prepared to handle these different "intents" from the model.

This is typically handled in a `listen` block on the response stream, where you check the type of each incoming response object and act accordingly:

```dart
chat.generateChatResponseAsync().listen((response) {
  if (response is TextResponse) {
    // This is a regular text token. Append it to your chat bubble.
    _updateChatBubble(response.token);
    
  } else if (response is FunctionCallResponse) {
    // The AI wants to call a function. Execute it now.
    await _handleFunctionCall(response);
    
  } else if (response is ThinkingResponse) {
    // The AI is "thinking" (DeepSeek only). Show this in the UI.
    _updateThinkingBubble(response.content);
  }
});
```

### Streaming vs. Batch: The User Experience Difference

This is one of the most important concepts for building a good AI application. You should **always stream the model's response** rather than waiting for the full text to be generated (batching).

The reason is purely about user experience. Waiting for a full response, which can take several seconds, makes an app feel slow, broken, or "frozen." In contrast, streaming the response token-by-token makes the app feel incredibly fast and interactive, as the user sees the AI "typing" in real-time. Even if the total generation time is identical, the *perceived performance* of the streaming version is dramatically better.

Here’s the standard implementation, where you accumulate the streaming tokens and update the UI on each new event:

```dart
String _accumulatedText = '';

void _processStreamingResponse() async {
  await for (final response in chat!.generateChatResponseAsync()) {
    if (response is TextResponse) {
      setState(() {
        _accumulatedText += response.token;
        // Update the last message in your message list with the new accumulated text
        _messages.last = Message.text(text: _accumulatedText);
      });
    }
  }
}
```

Now that we've covered the fundamental concepts, let's move on to detailed examples of how to work with more than just text.

---

## Advanced Feature #1: Multimodal AI (When Your App Can See)

The moment I got image understanding working in my Flutter app, I knew mobile AI had crossed a threshold. Here's how to build apps that can actually see and understand images.

### Setting Up Vision-Capable Models

- FIX Only Gemma 3 Nano models support vision. The setup is slightly different:

```dart
final model = await _gemma.createModel(
  modelType: ModelType.gemmaIt,
  supportImage: true,        // Enable vision
  maxNumImages: 1,          // How many images per message
  maxTokens: 4096,          // Vision models need more tokens
);

final chat = await model.createChat(
  supportImage: true,
  tokenBuffer: 512,         // Larger buffer for image processing
);
```

### Building an Image Analysis Feature

Here's the complete implementation I use for analyzing images:

```dart
class ImageAnalyzer extends StatefulWidget {
  @override
  _ImageAnalyzerState createState() => _ImageAnalyzerState();
}

class _ImageAnalyzerState extends State<ImageAnalyzer> {
  Uint8List? _selectedImage;
  String _analysis = '';
  bool _analyzing = false;

  Future<void> _pickAndAnalyzeImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImage = bytes;
        _analyzing = true;
      });
      
      await _analyzeImage(bytes);
    }
  }

  Future<void> _analyzeImage(Uint8List imageBytes) async {
    final message = Message.withImage(
      text: "Analyze this image in detail. What do you see?",
      imageBytes: imageBytes,
      isUser: true,
    );
    
    await chat!.addQuery(message);
    
    String analysis = '';
    await for (final response in chat!.generateChatResponseAsync()) {
      if (response is TextResponse) {
        setState(() {
          analysis += response.token;
          _analysis = analysis;
        });
      }
    }
    
    setState(() => _analyzing = false);
  }
  
  // ... UI implementation
}
```

**[Screenshot Placeholder: Image analysis interface showing selected image, loading state, and streaming analysis results]**

---

## Advanced Feature #2: Function Calling (When AI Meets the Real World)

Function calling is where on-device AI gets really powerful. Instead of just generating text, your AI can actually do things — call APIs, update databases, control device features.

### Understanding Tools and Functions

Think of tools as APIs that you expose to the AI. The AI decides when to call them based on user requests:

```dart
final List<Tool> appTools = [
  Tool(
    name: 'get_weather',
    description: 'Get current weather for a location',
    parameters: {
      'type': 'object',
      'properties': {
        'location': {
          'type': 'string',
          'description': 'City name or address'
        }
      },
      'required': ['location']
    }
  ),
  
  Tool(
    name: 'set_reminder',
    description: 'Create a reminder for the user',
    parameters: {
      'type': 'object', 
      'properties': {
        'title': {'type': 'string'},
        'datetime': {'type': 'string', 'format': 'datetime'},
        'priority': {'type': 'string', 'enum': ['low', 'medium', 'high']}
      },
      'required': ['title', 'datetime']
    }
  )
];
```

### Implementing Function Execution

When the AI wants to call a function, you need to execute it and return results:

```dart
Future<Map<String, dynamic>> _executeTool(FunctionCallResponse functionCall) async {
  switch (functionCall.name) {
    case 'get_weather':
      final location = functionCall.args['location'] as String;
      return await _getWeatherData(location);
      
    case 'set_reminder':
      final title = functionCall.args['title'] as String;
      final datetime = DateTime.parse(functionCall.args['datetime']);
      await _createReminder(title, datetime);
      return {'status': 'success', 'reminder_id': '12345'};
      
    default:
      return {'error': 'Unknown function: ${functionCall.name}'};
  }
}

Future<Map<String, dynamic>> _getWeatherData(String location) async {
  // Call actual weather API
  final response = await http.get(
    Uri.parse('https://api.weather.com/v1/current?location=$location')
  );
  
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return {
      'temperature': data['temperature'],
      'condition': data['condition'],
      'humidity': data['humidity']
    };
  } else {
    return {'error': 'Failed to get weather data'};
  }
}
```

**[Screenshot Placeholder: Function calling flow showing user request, AI decision to call function, execution, and response integration]**

---

## Advanced Feature #3: Thinking Mode (Seeing AI Reason)

The "thinking mode" available in some models is fascinating — you can literally watch the AI work through problems step by step. It's like having a transparent AI that shows its work.

### Understanding Thinking Mode

When thinking mode is enabled, the AI's reasoning process is captured separately from its final response:

```dart
final chat = await model.createChat(
  isThinking: true,
  modelType: ModelType.deepSeek,
  temperature: 0.7,
);

chat.generateChatResponseAsync().listen((response) {
  if (response is ThinkingResponse) {
    // AI is thinking - show reasoning process
    _showThinkingBubble(response.content);
    
  } else if (response is TextResponse) {
    // Final answer - show normal response
    _showChatMessage(response.token);
  }
});
```

### Building Thinking UI Components

I created expandable "thinking bubbles" that let users peek into the AI's reasoning:

```dart
class ThinkingBubble extends StatefulWidget {
  final String thinkingContent;
  final bool isComplete;
  
  @override
  _ThinkingBubbleState createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.psychology, color: Colors.blue),
            title: Text(
              'AI is thinking...',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
            ),
            trailing: widget.isComplete 
              ? IconButton(
                  icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                )
              : SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
          ),
          
          if (_isExpanded && widget.thinkingContent.isNotEmpty)
            Container(
              padding: EdgeInsets.all(16),
              child: Text(
                widget.thinkingContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

**[Screenshot Placeholder: Thinking bubble interface showing collapsed state, expanded reasoning, and streaming thought process]**

### When to Use Thinking Mode

Thinking mode is perfect for:
- **Educational apps** - Students can see how the AI solves problems
- **Debugging tools** - Developers can understand AI's problem-solving approach  
- **Complex reasoning tasks** - Users can verify AI's logic before trusting results

But it adds latency and uses more tokens, so use it thoughtfully.

---



## Real-World Use Cases

Here are a few of examples of how `flutter_gemma` can be used to build powerful, real-world features.

### 1. LiveCaptionsXR: AI Accessibility Platform

A powerful real-world example is [LiveCaptionsXR](https://livecaptionsxr.com/), an AI-powered accessibility platform. The project was born from an idea by [Craig Merry](https://www.linkedin.com/in/craigmerry/), a deaf developer from California, and we collaborated to build it for the [Gemma 3n Challenge](https://www.kaggle.com/competitions/google-gemma-3n-hackathon). Our goal was to solve a key problem for individuals with hearing loss by not just transcribing what is said, but also showing *who* is speaking and from where by rendering captions in 3D space. The project is in active development, with the initial MVP now published.

The application runs completely on-device for privacy and offline capability, using a multimodal Gemma model to process both audio and visual data. It also uses `flutter_gemma`'s function-calling ability to allow users to control accessibility features, like caption size, with natural language voice commands. You can see a full demonstration on [YouTube](https://www.youtube.com/watch?v=Oz8nzt2cc3Q).

```dart
// Simplified example of the voice command logic in LiveCaptionsXR
class _LiveCaptionsAppState extends State<LiveCaptionsApp> {
  final _accessibilityTools = [
    Tool(
      name: 'adjust_caption_settings',
      description: 'Modify caption appearance and behavior',
      // ... parameters
    ),
  ];
  
  Future<void> _processVoiceCommand(String command) async {
    final message = Message.text(
      text: "User said: '$command'. If this is a request to adjust accessibility settings, call the appropriate function.",
      isUser: true,
    );
    await _aiAssistant!.addQuery(message);
    await for (final response in _aiAssistant!.generateChatResponseAsync()) {
      if (response is FunctionCallResponse) {
        await _executeAccessibilityFunction(response);
      }
    }
  }
  // ...
}
```

### 2. Offline Menu Translator

A common challenge when traveling is reading menus in a foreign language with no internet connection. As demonstrated in an excellent [article by Csongor Benedek Vogel](https://medium.com/@vogelcsongorbenedek/using-gemma-for-flutter-apps-91f746e3347c), you can use a multimodal model to solve this.

With `flutter_gemma`, you can build an app that uses a vision-capable model to act as a personal translator. The user simply points their camera at the menu. The model processes the image, identifies the foreign text (e.g., Japanese), and translates it into the user's language. The key is that this all happens instantly and entirely on the device, ensuring it works anywhere and that the images never leave the user's phone.

The core logic involves sending the image to the model with a prompt that specifically asks for translation, as shown in the simplified example below.

```dart
class MenuTranslator {
  InferenceChat? _translatorAI;

  Future<void> initialize() async {
    final model = await FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.gemmaIt, // Vision model is required
      supportImage: true,
    );
    _translatorAI = await model.createChat(supportImage: true);
  }

  Future<String> translateMenu(Uint8List menuImageBytes) async {
    final prompt = Message.withImage(
      text: "Translate the Japanese text from this menu image into English.",
      imageBytes: menuImageBytes,
      isUser: true,
    );

    String translation = '';
    await for (final response in _translatorAI!.generateChatResponseAsync(prompt)) {
      if (response is TextResponse) {
        translation += response.token;
      }
    }
    return translation;
  }
}
```

### 3. MenuMind: Your Smart Nutrition Guide

Also born from the [Gemma 3n Challenge](https://www.kaggle.com/competitions/google-gemma-3n-hackathon) is [MenuMind](https://github.com/MohamedAbd0/menu_mind), a project by developer [Mohamed Abdo](https://www.linkedin.com/in/mohamed-abdo95/). This app takes the menu analysis concept a step further. Instead of just translating, it acts as a smart nutrition and allergen guide.

A user can take a picture of a menu, and the multimodal AI will not only translate the items but also identify potential allergens or provide nutritional information. This is a perfect example of using the model's reasoning capabilities to provide real value to users with dietary restrictions. You can see a [demonstration of the app on YouTube](https://www.youtube.com/watch?v=vqFfZMcezus).

The prompt for such a feature would be more analytical, asking the model to reason about the food items:

```dart
class NutritionAnalyzer {
  InferenceChat? _analyzerAI;

  Future<void> initialize() async {
    final model = await FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.gemmaIt, // Vision model is required
      supportImage: true,
    );
    _analyzerAI = await model.createChat(supportImage: true);
  }

  Future<String> analyzeDishForAllergens(Uint8List menuImage, String dishName) async {
    final prompt = Message.withImage(
      text: "Look at this menu. What are the likely ingredients in the '$dishName' dish? Please list common allergens it might contain, such as nuts, dairy, or gluten.",
      imageBytes: menuImage,
      isUser: true,
    );

    String analysis = '';
    await for (final response in _analyzerAI!.generateChatResponseAsync(prompt)) {
      if (response is TextResponse) {
        analysis += response.token;
      }
    }
    return analysis;
  }
}
```

### 4. Emergency Buddy: Offline First-Aid Assistant

Another inspiring project is [Emergency Buddy](https://github.com/TinyBigLabs/emergency-buddy), an app that acts as a reliable, offline-first first-aid assistant. Developed by [Siddharth Joshi](https://www.linkedin.com/in/siddharth-joshi-/), [Vera Austermann](https://www.linkedin.com/in/vera-austermann/), and [Jakub Niemiec](https://www.linkedin.com/in/jakub-niemiec/), it's designed to provide step-by-step instructions for various emergency situations, from cuts and burns to more serious injuries.

As shown in their [YouTube demonstration](https://www.youtube.com/watch?v=i2Zwoo4WGGc), the app's key feature is its ability to run on-device, making it a dependable tool even without an internet connection. To ensure the guidance is safe and accurate, the team used LoRA to fine-tune a Gemma model specifically on medical terminology.

A prompt to the fine-tuned model might look like this:

```dart
class FirstAidAssistant {
  InferenceChat? _assistantAI;

  Future<void> initialize() async {
    // Load the base Gemma model and the fine-tuned LoRA weights
    final model = await FlutterGemmaPlugin.instance.createModel(
      modelType: ModelType.gemmaIt, 
      // LoRA weights would be applied here
    );
    _assistantAI = await model.createChat();
  }

  Future<String> getInstructionsForBurn() async {
    final prompt = Message.text(
      text: "A person has a second-degree burn on their arm. What are the immediate first-aid steps I should take?",
      isUser: true,
    );

    String instructions = '';
    await for (final response in _assistantAI!.generateChatResponseAsync(prompt)) {
      if (response is TextResponse) {
        instructions += response.token;
      }
    }
    return instructions;
  }
}
```

---

## Future Roadmap and Community

The flutter_gemma plugin is actively evolving. Here's what's coming next and how you can be part of the journey:

### Upcoming Features

**Next Up:**
*   **Full Multimodal Web Support:** Achieving full feature parity for image input on the web platform.
*   **Text Embedder Support:** Adding the ability to generate text embeddings, a crucial first step for on-device search.
*   **On-Device RAG Pipelines:** Implementing helper classes and examples for building full Retrieval-Augmented Generation systems that can query a local vector database.

**Further Future:**
*   **Desktop Support (macOS, Windows, Linux):** Bringing on-device inference to desktop platforms.
*   **Audio & Video Input:** Expanding multimodal capabilities to include processing audio and video streams.
*   **Audio Output (Text-to-Speech):** Integrating on-device text-to-speech to allow the AI to respond with voice.

### Contributing to the Project

I built flutter_gemma because I believe on-device AI is the future of mobile apps. The community response has been incredible, and I'd love your help making it even better:

**Ways to Contribute:**
- **Report Issues:** Found a bug? Open an issue on GitHub.
- **Fix Bugs:** See an open issue you can solve? Feel free to submit a pull request.
- **Implement Features:** Inspired by the roadmap? Contributions to new features are welcome.
- **Share Examples:** Built something cool? Share it with the community.
- **Improve Documentation:** Help make the learning curve easier for newcomers.
- **Test New Models:** Try new model releases and share performance data.

**GitHub Repository:** [https://github.com/DenisovAV/flutter_gemma](https://github.com/DenisovAV/flutter_gemma)

A special thank you to all the contributors who have helped improve this project, including @leehack, @Maksimka101, @arrrrny, @gerfalcon, @AlexVegner, and @Vinayak006.

---

## Conclusion

Building AI-powered Flutter apps isn't just about implementing technology — it's about creating experiences that genuinely help users accomplish their goals. The flutter_gemma plugin gives you the tools, but the real magic happens when you combine AI capabilities with thoughtful UX design.

### Key Takeaways

**Technical Insights:**
- Choose models based on your specific use case, not just capabilities
- Streaming responses dramatically improve perceived performance
- Function calling transforms AI from text generator to actual assistant
- Vision capabilities open entirely new categories of mobile apps

**User Experience Lessons:**
- Always show loading states during model initialization
- Handle edge cases gracefully — AI can be unpredictable
- Make AI reasoning transparent when it adds value (thinking mode)
- Optimize for mobile constraints (memory, battery, thermal)

**Production Readiness:**
- Implement proper error handling and recovery
- Plan your model distribution strategy early
- Consider privacy and security from day one
- Test extensively on real devices, not just simulators

### What's Next?

The on-device AI revolution is just beginning. As models get smaller and more capable, and as mobile hardware gets more powerful, we're entering an era where every app can have AI superpowers.

I encourage you to:
1. **Start Small** - Pick one AI feature and implement it well
2. **Iterate Based on Usage** - Let real user behavior guide your AI implementation
3. **Share Your Learnings** - The community grows stronger when we learn together
4. **Think Beyond Chat** - AI can enhance any user interaction, not just conversations

### Get Started Today

Ready to build your first AI-powered Flutter app? Here's your action plan:

1. **Install flutter_gemma** and run the basic chat example
2. **Choose your model** based on the use cases I outlined
3. **Implement one advanced feature** (multimodal, function calling, or thinking mode)
4. **Test on real devices** and optimize performance
5. **Share your experience** with the community

The future of mobile apps is intelligent, responsive, and deeply personal. With flutter_gemma, you have everything you need to be part of building that future.

---

*Want to see more AI-powered Flutter content? Follow me for deep dives into mobile AI, performance optimization, and real-world implementation strategies. Let's build the future of intelligent mobile apps together.*

**Connect with me:**
- GitHub: [@DenisovAV](https://github.com/DenisovAV)
- Medium: [@denisov.shureg](https://medium.com/@denisov.shureg)
- Twitter: [Your Twitter Handle]

*This article is part of my ongoing series about practical AI implementation in mobile apps. Next up: "Building Fully Autonomous Offline Agents with RAG" - subscribe to stay updated.*

The future is closer than you think, and offline agents are a big part of it.
