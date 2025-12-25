    # Flutter Gemma

[![CI Tests](https://github.com/DenisovAV/flutter_gemma/actions/workflows/test.yml/badge.svg)](https://github.com/DenisovAV/flutter_gemma/actions/workflows/test.yml)
[![Release Build](https://github.com/DenisovAV/flutter_gemma/actions/workflows/release.yml/badge.svg)](https://github.com/DenisovAV/flutter_gemma/actions/workflows/release.yml)
[![pub package](https://img.shields.io/pub/v/flutter_gemma.svg)](https://pub.dev/packages/flutter_gemma)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/flutter_gemma)

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
- **🖼️ Multimodal Support:** Text + Image input with Gemma 3 Nano vision models 
- **🛠️ Function Calling:** Enable your models to call external functions and integrate with other services (supported by select models)
- **🧠 Thinking Mode:** View the reasoning process of DeepSeek models with <think> blocks 
- **🛑 Stop Generation:** Cancel text generation mid-process on Android devices 
- **⚙️ Backend Switching:** Choose between CPU and GPU backends for each model individually in the example app 
- **🔍 Advanced Model Filtering:** Filter models by features (Multimodal, Function Calls, Thinking) with expandable UI
- **📊 Model Sorting:** Sort models alphabetically, by size, or use default order in the example app 
- **LoRA Support:** Efficient fine-tuning and integration of LoRA (Low-Rank Adaptation) weights for tailored AI behavior.
- **📥 Enhanced Downloads:** Smart retry logic and ETag handling for reliable model downloads from HuggingFace CDN
- **🔧 Download Reliability:** Automatic resume/restart logic for interrupted downloads with exponential backoff
- **🔧 Model Replace Policy:** Configurable model replacement system (keep/replace) with automatic model switching
- **📊 Text Embeddings:** Generate vector embeddings from text using EmbeddingGemma and Gecko models
- **🔧 Unified Model Management:** Single system for managing both inference and embedding models with automatic validation
- **💾 Web Persistent Caching:** Models persist across browser restarts using Cache API (Web only)

## Model File Types

Flutter Gemma supports different model file formats, which are grouped into **two types** based on how chat templates are handled:

### Type 1: MediaPipe-Managed Templates
- **`.task` files:** MediaPipe-optimized format for mobile (Android/iOS)
- **`.litertlm` files:** LiterTLM format optimized for web platform

Both formats have **identical behavior** — MediaPipe handles chat templates internally.

### Type 2: Manual Template Formatting
- **`.bin` files:** Standard binary format
- **`.tflite` files:** TensorFlow Lite format

Both formats require **manual chat template formatting** in your code.

**Note:** The plugin automatically detects the file extension and applies appropriate formatting. When specifying `ModelFileType` in your code:
- Use `ModelFileType.task` for `.task` and `.litertlm` files (same behavior)
- Use `ModelFileType.binary` for `.bin` and `.tflite` files (same behavior)

## Model Capabilities

The example app offers a curated list of models, each suited for different tasks. Here's a breakdown of the models available and their capabilities:

| Model Family | Best For | Function Calling | Thinking Mode | Vision | Languages | Size |
|---|---|:---:|:---:|:---:|---|---|
| **Gemma 3 Nano** | On-device multimodal chat and image analysis. | ✅ | ❌ | ✅ | Multilingual | 3-6GB |
| **Phi-4 Mini** | Advanced reasoning and instruction following. | ✅ | ❌ | ❌ | Multilingual | 3.9GB |
| **DeepSeek R1** | High-performance reasoning and code generation. | ✅ | ✅ | ❌ | Multilingual | 1.7GB |
| **Qwen 2.5** | Strong multilingual chat and instruction following. | ✅ | ❌ | ❌ | Multilingual | 1.6GB |
| **Hammer 2.1** | Lightweight action model for tool usage. | ✅ | ❌ | ❌ | Multilingual | 0.5GB |
| **Gemma 3 1B** | Balanced and efficient text generation. | ✅ | ❌ | ❌ | Multilingual | 0.5GB |
| **Gemma 3 270M**| Ideal for fine-tuning (LoRA) for specific tasks | ❌ | ❌ | ❌ | Multilingual | 0.3GB |
| **FunctionGemma 270M**| Specialized for function calling on-device | ✅ | ❌ | ❌ | Multilingual | 0.3GB |
| **TinyLlama 1.1B**| Extremely compact, general-purpose chat. | ❌ | ❌ | ❌ | English-focused | 1.2GB |
| **Llama 3.2 1B** | Efficient instruction following | ❌ | ❌ | ❌ | Multilingual | 1.1GB |

## ModelType Reference

When installing models, you need to specify the correct `ModelType`. Use this table to find the right type for your model:

| Model Family | ModelType | Examples |
|--------------|-----------|----------|
| **Gemma (all variants)** | `ModelType.gemmaIt` | Gemma 2B, Gemma 7B, Gemma-2 2B, Gemma-3 1B, Gemma 3 270M, Gemma 3 Nano E2B/E4B |
| **DeepSeek** | `ModelType.deepSeek` | DeepSeek R1, DeepSeek-R1-Distill-Qwen-1.5B |
| **Qwen** | `ModelType.qwen` | Qwen 2.5 1.5B Instruct |
| **Llama** | `ModelType.llama` | Llama 3.2 1B, TinyLlama 1.1B |
| **Hammer** | `ModelType.hammer` | Hammer 2.1 0.5B |
| **FunctionGemma** | `ModelType.functionGemma` | FunctionGemma 270M IT |
| **Phi / Falcon / StableLM** | `ModelType.general` | Phi-2, Phi-3, Phi-4, Falcon-RW-1B, StableLM-3B |

**Usage Example:**
```dart
// Gemma models
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url).install();

// DeepSeek models
await FlutterGemma.installModel(modelType: ModelType.deepSeek)
  .fromNetwork(url).install();

// Phi-4 (uses general type)
await FlutterGemma.installModel(modelType: ModelType.general)
  .fromNetwork(url).install();
```

## Installation

1.  Add `flutter_gemma` to your `pubspec.yaml`:

    ```yaml
    dependencies:
      flutter_gemma: latest_version
    ```

2.  Run `flutter pub get` to install.

## Setup

> **⚠️ Important:** Complete platform-specific setup before using the plugin.

1. **Download Model and optionally LoRA Weights:** Obtain a pre-trained Gemma model (recommended: 2b or 2b-it) [from Kaggle](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/)
* For **multimodal support**, download [Gemma 3 Nano models](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) or [Gemma 3 Nano in LitertLM format](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm) that support vision input
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

* **For embedding models**, add force_load to `Podfile`'s post_install hook:
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    # Required for embedding models (TensorFlow Lite SelectTfOps)
    if target.name == 'Runner'
      target.build_configurations.each do |config|
        sdk = config.build_settings['SDKROOT']
        if sdk.nil? || !sdk.include?('simulator')
          config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
          config.build_settings['OTHER_LDFLAGS'] << '-force_load'
          config.build_settings['OTHER_LDFLAGS'] << '$(PODS_ROOT)/TensorFlowLiteSelectTfOps/Frameworks/TensorFlowLiteSelectTfOps.xcframework/ios-arm64/TensorFlowLiteSelectTfOps.framework/TensorFlowLiteSelectTfOps'
        end
      end
    end
  end
end
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

* **For release builds with ProGuard/R8 enabled**, the plugin automatically includes necessary ProGuard rules. If you encounter issues with `UnsatisfiedLinkError` or missing classes in release builds, ensure your `proguard-rules.pro` includes:

```proguard
# MediaPipe
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# RAG functionality
-keep class com.google.ai.edge.localagents.** { *; }
-dontwarn com.google.ai.edge.localagents.**
```

**Web**

* Web currently works only GPU backend models, CPU backend models are not supported by MediaPipe yet
* **Model compatibility**: Mobile `.task` models often don't work on web. Use web-specific variants: `-web.task` or `.litertlm` files. Check model repository for web-compatible versions.

* Add dependencies to `index.html` file in web folder
```html
  <script type="module">
  import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.25';
  window.FilesetResolver = FilesetResolver;
  window.LlmInference = LlmInference;
  </script>
```

## Quick Start

> **⚠️ Important:** Complete [platform setup](#setup) before running this code.

### 1. Install a Model (One Time)

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// Install model
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
).fromNetwork(
  'https://huggingface.co/google/gemma-3-2b-it/resolve/main/gemma-3-2b-it-gpu-int8.task',
  token: 'your_hf_token',
).withProgress((progress) {
  print('Downloading: ${progress.percentage}%');
}).install();
```

### 2. Create and Use Model (Multiple Times)

```dart
// Create model with specific configuration
final model = await FlutterGemma.getActiveModel(
  maxTokens: 2048,
  preferredBackend: PreferredBackend.gpu,
);

// Use model
final chat = await model.createChat();
await chat.addQueryChunk(Message.text(
  text: 'Explain quantum computing',
  isUser: true,
));
final response = await chat.generateChatResponse();

// Cleanup
await chat.close();
await model.close();
```

### 3. Multiple Instances from Same Model

```dart
// Install once
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url).install();

// Create multiple instances
final quickModel = await FlutterGemma.getActiveModel(maxTokens: 512);
final deepModel = await FlutterGemma.getActiveModel(maxTokens: 4096);
// Both use the SAME model file!
```

## Installation Sources

```dart
// Network
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork('https://example.com/model.task', token: 'optional')
  .install();

// Flutter assets
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromAsset('assets/models/model.task')
  .install();

// Native bundle
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromBundled('model.task')
  .install();

// External file
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromFile('/path/to/model.task')
  .install();
```

## Modern API vs Legacy API

### Modern API (Recommended) ✅

**Benefits:**
- ✅ Cleaner, more intuitive
- ✅ Type-safe ModelSource
- ✅ Automatic active model management
- ✅ Install once, create many instances

**Usage:**
```dart
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url).install();
final model = await FlutterGemma.getActiveModel(maxTokens: 2048);
```

### Legacy API ⚠️ Deprecated

> **⚠️ DEPRECATED:** This API is maintained for backwards compatibility only. New projects should use the [Modern API](#modern-api-recommended-) above.

Still works but requires manual ModelType specification:
```dart
final model = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt,  // Must specify every time
  maxTokens: 2048,
);
```

---

### Initialize Flutter Gemma

Add to your `main.dart`:

```dart
import 'package:flutter_gemma/core/api/flutter_gemma.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: Initialize with HuggingFace token for gated models
  FlutterGemma.initialize(
    huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN'),
    maxDownloadRetries: 10,
  );

  runApp(MyApp());
}
```

**Configuration Options:**
- `huggingFaceToken`: Authentication token for gated models (Gemma 3 Nano, EmbeddingGemma)
- `maxDownloadRetries`: Number of retry attempts for failed downloads (default: 10)
- `enableWebCache`: **(Web only)** Enable persistent caching via Cache API (default: true)
  - `true`: Models persist across browser restarts (recommended for production)
  - `false`: Ephemeral mode, models cleared when closing browser (useful for testing/demos)

**Example:**
```dart
FlutterGemma.initialize(
  huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN'),
  maxDownloadRetries: 10,
  enableWebCache: false,  // Disable persistent cache (web only)
);
```

**Next Steps:**
- 📖 [Authentication Setup](#huggingface-authentication) - Configure tokens for gated models
- 📦 [Model Sources](#model-sources) - Learn about different model sources
- 🌐 [Platform Support](#platform-support-details) - Web vs Mobile differences
- 🔄 [Migration Guide](#migration-from-legacy-to-modern-api) - Upgrade from Legacy API
- 📚 [Legacy API Documentation](#usage-legacy-api) - For backwards compatibility

## HuggingFace Authentication 🔐

Many models require authentication to download from HuggingFace. **Never commit tokens to version control.**

### ✅ Recommended: config.json Pattern

This is the **most secure** way to handle tokens in development and production.

**Step 1:** Create config template file `config.json.example`:
```json
{
  "HUGGINGFACE_TOKEN": ""
}
```

**Step 2:** Copy and add your token:
```bash
cp config.json.example config.json
# Edit config.json and add your token from https://huggingface.co/settings/tokens
```

**Step 3:** Add to `.gitignore`:
```gitignore
# Never commit tokens!
config.json
```

**Step 4:** Run with config:
```bash
flutter run --dart-define-from-file=config.json
```

**Step 5:** Access in code:
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Read from environment (populated by --dart-define-from-file)
  const token = String.fromEnvironment('HUGGINGFACE_TOKEN');

  // Initialize with token (optional if all models are public)
  FlutterGemma.initialize(
    huggingFaceToken: token.isNotEmpty ? token : null,
  );

  runApp(MyApp());
}
```

### Alternative: Environment Variables

```bash
export HUGGINGFACE_TOKEN=hf_your_token_here
flutter run --dart-define=HUGGINGFACE_TOKEN=$HUGGINGFACE_TOKEN
```

### Alternative: Per-Download Token

```dart
// Pass token directly for specific downloads
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromNetwork(
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    token: 'hf_your_token_here',  // ⚠️ Not recommended - use config.json
  )
  .install();
```

### Which Models Require Authentication?

**Common gated models:**
- ✅ **Gemma 3 Nano** (E2B, E4B) - `google/` repos are gated
- ✅ **Gemma 3 1B** - `litert-community/` requires access
- ✅ **Gemma 3 270M** - `litert-community/` requires access
- ✅ **EmbeddingGemma** - `litert-community/` requires access

**Public models (no auth needed):**
- ❌ **DeepSeek, Qwen2.5, TinyLlama** - Public repos

**Get your token:** https://huggingface.co/settings/tokens

**Grant access to gated repos:** Visit model page → "Request Access" button

## Model Sources 📦

Flutter Gemma supports multiple model sources with different capabilities:

| Source Type | Platform | Progress | Resume | Authentication | Use Case |
|-------------|----------|----------|--------|----------------|----------|
| **NetworkSource** | All | ✅ Detailed | ✅ Yes | ✅ Supported | HuggingFace, CDNs, private servers |
| **AssetSource** | All | ⚠️ End only | ❌ No | ❌ N/A | Models bundled in app assets |
| **BundledSource** | All | ⚠️ End only | ❌ No | ❌ N/A | Native platform resources |
| **FileSource** | Mobile only | ⚠️ End only | ❌ No | ❌ N/A | User-selected files (file picker) |

### NetworkSource - Internet Downloads

Downloads models from HTTP/HTTPS URLs with full progress tracking and authentication.

**Features:**
- ✅ Progress tracking (0-100%)
- ✅ Resume after interruption (ETag support)
- ✅ HuggingFace authentication
- ✅ Smart retry logic with exponential backoff
- ✅ Background downloads on mobile
- ✅ Cancellable downloads with CancelToken

**Example:**
```dart
// Public model
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromNetwork('https://example.com/model.bin')
  .withProgress((progress) => print('$progress%'))
  .install();

// Private model with authentication
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromNetwork(
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/model.task',
    token: 'hf_...',  // Or use FlutterGemma.initialize(huggingFaceToken: ...)
  )
  .withProgress((progress) => setState(() => _progress = progress))
  .install();
```

**Cancelling Downloads:**

Use `CancelToken` to cancel downloads in progress:

```dart
import 'package:flutter_gemma/core/model_management/cancel_token.dart';

// Create cancel token
final cancelToken = CancelToken();

// Start download with cancel token
final future = FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromNetwork(url)
  .withCancelToken(cancelToken)  // ← Pass cancel token via builder
  .withProgress((progress) => print('Progress: $progress%'))
  .install();

// Cancel download from another part of your code
// (e.g., user pressed cancel button)
cancelToken.cancel('User cancelled download');

// Handle cancellation
try {
  await future;
  print('Download completed');
} catch (e) {
  if (CancelToken.isCancel(e)) {
    print('Download was cancelled by user');
  } else {
    print('Download failed: $e');
  }
}

// Check if cancelled
if (cancelToken.isCancelled) {
  print('Reason: ${cancelToken.cancelReason}');
}
```

**CancelToken Features:**
- ✅ Non-breaking: Optional parameter, existing code works without changes
- ✅ Works with network downloads (inference + embedding models)
- ✅ Cancels ALL files in multi-file downloads (embedding: model + tokenizer)
- ✅ Platform-independent (Mobile + Web)
- ✅ Throws `DownloadCancelledException` for proper error handling
- ✅ Thread-safe cancellation

### AssetSource - Flutter Assets

Copies models from Flutter assets (declared in `pubspec.yaml`).

**Features:**
- ✅ No network required
- ✅ Fast installation (local copy)
- ⚠️ Increases app size significantly
- ✅ Works offline

**Example:**
```dart
// 1. Add to pubspec.yaml
// assets:
//   - models/gemma-2b-it.bin

// 2. Install from asset
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromAsset('models/gemma-2b-it.bin')
  .install();
```

### BundledSource - Native Resources

**Production-Ready Offline Models**: Include small models directly in your app bundle for instant availability without downloads.

**Use Cases:**
- ✅ Offline-first applications (works without internet from first launch)
- ✅ Small models (Gemma 3 270M ~300MB)
- ✅ Core features requiring guaranteed availability
- ⚠️ **Not for large models** (increases app size significantly)

**Platform Setup:**

**Android** (`android/app/src/main/assets/models/`)
```bash
# Place your model file
android/app/src/main/assets/models/gemma-3-270m-it.task
```

**iOS** (Add to Xcode project)
1. Drag model file into Xcode project
2. Check "Copy items if needed"
3. Add to target membership

**Web** (Static files in `web/` directory)
```bash
# Place model files in web/ directory
example/web/gemma-3-270m-it.task

# Files are automatically copied to build/web/ during production build
flutter build web
```

⚠️ **Web Platform Limitation:**
- **Production only**: Bundled resources work ONLY in production builds (`flutter build web`)
- **Debug mode**: Files in `web/` are NOT served by `flutter run` dev server
- **For development**: Use `NetworkSource` or `AssetSource` instead

**Features:**
- ✅ Zero network dependency
- ✅ No installation delay
- ✅ No storage permission needed
- ✅ Direct path usage (no file copying)

**Example:**
```dart
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromBundled('gemma-3-270m-it.task')
  .install();
```

**App Size Impact:**
- Gemma 3 270M: ~300MB
- TinyLlama 1.1B: ~1.2GB
- Consider hosting large models for download instead

### FileSource - External Files (Mobile Only)

References external files (e.g., user-selected via file picker).

**Features:**
- ✅ No copying (references original file)
- ✅ Protected from cleanup
- ❌ **Web not supported** (no local file system)

**Example:**
```dart
// Mobile only - after user selects file with file_picker
final path = '/data/user/0/com.app/files/model.task';
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromFile(path)
  .install();
```

**Important:** On web, FileSource only works with URLs or asset paths, not local file system paths.

## Migration from Legacy to Modern API 🔄

If you're upgrading from the Legacy API, here are common migration patterns:

### Installing Models

<table>
<tr>
<th>Legacy API</th>
<th>Modern API</th>
</tr>
<tr>
<td>

```dart
// Network download
final spec = MobileModelManager.createInferenceSpec(
  name: 'model.bin',
  modelUrl: 'https://example.com/model.bin',
);

await FlutterGemmaPlugin.instance.modelManager
  .downloadModelWithProgress(spec, token: token)
  .listen((progress) {
    print('${progress.overallProgress}%');
  });
```

</td>
<td>

```dart
// Network download
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromNetwork(
    'https://example.com/model.bin',
    token: token,
  )
  .withProgress((progress) {
    print('$progress%');
  })
  .install();
```

</td>
</tr>
<tr>
<td>

```dart
// From assets
await modelManager.installModelFromAssetWithProgress(
  'model.bin',
  loraPath: 'lora.bin',
).listen((progress) {
  print('$progress%');
});
```

</td>
<td>

```dart
// From assets
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromAsset('model.bin')
  .withProgress((progress) {
    print('$progress%');
  })
  .install();

// LoRA weights can be installed with the model
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromAsset('model.bin')
  .withLoraFromAsset('lora.bin')
  .install();
```

</td>
</tr>
</table>

### Checking Model Installation

<table>
<tr>
<th>Legacy API</th>
<th>Modern API</th>
</tr>
<tr>
<td>

```dart
final spec = MobileModelManager.createInferenceSpec(
  name: 'model.bin',
  modelUrl: url,
);

final isInstalled = await FlutterGemmaPlugin
  .instance.modelManager
  .isModelInstalled(spec);
```

</td>
<td>

```dart
final isInstalled = await FlutterGemma
  .isModelInstalled('model.bin');
```

</td>
</tr>
</table>

### Key Migration Notes

- ✅ **Simpler imports**: Use `package:flutter_gemma/core/api/flutter_gemma.dart`
- ✅ **Builder pattern**: Chain methods for cleaner code
- ✅ **Callback-based progress**: Simpler than streams for most cases
- ✅ **Type-safe sources**: Compile-time validation of source types
- ⚠️ **Breaking change**: Progress values are now `int` (0-100) instead of `DownloadProgress` object
- ⚠️ **Separate files**: Model and LoRA weights installed independently

### Model Creation and Inference

**Modern API (Recommended):**

```dart
// Create model with runtime configuration
final inferenceModel = await FlutterGemma.getActiveModel(
  maxTokens: 2048,
  preferredBackend: PreferredBackend.gpu,
);

final chat = await inferenceModel.createChat();
await chat.addQueryChunk(Message.text(text: 'Hello!', isUser: true));
final response = await chat.generateChatResponse();
```

**Legacy API (Still supported):**

```dart
// Works with both Legacy and Modern installation methods
final inferenceModel = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt,
  preferredBackend: PreferredBackend.gpu,
  maxTokens: 2048,
);

final chat = await inferenceModel.createChat();
await chat.addQueryChunk(Message.text(text: 'Hello!', isUser: true));
final response = await chat.generateChatResponse();
```

## Usage (Legacy API) ⚠️ DEPRECATED

<details>
<summary><b>⚠️ Click to expand Legacy API documentation (for backwards compatibility)</b></summary>

> **⚠️ DEPRECATED:** This API is maintained for backwards compatibility only.
>
> **For new projects, use the [Modern API](#quick-start) instead.**
>
> **Why migrate?**
> - ✅ **Modern API:** Fluent builder pattern, type-safe sources, callback-based progress, better error messages
> - ⚠️ **Legacy API:** Direct method calls, stream-based progress, manual state management
>
> **Migration Guide:** See [Migration from Legacy to Modern API](#migration-from-legacy-to-modern-api-) section.

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

**Model Replace Policy**

Configure how the plugin handles switching between different models:

```dart
// Set policy to keep all models (default behavior)
await modelManager.setReplacePolicy(ModelReplacePolicy.keep);

// Set policy to replace old models (saves storage space)
await modelManager.setReplacePolicy(ModelReplacePolicy.replace);

// Check current policy
final currentPolicy = modelManager.replacePolicy;
```

**Automatic Model Management**

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

**🖼️ Multimodal Models:**
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

2) **🖼️ Multimodal Session:**

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

**🖼️ Multimodal Chat:**
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

### FunctionGemma - Specialized Function Calling Model

[FunctionGemma](https://huggingface.co/google/functiongemma-270m-it) is a specialized 270M parameter model from Google, optimized for function calling on mobile devices.

#### Pre-converted Models

Ready-to-use `.task` files:

| Model | Description | Link |
|-------|-------------|------|
| **FunctionGemma 270M IT** | Original Google model | [sasha-denisov/function-gemma-270M-it](https://huggingface.co/sasha-denisov/function-gemma-270M-it) |
| **FunctionGemma Flutter Demo** | Fine-tuned for example app (`change_background_color`, `change_app_title`, `show_alert`) | [sasha-denisov/functiongemma-flutter-gemma-demo](https://huggingface.co/sasha-denisov/functiongemma-flutter-gemma-demo) |

#### Usage

```dart
// Install FunctionGemma
await FlutterGemma.installModel(
  modelType: ModelType.functionGemma,
).fromNetwork(
  'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task',
).install();

// Create model
final model = await FlutterGemma.getActiveModel(
  maxTokens: 1024,
  preferredBackend: PreferredBackend.gpu,
);

// Use with function calling
final chat = await model.createChat(
  tools: myTools,
  supportsFunctionCalls: true,
);
```

#### Platform Support

| Platform | Status |
|----------|--------|
| Android | ✅ Full support |
| iOS | ✅ Full support |
| Web | ❌ Not supported yet |

#### Fine-tuning FunctionGemma

You can fine-tune FunctionGemma for your custom functions using the provided Colab notebooks:

**Pipeline:**
1. [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/DenisovAV/flutter_gemma/blob/main/colabs/functiongemma_finetuning.ipynb) Fine-tune the model on your training data
2. [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/DenisovAV/flutter_gemma/blob/main/colabs/functiongemma_to_tflite.ipynb) Convert PyTorch → TFLite
3. [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/DenisovAV/flutter_gemma/blob/main/colabs/functiongemma_tflite_to_task.ipynb) Bundle TFLite → MediaPipe `.task`

**Training Data Format** (`training_data.jsonl`):
```json
{"user_content": "make it red", "tool_name": "change_background_color", "tool_arguments": "{\"color\": \"red\"}"}
{"user_content": "show welcome message", "tool_name": "show_alert", "tool_arguments": "{\"title\": \"Welcome\", \"message\": \"Hello!\"}"}
```

**Requirements:**
- Google Colab with A100 GPU
- HuggingFace account with [accepted Gemma license](https://huggingface.co/google/functiongemma-270m-it)
- HuggingFace token with write access (for uploading)

#### FunctionGemma Format

FunctionGemma uses a special format (different from JSON-based function calling):

**Function Call Output:**
```
<start_function_call>call:change_background_color{color:<escape>red<escape>}<end_function_call>
```

The `flutter_gemma` plugin handles this format automatically via `FunctionCallParser`.

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

10. **📊 Text Embeddings & RAG (Retrieval-Augmented Generation)**

Generate vector embeddings from text and perform semantic search with local vector storage. This enables RAG applications with on-device inference and privacy-preserving semantic search.

### Platform Support

| Feature | Android | iOS | Web |
|---------|---------|-----|-----|
| **Embedding Generation** | ✅ Full | ✅ Full | ✅ Full |
| **VectorStore (RAG)** | ✅ SQLite | ✅ SQLite | ✅ SQLite WASM |

- **Mobile (Android/iOS)**: Full RAG support with SQLite-based VectorStore
- **Web**: Full RAG support with SQLite WASM (wa-sqlite + OPFS) - see [Web Setup](#web-setup-embeddings--vectorstore) below

### Supported Embedding Models

- **EmbeddingGemma-300M** - 300M parameters, generates 768D embeddings with varying max sequence lengths (256, 512, 1024, 2048 tokens)
- **Gecko-110m** - 110M parameters, generates 768D embeddings with varying max sequence lengths (64, 256, 512 tokens)

**Note:** Numbers in model names (64, 256, 512, 1024, 2048) refer to **max sequence length** (context window size in tokens), **NOT** embedding dimension. All these models output **768-dimensional embeddings** regardless of sequence length.

### Install Embedding Model

```dart
// Install from network with progress tracking
await FlutterGemma.installEmbedder()
  .modelFromNetwork(
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
    token: 'hf_your_token_here',  // Required for gated models
  )
  .tokenizerFromNetwork(
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
  )
  .withModelProgress((progress) => print('Model: $progress%'))
  .withTokenizerProgress((progress) => print('Tokenizer: $progress%'))
  .install();

// Or from assets
await FlutterGemma.installEmbedder()
  .modelFromAsset('models/embeddinggemma.tflite')
  .tokenizerFromAsset('models/sentencepiece.model')
  .install();
```

### Generate Text Embeddings

```dart
// Create embedding model instance
final embeddingModel = await FlutterGemma.getActiveEmbedder(
  preferredBackend: PreferredBackend.gpu, // Optional: use GPU acceleration
);

// Generate embedding for single text
final embedding = await embeddingModel.generateEmbedding('Hello, world!');
print('Embedding vector: ${embedding.take(5)}...'); // Show first 5 dimensions
print('Embedding dimension: ${embedding.length}');

// Generate embeddings for multiple texts
final embeddings = await embeddingModel.generateEmbeddings([
  'Hello, world!',
  'How are you?',
  'Flutter is awesome!'
]);
print('Generated ${embeddings.length} embeddings');

// Get embedding model dimension
final dimension = await embeddingModel.getDimension();
print('Model dimension: $dimension');

// Calculate cosine similarity between embeddings
double cosineSimilarity(List<double> a, List<double> b) {
  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
}

final similarity = cosineSimilarity(embeddings[0], embeddings[1]);
print('Similarity: $similarity');

// Close model when done
await embeddingModel.close();
```

### RAG with VectorStore

**Full cross-platform support:** VectorStore uses SQLite on mobile (Android/iOS) and SQLite WASM (wa-sqlite + OPFS) on web with identical API and behavior.

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

// Step 1: Initialize VectorStore
final appDir = await getApplicationDocumentsDirectory();
final dbPath = '${appDir.path}/my_vector_store.db';
await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

// Step 2: Add documents with embeddings
final documents = [
  'Flutter is a UI toolkit for building apps',
  'Dart is the programming language used with Flutter',
  'Machine learning enables AI capabilities',
];

for (final doc in documents) {
  // Generate embedding
  final embedding = await embeddingModel.generateEmbedding(doc);

  // Add to vector store
  await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: 'doc_${documents.indexOf(doc)}',
    content: doc,
    embedding: embedding,
    metadata: {'source': 'example', 'index': documents.indexOf(doc)},
  );
}

// Step 3: Search for similar documents
final query = 'What is Flutter?';
final queryEmbedding = await embeddingModel.generateEmbedding(query);

final results = await FlutterGemmaPlugin.instance.searchSimilar(
  queryEmbedding: queryEmbedding,
  topK: 3,              // Return top 3 results
  threshold: 0.7,       // Minimum similarity score (0.0-1.0)
);

// Step 4: Use results
for (final result in results) {
  print('Score: ${result.similarity}');
  print('Content: ${result.content}');
  print('Metadata: ${result.metadata}');
}

// Step 5: RAG with inference model
final context = results.map((r) => r.content).join('\n');
final prompt = 'Context:\n$context\n\nQuestion: $query';

final inferenceModel = await FlutterGemma.getActiveModel();
final session = await inferenceModel.createSession();
await session.addQueryChunk(Message.text(text: prompt, isUser: true));
final answer = await session.getResponse();
print('Answer: $answer');

await session.close();
await inferenceModel.close();
await embeddingModel.close();
```

### Web Setup (Embeddings + VectorStore)

**Option 1: Use CDN (Recommended for most users)**

Add script tags to your `index.html`:
```html
<!-- Load from jsDelivr CDN (version 0.11.14) -->
<script src="https://cdn.jsdelivr.net/gh/DenisovAV/flutter_gemma@0.11.14/web/cache_api.js"></script>
<script type="module" src="https://cdn.jsdelivr.net/gh/DenisovAV/flutter_gemma@0.11.14/web/litert_embeddings.js"></script>
<script type="module" src="https://cdn.jsdelivr.net/gh/DenisovAV/flutter_gemma@0.11.14/web/sqlite_vector_store.js"></script>
```

**Option 2: Build locally (For development or customization)**

1. Navigate to the `web/rag` directory in the flutter_gemma package
2. Follow the detailed setup guide: [`web/rag/README.md`](web/rag/README.md)

**Quick steps:**
```bash
# Navigate to web/rag directory
cd <flutter_gemma_package_path>/web/rag

# Install dependencies
npm install

# Build modules (embeddings + VectorStore)
npm run build

# Copy to your web project
cp dist/* <your_flutter_project>/web/

# Add script tags to index.html
<script type="module" src="litert_embeddings.js"></script>
<script type="module" src="sqlite_vector_store.js"></script>
```

**See [`web/rag/README.md`](web/rag/README.md) for complete instructions.**

### Legacy API (Still supported)

<details>
<summary>Click to expand Legacy API for embeddings</summary>

```dart
// Create embedding model specification
final embeddingSpec = MobileModelManager.createEmbeddingSpec(
  name: 'EmbeddingGemma 1024',
  modelUrl: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
  tokenizerUrl: 'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
);

// Download with progress tracking
final mobileManager = FlutterGemmaPlugin.instance.modelManager as MobileModelManager;
mobileManager.downloadModelWithProgress(embeddingSpec, token: 'your_hf_token').listen(
  (progress) => print('Download progress: ${progress.overallProgress}%'),
  onError: (error) => print('Download error: $error'),
  onDone: () => print('Download completed'),
);

// Create embedding model instance
final embeddingModel = await FlutterGemmaPlugin.instance.createEmbeddingModel(
  modelPath: '/path/to/embeddinggemma-300M_seq1024_mixed-precision.tflite',
  tokenizerPath: '/path/to/sentencepiece.model',
  preferredBackend: PreferredBackend.gpu,
);
```

</details>

### Important Notes

- ✅ EmbeddingGemma models require HuggingFace authentication token for gated repositories
- ✅ Embedding models use the same unified download and management system as inference models
- ✅ Each embedding model consists of both model file (.tflite) and tokenizer file (.model)
- ✅ Different sequence length options allow trade-offs between accuracy and performance
- ✅ Modern API provides separate progress tracking for model and tokenizer downloads
- ✅ **VectorStore (RAG) is available on ALL platforms** - Android/iOS use native SQLite, Web uses SQLite WASM (wa-sqlite + OPFS)

### VectorStore Optimization (v0.11.7)

As of version 0.11.7, the VectorStore has been significantly optimized for better performance and storage efficiency:

**Performance Improvements:**
- **71% smaller storage**: Binary BLOB format instead of JSON (3 KB vs 10.5 KB per 768D embedding)
- **6.7x faster reads**: ~75 μs vs ~500 μs per document search
- **3.3x faster writes**: ~45 μs vs ~150 μs per document insertion

**New Features:**
- **Dynamic dimensions**: Auto-detects any embedding size (256D, 384D, 512D, 768D, 1024D, 1536D, 3072D, 4096D+)
- **iOS implementation**: Full VectorStore support on iOS (was stubs only before v0.11.7)
- **Cross-platform parity**: Identical behavior on Android and iOS
- **SQLite-based**: Uses SQLite for efficient storage and querying

**Migration Notes:**
- ⚠️ **Breaking change for RAG users**: Existing vector databases will be recreated on upgrade (re-indexing required)
- 📝 **Impact**: Minimal, since RAG feature is new (introduced in v0.11.5)
- ✅ **Automatic**: Database schema upgrade happens automatically on first use

**Common Embedding Dimensions:**
- 256D: Gecko Small, efficient for mobile
- 384D: MiniLM models
- 512D: Mid-range models
- 768D: BERT-base (standard) - EmbeddingGemma, Gecko default
- 1024D: BERT-large, Cohere v3
- 1536D: OpenAI Ada
- 3072D: OpenAI Large
- 4096D: Qwen-3

11. **Checking Token Usage**
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

</details>

## 🖼️ Message Types

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

## 💬 Response Types

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
- [FunctionGemma 270M](https://huggingface.co/google/functiongemma-270m-it) - Specialized function calling model
- [TinyLlama 1.1B](https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0) - Lightweight chat model
- [Hammer 2.1 0.5B](https://huggingface.co/litert-community/Hammer2.1-0.5b) - Action model with function calling
- [Llama 3.2 1B](https://huggingface.co/litert-community/Llama-3.2-1B-Instruct) - Instruction-tuned model
- [Phi-4](https://huggingface.co/litert-community/Phi-4-mini-instruct)
- [DeepSeek](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B)
- Phi-2, Phi-3, Falcon-RW-1B, StableLM-3B

### 🖼️ Multimodal Models (Vision + Text)
- [Gemma 3 Nano E2B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) - 2B parameters with vision support
- [Gemma 3 Nano E4B](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview) - 4B parameters with vision support
- [Gemma 3 Nano E2B LitertLM](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm) - 2B parameters with vision support
- [Gemma 3 Nano E4B LitertLM](https://huggingface.co/google/gemma-3n-E4B-it-litert-lm) - 4B parameters with vision support

### 📊 Text Embedding Models

All embedding models generate **768-dimensional vectors**. The numbers in names (64/256/512/1024/2048) indicate **maximum input sequence length in tokens**, not embedding dimension.

| Model | Parameters | Dimensions | Max Seq Length | Size | Best For | Auth Required |
|-------|-----------|------------|----------------|------|----------|---------------|
| **[Gecko 64](https://huggingface.co/litert-community/Gecko-110m-en)** | 110M | 768D | 64 tokens | 110MB | Short queries, real-time search | ❌ |
| **[Gecko 256](https://huggingface.co/litert-community/Gecko-110m-en)** | 110M | 768D | 256 tokens | 114MB | Balanced speed/accuracy | ❌ |
| **[Gecko 512](https://huggingface.co/litert-community/Gecko-110m-en)** | 110M | 768D | 512 tokens | 116MB | Medium context documents | ❌ |
| **[EmbeddingGemma 256](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 256 tokens | 179MB | High accuracy, short context | ✅ |
| **[EmbeddingGemma 512](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 512 tokens | 179MB | High accuracy, medium context | ✅ |
| **[EmbeddingGemma 1024](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 1024 tokens | 183MB | Long documents, detailed content | ✅ |
| **[EmbeddingGemma 2048](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 2048 tokens | 196MB | Very long documents | ✅ |

**Performance Comparison (Android Pixel 8 with GPU acceleration):**
- **Gecko 64**: ~109ms/doc embedding, 130ms search (⚡ **fastest** - 2.6x faster than EmbeddingGemma)
- **EmbeddingGemma 256**: ~286ms/doc embedding, 342ms search (🎯 **more accurate** - 300M vs 110M params)

**Use Cases:**
- ✅ **Gecko 64**: Real-time search, mobile apps, short queries (≤64 tokens), fast inference
- ✅ **Gecko 256/512**: Balanced use cases, general-purpose embeddings, good speed/quality tradeoff
- ✅ **EmbeddingGemma 256/512**: High-quality embeddings, semantic search, better accuracy
- ✅ **EmbeddingGemma 1024/2048**: Long documents, detailed content, research papers, articles

## 🛠️ Model Function Calling Support

Function calling is currently supported by the following models:

### ✅ Models with Function Calling Support
- **Gemma 3 Nano** models (E2B, E4B) - Full function calling support
- **FunctionGemma 270M** - Google's specialized function calling model (Android/iOS only)
- **Hammer 2.1 0.5B** - Action model with strong function calling capabilities
- **DeepSeek** models - Function calling + thinking mode support
- **Qwen** models - Full function calling support
- **Phi-4 Mini** - Advanced reasoning with function calling support

### ❌ Models WITHOUT Function Calling Support
- **Gemma 3 1B** models - Text generation only
- **Gemma 3 270M** - Text generation only
- **TinyLlama 1.1B** - Text generation only
- **Llama 3.2 1B** - Text generation only
- **Phi-2, Phi-3** models - Text generation only

**Important Notes:**
- When using unsupported models with tools, the plugin will log a warning and ignore the tools
- Models will work normally for text generation even if function calling is not supported
- Check the `supportsFunctionCalls` property in your model configuration

## Platform Support Details 🌐

### Feature Comparison

| Feature | Android | iOS | Web | Notes |
|---------|---------|-----|-----|-------|
| **Text Generation** | ✅ Full | ✅ Full | ✅ Full | All models supported |
| **Image Input (Multimodal)** | ✅ Full | ✅ Full | ✅ Full | Gemma 3 Nano models |
| **Function Calling** | ✅ Full | ✅ Full | ✅ Full | Select models only |
| **Thinking Mode** | ✅ Full | ✅ Full | ✅ Full | DeepSeek models |
| **Stop Generation** | ✅ Android only | ❌ Not supported | ❌ Not supported | Cancel mid-process |
| **GPU Acceleration** | ✅ Full | ✅ Full | ✅ Full | Recommended |
| **CPU Backend** | ✅ Full | ✅ Full | ❌ Not supported | MediaPipe limitation |
| **Streaming Responses** | ✅ Full | ✅ Full | ✅ Full | Real-time generation |
| **LoRA Support** | ✅ Full | ✅ Full | ✅ Full | Fine-tuned weights |
| **Text Embeddings** | ✅ Full | ✅ Full | ✅ Full | EmbeddingGemma, Gecko |
| **VectorStore (RAG)** | ✅ SQLite | ✅ SQLite | ✅ SQLite WASM | Semantic search, RAG |
| **File Downloads** | ✅ Background | ✅ Background | ✅ In-memory | Platform-specific |
| **Asset Loading** | ✅ Full | ✅ Full | ✅ Full | All source types |
| **Bundled Resources** | ✅ Full | ✅ Full | ✅ Full | Native bundles |
| **External Files (FileSource)** | ✅ Full | ✅ Full | ❌ Not supported | No local FS on web |

### Web Platform Specifics

#### Authentication
- **Required for gated models:** Gemma 3 Nano, Gemma 3 1B/270M, EmbeddingGemma
- **Configuration:** Use `FlutterGemma.initialize(huggingFaceToken: '...')` or pass token per-download
- **Storage:** Tokens stored in browser memory (not localStorage)

#### File Handling
- **Downloads:** Creates blob URLs in browser memory (no actual files)
- **Storage:** IndexedDB via `WebFileSystemService`
- **FileSource:** Only works with HTTP/HTTPS URLs or `assets/` paths
- **Local file paths:** ❌ Not supported (browser security restriction)

#### Persistent Caching (NEW in 0.11.10)

**Two Cache Modes:**

**1. Persistent Mode (default, `enableWebCache: true`):**
- Downloaded models persist across browser restarts
- Uses browser Cache API (up to 50% of disk space)
- Works for all sources (public URLs and HuggingFace gated models)
- Smart management: 30-day automatic cleanup
- Zero configuration: Automatically enabled

**2. Ephemeral Mode (`enableWebCache: false`):**
- Models stored in memory only (InMemoryRepository)
- Cleared when browser tab/window closes
- Faster development/testing workflow
- No persistent storage used
- Useful for demos, temporary testing, privacy-sensitive scenarios

```dart
// Enable persistent caching (default)
FlutterGemma.initialize(enableWebCache: true);

// Use ephemeral mode (no persistence)
FlutterGemma.initialize(enableWebCache: false);

// Check cache statistics (persistent mode only)
final stats = await FlutterGemma.instance.modelManager.getCacheStats();
print('Cached models: ${stats['cachedUrls']}');
print('Storage used: ${stats['storageUsage']} bytes');

// Clear cache if needed (persistent mode only)
await FlutterGemma.instance.modelManager.clearCache();
```

#### Backend Support
- **GPU only:** Web platform requires GPU backend (MediaPipe limitation)
- **CPU models:** ❌ Will fail to initialize on web

#### CORS Configuration
- **Required for custom servers:** Enable CORS headers on your model hosting server
- **Firebase Storage:** See [CORS configuration docs](https://firebase.google.com/docs/storage/web/download-files#cors_configuration)
- **HuggingFace:** CORS already configured correctly

#### Memory Limitations
- **Large models:** May hit browser memory limits (2GB typical)
- **Recommended:** Use smaller models (1B-2B) for web platform
- **Best models for web:**
  - Gemma 3 270M (300MB)
  - Gemma 3 1B (500MB-1GB)
  - Gemma 3 Nano E2B (3GB) - requires 6GB+ device RAM

#### Browser Cache Storage Limits

| Browser | Max Model Size | Notes |
|---------|----------------|-------|
| **Chrome/Firefox** | ~2 GB | ArrayBuffer limit |
| **Safari** | ~50 MB | ⚠️ Not suitable |

### Mobile Platform Specifics

#### Android
- **GPU Support:** Requires OpenGL libraries in `AndroidManifest.xml`
- **ProGuard:** Automatic rules included for release builds
- **Storage:** Local file system in app documents directory

#### iOS
- **Minimum version:** iOS 16.0 required for MediaPipe GenAI
- **Memory entitlements:** Required for large models (see Setup section)
- **Linking:** Static linking required (`use_frameworks! :linkage => :static`)
- **Storage:** Local file system in app documents directory
- **Embedding models:** Require force_load for TensorFlowLiteSelectTfOps in Podfile (see Setup section)

The full and complete example you can find in `example` folder

## **Important Considerations**

* **Model Size:** Larger models (such as 7b and 7b-it) might be too resource-intensive for on-device inference.
* **Function Calling Support:** Gemma 3 Nano and DeepSeek models support function calling. Other models will ignore tools and show a warning.
* **Thinking Mode:** Only DeepSeek models support thinking mode. Enable with `isThinking: true` and `modelType: ModelType.deepSeek`.
* **Multimodal Models:** Gemma 3 Nano models with vision support require more memory and are recommended for devices with 8GB+ RAM.
* **iOS Memory Requirements:** Large models require memory entitlements in `Runner.entitlements` and minimum iOS 16.0.
* **LoRA Weights:** They provide efficient customization without the need for full model retraining.
* **Development vs. Production:** For production apps, do not embed the model or LoRA weights within your assets. Instead, load them once and store them securely on the device or via a network drive.
* **Web Models:** Currently, Web support is available only for GPU backend models. Multimodal support is fully implemented.
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

**iOS Embedding Models:**
For embedding models on iOS, you must add force_load to your Podfile's post_install hook:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    # Required for embedding models
    if target.name == 'Runner'
      target.build_configurations.each do |config|
        sdk = config.build_settings['SDKROOT']
        if sdk.nil? || !sdk.include?('simulator')
          config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
          config.build_settings['OTHER_LDFLAGS'] << '-force_load'
          config.build_settings['OTHER_LDFLAGS'] << '$(PODS_ROOT)/TensorFlowLiteSelectTfOps/Frameworks/TensorFlowLiteSelectTfOps.xcframework/ios-arm64/TensorFlowLiteSelectTfOps.framework/TensorFlowLiteSelectTfOps'
        end
      end
    end
  end
end
```

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

✅ **📊 Text Embeddings** - Generate vector embeddings with EmbeddingGemma and Gecko models for semantic search applications
✅ **🔧 Unified Model Management** - Single system for managing both inference and embedding models with automatic validation

**Coming Soon:**
- On-Device RAG Pipelines
- Desktop Support (macOS, Windows, Linux)
- Audio & Video Input
- Audio Output (Text-to-Speech)
- System Instruction support

---

## ☕ Support the Project

If you find **Flutter Gemma** useful and want to support its development, consider buying me a coffee! Your support helps me:

- 🔧 Maintain and improve the plugin
- 📚 Keep documentation up-to-date
- 🐛 Fix bugs and resolve issues faster
- ✨ Add new features and model support
- 🧪 Test on more devices and platforms

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/flutter_gemma)

Every contribution, no matter how small, makes a difference. Thank you for your support! 💙