    # Flutter Gemma

[![CI Tests](https://github.com/DenisovAV/flutter_gemma/actions/workflows/test.yml/badge.svg)](https://github.com/DenisovAV/flutter_gemma/actions/workflows/test.yml)
[![Release Build](https://github.com/DenisovAV/flutter_gemma/actions/workflows/release.yml/badge.svg)](https://github.com/DenisovAV/flutter_gemma/actions/workflows/release.yml)
[![pub package](https://img.shields.io/pub/v/flutter_gemma.svg)](https://pub.dev/packages/flutter_gemma)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/DenisovAV/flutter_gemma)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/flutter_gemma)

**The plugin supports not only Gemma, but also other models. Here's the full list of supported models:** [Gemma 4 E2B/E4B](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm), [Gemma3n E2B/E4B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview), [FastVLM 0.5B](https://huggingface.co/litert-community/FastVLM-0.5B), [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT), [Gemma 3 270M](https://huggingface.co/litert-community/gemma-3-270m-it), [FunctionGemma 270M](https://huggingface.co/sasha-denisov/function-gemma-270M-it), [Qwen3 0.6B](https://huggingface.co/litert-community/Qwen3-0.6B), [Qwen 2.5](https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct), [Phi-4 Mini](https://huggingface.co/litert-community/Phi-4-mini-instruct), [DeepSeek R1](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B), [SmolLM 135M](https://huggingface.co/litert-community/SmolLM-135M-Instruct).

*Note: The flutter_gemma plugin supports Gemma 4 and Gemma3n (with **multimodal vision and audio support**), FastVLM (vision), Gemma-3, FunctionGemma, Qwen3, Qwen 2.5, Phi-4, DeepSeek R1 and SmolLM. Desktop platforms (macOS, Windows, Linux) require `.litertlm` model format.

[Gemma](https://ai.google.dev/gemma) is a family of lightweight, state-of-the art open models built from the same research and technology used to create the Gemini models

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma3.png" alt="gemma_github_cover">
</p>

Bring the power of Google's lightweight Gemma language models directly to your Flutter applications. With Flutter Gemma, you can seamlessly incorporate advanced AI capabilities into your Flutter applications, all without relying on external servers.

There is an example of using:

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/assets/gemma.gif" alt="gemma_github_gif">
</p>

## Features

- **Local Execution:** Run Gemma models directly on user devices for enhanced privacy and offline functionality.
- **Platform Support:** Compatible with iOS, Android, Web, macOS, Windows, and Linux platforms.
- **🖥️ Desktop Support:** Native desktop apps (macOS, Windows, Linux) with GPU acceleration via LiteRT-LM, called directly from Dart through `dart:ffi` — no JVM/JRE bundling. See [DESKTOP_SUPPORT.md](DESKTOP_SUPPORT.md) for details.
- **🖼️ Multimodal Support:** Text + Image input with Gemma3n vision models
- **🎙️ Audio Input:** Record and send audio messages with Gemma3n E2B/E4B models (Android, iOS device, Desktop)
- **🛠️ Function Calling:** Enable your models to call external functions and integrate with other services (supported by select models)
- **🧠 Thinking Mode:** View the reasoning process of DeepSeek and Gemma 4 models with thinking blocks
- **🛑 Stop Generation:** Cancel text generation mid-process on Android, iOS, Web, and Desktop
- **⚙️ Backend Switching:** Choose between CPU and GPU backends for each model individually in the example app 
- **🔍 Advanced Model Filtering:** Filter models by features (Multimodal, Function Calls, Thinking) with expandable UI
- **📊 Model Sorting:** Sort models alphabetically, by size, or use default order in the example app 
- **LoRA Support:** Efficient fine-tuning and integration of LoRA (Low-Rank Adaptation) weights for tailored AI behavior.
- **📥 Enhanced Downloads:** Smart retry logic with exponential backoff for reliable model downloads
- **🔧 Download Reliability:** Automatic restart logic for interrupted downloads (resume not supported by HuggingFace CDN)
- **📱 Android Foreground Service:** Large downloads (>500MB) automatically use foreground service to bypass 9-minute timeout
- **🔧 Model Replace Policy:** Configurable model replacement system (keep/replace) with automatic model switching
- **📊 Text Embeddings:** Generate vector embeddings from text using EmbeddingGemma and Gecko models
- **🔧 Unified Model Management:** Single system for managing both inference and embedding models with automatic validation
- **💾 Web Persistent Caching:** Models persist across browser restarts using Cache API (Web only)

## What's new in 0.14.1

- 🛠️ **Gemma 4 native function calling** — `ModelType.gemma4` routes tool definitions through the LiteRT-LM SDK's chat-template path (minja). The SDK renders native `<|tool>declaration:...<tool|>` tokens, the model emits `<|tool_call>...<tool_call|>`, and the SDK parses the response into structured `tool_calls` JSON. flutter_gemma surfaces it as `FunctionCallResponse` — no Dart-side prompt engineering required.

## What's new in 0.14.0

- 🖥️ **Desktop rewritten on `dart:ffi`** — no JVM, no gRPC, no separate server. Native libs auto-fetched at build time.
- 🍎 **iOS Metal GPU** for `.litertlm` models on physical devices via FFI.
- 🐧 **Linux GPU** (Vulkan/WebGPU) and 🪟 **Windows GPU** (DirectX 12) ready out of the box.
- 🤖 **Android** — Kotlin LiteRtLm dependency removed; FFI used exclusively for `.litertlm`.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## Model File Types

Flutter Gemma supports different model file formats, which are grouped into **two types** based on how chat templates are handled:

### Type 1: MediaPipe-Managed Templates
- **`.task` files:** MediaPipe-optimized format for mobile (Android/iOS)
- **`.litertlm` files:** LiteRT-LM format for Android, iOS, and Desktop platforms

Both formats have **identical behavior** — MediaPipe handles chat templates internally.

### Type 2: Manual Template Formatting
- **`.bin` files:** Standard binary format
- **`.tflite` files:** LiteRT format (formerly TensorFlow Lite)

Both formats require **manual chat template formatting** in your code.

**Note:** The plugin automatically detects the file extension and applies appropriate formatting. When specifying `ModelFileType` in your code:
- Use `ModelFileType.task` for `.task` and `.litertlm` files (same behavior)
- Use `ModelFileType.binary` for `.bin` and `.tflite` files (same behavior)

### Format by Platform

| Format | Android | iOS | Web | Desktop | Use Case |
|--------|:-------:|:---:|:---:|:-------:|----------|
| `.task` | ✅ | ✅ | ✅ | ❌ | Older models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) |
| `.litertlm` | ✅ | ✅ ¹ | ❌ | ✅ | Newer models (Gemma 4, Qwen3, FastVLM + desktop for all) |
| `-web.task` | ❌ | ❌ | ✅ | ❌ | Web-specific builds (e.g. Gemma 4, Gemma3n) |
| `.bin` | ✅ | ✅ | ✅ | ❌ | Manual chat template formatting required |
| `.tflite` | ✅ | ✅ | ✅ | ✅ | Embeddings only (EmbeddingGemma, Gecko) |

> ¹ iOS `.litertlm` runs on the FFI engine — vision and audio supported on physical devices. The Simulator stays CPU-only because Metal sim has a 256 MB single-allocation cap.

## Model Capabilities

The example app offers a curated list of models, each suited for different tasks. Here's a breakdown of the models available and their capabilities:

| Model Family | Best For | Function Calling | Thinking Mode | Vision | Languages | Size |
|---|---|:---:|:---:|:---:|---|---|
| **Gemma 4 E2B** | Next-gen multimodal chat — text, image, audio | ✅ | ✅ | ✅ | Multilingual | 2.4GB |
| **Gemma 4 E4B** | Next-gen multimodal chat — text, image, audio | ✅ | ✅ | ✅ | Multilingual | 4.3GB |
| **Gemma3n** | On-device multimodal chat and image analysis | ✅ | ❌ | ✅ | Multilingual | 3-6GB |
| **FastVLM 0.5B** | Fast vision-language inference | ❌ | ❌ | ✅ | Multilingual | 0.5GB |
| **Phi-4 Mini** | Advanced reasoning and instruction following | ✅ | ❌ | ❌ | Multilingual | 3.9GB |
| **DeepSeek R1** | High-performance reasoning and code generation | ✅ | ✅ | ❌ | Multilingual | 1.7GB |
| **Qwen3 0.6B** | Compact multilingual chat with function calling | ✅ | ✅ | ❌ | Multilingual | 586MB |
| **Qwen 2.5** | Strong multilingual chat and instruction following | ✅ | ❌ | ❌ | Multilingual | 0.5-1.6GB |
| **Gemma 3 1B** | Balanced and efficient text generation | ✅ | ❌ | ❌ | Multilingual | 0.5GB |
| **Gemma 3 270M** | Ideal for fine-tuning (LoRA) for specific tasks | ❌ | ❌ | ❌ | Multilingual | 0.3GB |
| **FunctionGemma 270M** | Specialized for function calling on-device | ✅ | ❌ | ❌ | Multilingual | 284MB |
| **SmolLM 135M** | Ultra-compact, resource-constrained devices | ❌ | ❌ | ❌ | English | 135MB |

## ModelType Reference

When installing models, you need to specify the correct `ModelType`. Use this table to find the right type for your model:

| Model Family | ModelType | Examples |
|--------------|-----------|----------|
| **Gemma 4** | `ModelType.gemma4` | Gemma 4 E2B, Gemma 4 E4B (native function-call tokens) |
| **Gemma 3 / Gemma3n** | `ModelType.gemmaIt` | Gemma 3 1B, Gemma 3 270M, Gemma3n E2B/E4B |
| **DeepSeek** | `ModelType.deepSeek` | DeepSeek R1 |
| **Qwen 2.5** | `ModelType.qwen` | Qwen 2.5 1.5B, Qwen 2.5 0.5B |
| **Qwen 3** | `ModelType.qwen3` | Qwen3 0.6B |
| **FunctionGemma** | `ModelType.functionGemma` | FunctionGemma 270M IT |
| **Phi** | `ModelType.phi` | Phi-4 Mini |
| **General** | `ModelType.general` | FastVLM 0.5B, SmolLM 135M |

> **Note**: Gemma 4 uses `ModelType.gemma4` (introduced in 0.14.1) so its native `<\|tool_call>...<tool_call\|>` tokens are routed through the LiteRT-LM SDK's chat-template path. For Gemma 3 and earlier, keep `ModelType.gemmaIt`.

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

## Platform & Architecture Support

The plugin ships native prebuilts only for the architectures below. Other ABIs fail at native load with a typed error.

| Platform        | Supported architecture            | Not supported            |
|-----------------|-----------------------------------|--------------------------|
| Android         | `arm64-v8a` (full)                | `armeabi-v7a`, `x86_64`¹ |
| iOS device      | `arm64`                           | —                        |
| iOS Simulator   | `arm64` (Apple Silicon Mac)       | `x86_64` (Intel Mac)     |
| macOS           | `arm64` (Apple Silicon)           | `x86_64` (Intel Mac)     |
| Linux           | `x86_64`, `arm64`                 | —                        |
| Windows         | `x86_64`                          | `arm64`                  |

¹ MediaPipe text inference (`.task` / `.bin`) on Android also works on `x86_64` and `armeabi-v7a` because Google ships those ABIs in `tasks-genai`. Everything else (`.litertlm` FFI, embedding via `localagents-rag`, image generation) is `arm64-v8a` only:

| Android feature                      | arm64-v8a | x86_64 | armeabi-v7a |
|--------------------------------------|:---------:|:------:|:-----------:|
| Text inference (`.task` / `.bin`)    |     ✅    |   ✅   |      ✅      |
| `.litertlm` (FFI)                    |     ✅    |   ❌   |      ❌      |
| Embedding (`localagents-rag`)        |     ✅    |   ❌   |      ❌      |
| Image generation (vision)            |     ✅    |   ❌   |      ❌      |

If your Android app uses only the arm64-only features, restrict the build to arm64 so the Play Store does not offer broken APKs to incompatible devices:

```gradle
android {
    defaultConfig {
        ndk { abiFilters 'arm64-v8a' }
    }
}
```

For development, prefer an Apple Silicon Mac — the Android emulator runs `arm64-v8a` natively, and macOS / iOS Simulator builds are arm64.

## Setup

> **⚠️ Important:** Complete platform-specific setup before using the plugin.

1. **Download Model and optionally LoRA Weights:** Obtain a model from the [Supported Models](#-supported-models) section or [HuggingFace](https://huggingface.co/litert-community)
* For **multimodal support**, download [Gemma3n models](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) or [Gemma3n in LitertLM format](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm) that support vision input
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

> Since 0.14.1, no host-side `Podfile` `post_install` is required on iOS — flutter_gemma patches the upstream LiteRT-LM `dlopen` path to use `@executable_path/Frameworks/<X>.framework/<X>` so dyld resolves Metal accelerators directly through the Native-Assets-bundled framework. This also keeps `Runner.app/Frameworks/` App-Store-clean (fixes ITMS-90432, see #245).

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
  import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
  window.FilesetResolver = FilesetResolver;
  window.LlmInference = LlmInference;
  </script>
```

**Desktop (macOS, Windows, Linux)**

> **⚠️ Desktop Model Format**
>
> Desktop platforms use **LiteRT-LM format only** (`.litertlm` files).
> MediaPipe `.task` and `.bin` models used on mobile/web are **NOT compatible** with desktop.

Since 0.14.0 desktop inference and embeddings both use the LiteRT-LM C API via `dart:ffi` directly in the Dart process — no JVM, no gRPC, no separate server. Native libraries are downloaded by `hook/build.dart` (Native Assets) at build time and bundled into the app automatically.

| Platform | Architecture | GPU Acceleration | Status |
|----------|-------------|------------------|--------|
| macOS | arm64 (Apple Silicon) | Metal | ✅ Ready |
| macOS | x86_64 (Intel) | - | ❌ Not Supported |
| Windows | x86_64 | DirectX 12 | ✅ Ready |
| Windows | arm64 | - | ❌ Not Supported |
| Linux | x86_64 | Vulkan | ✅ Ready |
| Linux | arm64 | Vulkan | ✅ Ready |

**macOS Setup:**

flutter_gemma 0.14.2+ requires a small `post_install` block in your
`macos/Podfile`. The Apple accelerator dylibs Google ships upstream
(`libGemmaModelConstraintProvider.dylib`, `libLiteRtMetalAccelerator.dylib`,
`libLiteRtTopKMetalSampler.dylib`) were linked without
`-Wl,-headerpad_max_install_names`, so Dart Native Assets' JIT bundling path
(used by `dart run` / `dart build_runner` / `flutter test` on a pure Dart
library) cannot rewrite their install_name to a long absolute path inside
`.dart_tool/lib/` and aborts (#247). To unblock both `dart run` and
`flutter build macos`, the plugin's `hook/build.dart` skips bundling those
three through Native Assets on macOS, and we instead copy them into
`App.app/Contents/Frameworks/` ourselves and patch `LiteRtLm.dylib`'s
`LC_LOAD_DYLIB` reference to the new framework path.

Paste this into your `macos/Podfile` (replacing any existing
`post_install` block) and run `pod install`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end

  # flutter_gemma 0.14.4: bundle Apple accelerator dylibs as .framework
  # bundles into Contents/Frameworks/ and re-point LiteRtLm.dylib's
  # LC_LOAD_DYLIB reference to GemmaModelConstraintProvider's new path.
  # 3-tier dylib source fallback: Native Assets cache (pub.dev users) →
  # plugin symlink → in-repo prebuilt/. See README -> macOS Setup and #247/#255.
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_targets.each do |user_target|
      phase_name = '[flutter_gemma] Setup LiteRT-LM macOS'
      existing = user_target.shell_script_build_phases.find { |p| p.name == phase_name }
      phase = existing || user_target.new_shell_script_build_phase(phase_name)
      phase.shell_script = <<~SHELL
        set -e
        FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
        if [ ! -d "${FRAMEWORKS}" ]; then
          exit 0
        fi
        # Sweep any leftover lib*.dylib symlinks from older flutter_gemma versions.
        for base in LiteRtMetalAccelerator LiteRtTopKMetalSampler GemmaModelConstraintProvider; do
          rm -f "${FRAMEWORKS}/lib${base}.dylib"
        done
        # Wrap each upstream dylib into a .framework bundle inside the app's
        # Contents/Frameworks/ so dlopen("@executable_path/../Frameworks/<X>.framework/<X>")
        # (the path the patched gpu_registry.cc uses) resolves at runtime.
        # Resolve dylib source — Native Assets cache (pub.dev), then path-dep fallbacks.
        for candidate in \
            "${HOME}/Library/Caches/flutter_gemma/native/macos_arm64" \
            "${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/flutter_gemma/native/litert_lm/prebuilt/macos_arm64" \
            "${SRCROOT}/../../native/litert_lm/prebuilt/macos_arm64"; do
          if [ -f "${candidate}/libGemmaModelConstraintProvider.dylib" ]; then
            PLUGIN_PREBUILT="${candidate}"
            break
          fi
        done
        if [ -z "${PLUGIN_PREBUILT:-}" ]; then
          echo "[flutter_gemma] ERROR: macOS companion dylibs not found. Run 'flutter clean && flutter pub get'."
          exit 1
        fi
        for base in GemmaModelConstraintProvider LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
          src="${PLUGIN_PREBUILT}/lib${base}.dylib"
          if [ ! -f "${src}" ]; then
            echo "[flutter_gemma] WARNING: ${src} not found — runtime dlopen will fail"
            continue
          fi
          fw_dir="${FRAMEWORKS}/${base}.framework"
          mkdir -p "${fw_dir}/Versions/A/Resources"
          cp "${src}" "${fw_dir}/Versions/A/${base}"
          install_name_tool -id "@rpath/${base}.framework/Versions/A/${base}" \\
            "${fw_dir}/Versions/A/${base}" 2>/dev/null || true
          (cd "${fw_dir}" && ln -sfh A Versions/Current && ln -sfh "Versions/Current/${base}" "${base}" && ln -sfh "Versions/Current/Resources" Resources)
          cat > "${fw_dir}/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${base}</string>
  <key>CFBundleIdentifier</key><string>dev.flutterberlin.flutter_gemma.${base}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
</dict>
</plist>
EOF
        done
        # Re-point LiteRtLm.dylib's LC_LOAD_DYLIB at the new framework path.
        LITERTLM="${FRAMEWORKS}/LiteRtLm.framework/Versions/A/LiteRtLm"
        if [ -f "${LITERTLM}" ]; then
          install_name_tool -change \\
            @rpath/libGemmaModelConstraintProvider.dylib \\
            @rpath/GemmaModelConstraintProvider.framework/Versions/A/GemmaModelConstraintProvider \\
            "${LITERTLM}" 2>/dev/null || true
          codesign --force --sign - "${LITERTLM}" 2>/dev/null || true
        fi
      SHELL
    end
  end
end
```

Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

**Windows Setup:**

No additional configuration required. `hook/build.dart` (Native Assets) downloads `LiteRtLm.dll` + companion DLLs + the DXC runtime (`dxil.dll`, `dxcompiler.dll` v1.9.2602) from the GitHub release on first build, verifies them via SHA256, and bundles them next to your `app.exe`. End users need the **Microsoft Visual C++ Redistributable 2019+** ([download](https://aka.ms/vs/17/release/vc_redist.x64.exe)) — most modern Windows 10/11 systems already have it.

**Linux Setup:**

No additional configuration required. Build dependencies:
```bash
sudo apt install clang cmake ninja-build libgtk-3-dev
```

For GPU acceleration, ensure Vulkan drivers are installed:
```bash
sudo apt install vulkan-tools libvulkan1
```

📚 **[Full Desktop Documentation →](DESKTOP_SUPPORT.md)**

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
await model.close();
```

### System Instructions

Control model behavior with a system-level instruction:

```dart
final chat = await model.createChat(
  systemInstruction: 'You are a concise assistant. Always respond in bullet points.',
);
```

**Platform support:**
- **Android `.litertlm` / Desktop**: Passed natively via `ConversationConfig.systemInstruction`
- **Android `.task` / iOS / Web**: Prepended to first user message as fallback

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
- `huggingFaceToken`: Authentication token for gated models (Gemma3n, EmbeddingGemma)
- `maxDownloadRetries`: Number of retry attempts for failed downloads (default: 10)
- `webStorageMode`: **(Web only)** Storage strategy for model files (default: `cacheApi`)
  - `WebStorageMode.cacheApi`: Cache API with Blob URLs (for models <2GB)
  - `WebStorageMode.streaming`: OPFS streaming (for large models >2GB like E4B, 7B)
  - `WebStorageMode.none`: No caching (ephemeral mode for testing)

**Example:**
```dart
FlutterGemma.initialize(
  huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN'),
  maxDownloadRetries: 10,
  webStorageMode: WebStorageMode.streaming,  // For large models (>2GB)
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
- ✅ **Gemma3n** (E2B, E4B) - `google/` repos are gated
- ✅ **Gemma 3 1B** - `litert-community/` requires access
- ✅ **Gemma 3 270M** - `litert-community/` requires access
- ✅ **EmbeddingGemma** - `litert-community/` requires access

**Public models (no auth needed):**
- ❌ **DeepSeek, Qwen3, Qwen 2.5, SmolLM, Phi-4, FastVLM** - Public repos

**Get your token:** https://huggingface.co/settings/tokens

**Grant access to gated repos:** Visit model page → "Request Access" button

## Model Sources 📦

Flutter Gemma supports multiple model sources with different capabilities:

| Source Type | Platform | Progress | Resume | Authentication | Use Case |
|-------------|----------|----------|--------|----------------|----------|
| **NetworkSource** | All | ✅ Detailed | ⚠️ Server-dependent | ✅ Supported | HuggingFace, CDNs, private servers |
| **AssetSource** | All | ⚠️ End only | ❌ No | ❌ N/A | Models bundled in app assets |
| **BundledSource** | All | ⚠️ End only | ❌ No | ❌ N/A | Native platform resources |
| **FileSource** | Mobile only | ⚠️ End only | ❌ No | ❌ N/A | User-selected files (file picker) |

### NetworkSource - Internet Downloads

Downloads models from HTTP/HTTPS URLs with full progress tracking and authentication.

**Features:**
- ✅ Progress tracking (0-100%)
- ⚠️ Resume after interruption (server-dependent, not supported by HuggingFace CDN)
- ✅ HuggingFace authentication
- ✅ Smart retry logic with exponential backoff
- ✅ Background downloads on mobile
- ✅ Cancellable downloads with CancelToken
- ✅ **Android foreground service** for large downloads (>500MB)

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

**Android Foreground Service (Large Downloads):**

Android has a 9-minute background execution limit. For large models (>500MB), you can use foreground service mode which shows a notification but bypasses this timeout:

```dart
// Auto-detect based on file size (>500MB = foreground) - DEFAULT
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url)  // foreground: null (auto-detect)
  .install();

// Force foreground mode (always show notification)
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url, foreground: true)
  .install();

// Force background mode (may fail for large files)
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url, foreground: false)
  .install();
```

**Foreground Parameter:**
- `null` (default): Auto-detect based on file size. Files >500MB use foreground service.
- `true`: Always use foreground service (shows notification, no timeout)
- `false`: Never use foreground service (subject to 9-minute timeout)

**Note:** iOS uses native URLSession which handles long downloads automatically - no foreground service needed.

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
- SmolLM 135M: ~135MB
- Gemma 3 270M: ~300MB
- Qwen3 0.6B: ~586MB
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

The pre-Modern stream-based API (`FlutterGemmaPlugin.instance.modelManager`, `installModelFromAsset`, `downloadModelFromNetworkWithProgress`, etc.) is still supported but deprecated. New projects should use the [Modern API](#quick-start) above.

📚 **Full Legacy API reference:** [docs/LEGACY_API.md](docs/LEGACY_API.md)

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
    // Model wants to call a function (Gemma3n, DeepSeek, Qwen2.5)
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

### Platform Support

| Model | Size | Desktop | Mobile | Web |
|-------|------|:-------:|:------:|:---:|
| [Gemma 4 E2B](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) | 2.4GB | ✅ | ✅ | ✅ |
| [Gemma 4 E4B](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) | 4.3GB | ✅ | ✅ | ✅ |
| [Gemma3n E2B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) | 3.1GB | ✅ | ✅ | ✅ |
| [Gemma3n E4B](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview) | 6.5GB | ✅ | ✅ | ✅ |
| [FastVLM 0.5B](https://huggingface.co/litert-community/FastVLM-0.5B) | 0.5GB | ✅ | ❌ | ❌ |
| [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT) | 0.5GB | ✅ | ✅ | ✅ |
| [Gemma 3 270M](https://huggingface.co/litert-community/gemma-3-270m-it) | 0.3GB | ✅ | ✅ | ✅ |
| [FunctionGemma 270M](https://huggingface.co/sasha-denisov/function-gemma-270M-it) | 284MB | ✅ | ✅ | ❌ |
| [Qwen3 0.6B](https://huggingface.co/litert-community/Qwen3-0.6B) | 586MB | ✅ | ✅ | ✅ |
| [Qwen 2.5 1.5B](https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct) | 1.6GB | ✅ | ✅ | ❌ |
| [Qwen 2.5 0.5B](https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct) | 0.5GB | ❌ | ✅ | ❌ |
| [SmolLM 135M](https://huggingface.co/litert-community/SmolLM-135M-Instruct) | 135MB | ❌ | ✅ | ❌ |
| [Phi-4 Mini](https://huggingface.co/litert-community/Phi-4-mini-instruct) | 3.9GB | ✅ | ✅ | ✅ |
| [DeepSeek R1](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B) | 1.7GB | ❌ | ✅ | ❌ |

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
- **Gemma 4** (E2B, E4B) - Full function calling support
- **Gemma3n** (E2B, E4B) - Full function calling support
- **Gemma 3 1B** - Function calling support
- **FunctionGemma 270M** - Google's specialized function calling model
- **DeepSeek R1** - Function calling + thinking mode support
- **Qwen** models (0.5B, 0.6B, 1.5B) - Full function calling support
- **Phi-4 Mini** - Advanced reasoning with function calling support

### ❌ Models WITHOUT Function Calling Support
- **Gemma 3 270M** - Text generation only
- **SmolLM 135M** - Text generation only
- **FastVLM 0.5B** - Vision model, no function calling

**Important Notes:**
- When using unsupported models with tools, the plugin will log a warning and ignore the tools
- Models will work normally for text generation even if function calling is not supported
- Check the `supportsFunctionCalls` property in your model configuration

## Platform Support Details 🌐

### Feature Comparison

| Feature | Android | iOS | Web | Desktop | Notes |
|---------|---------|-----|-----|---------|-------|
| **Text Generation** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | All models supported |
| **Image Input (Multimodal)** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Broken (#684) | macOS: model hallucinates |
| **Audio Input** | ✅ Full | ✅ Full | ❌ Not supported | ✅ Full | Gemma3n E2B/E4B |
| **Function Calling** | ✅ Full | ✅ Full | ✅ Full | ❌ Not supported | LiteRT-LM limitation |
| **Thinking Mode** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | DeepSeek & Gemma 4 |
| **Stop Generation** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | Cancel mid-process |
| **GPU Acceleration** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Partial | macOS GPU broken |
| **NPU Acceleration** | ✅ Full | ❌ Not supported | ❌ Not supported | ❌ Not supported | Android only (.litertlm) |
| **CPU Backend** | ✅ Full | ✅ Full | ❌ Not supported | ✅ Full | MediaPipe limitation |
| **Streaming Responses** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | Real-time generation |
| **LoRA Support** | ✅ Full | ✅ Full | ✅ Full | ❌ Not supported | LiteRT-LM limitation |
| **Text Embeddings** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | EmbeddingGemma, Gecko |
| **VectorStore (RAG)** | ✅ SQLite | ✅ SQLite | ✅ SQLite WASM | ✅ SQLite | Semantic search, RAG |
| **File Downloads** | ✅ Background | ✅ Background | ✅ In-memory | ✅ Background | Platform-specific |
| **Asset Loading** | ✅ Full | ✅ Full | ✅ Full | ❌ Not supported | Flutter assets N/A |
| **Bundled Resources** | ✅ Full | ✅ Full | ✅ Full | ❌ Not supported | Native bundles only |
| **External Files (FileSource)** | ✅ Full | ✅ Full | ❌ Not supported | ✅ Full | No local FS on web |

### Web Platform Specifics

#### Authentication
- **Required for gated models:** Gemma3n, Gemma 3 1B/270M, EmbeddingGemma
- **Configuration:** Use `FlutterGemma.initialize(huggingFaceToken: '...')` or pass token per-download
- **Storage:** Tokens stored in browser memory (not localStorage)

#### File Handling
- **Downloads:** Creates blob URLs in browser memory (no actual files)
- **Storage:** IndexedDB via `WebFileSystemService`
- **FileSource:** Only works with HTTP/HTTPS URLs or `assets/` paths
- **Local file paths:** ❌ Not supported (browser security restriction)

#### Web Storage Modes (v0.12.1+)

**Three Storage Modes:**

**1. Cache API Mode (default, `WebStorageMode.cacheApi`):**
- Uses browser Cache API with Blob URLs
- Models persist across browser restarts
- Best for models <2GB

**2. Streaming Mode (`WebStorageMode.streaming`):**
- Uses OPFS with ReadableStream
- Bypasses browser 2GB ArrayBuffer limit
- Required for large models (E4B 4GB+, 7B, 27B)
- Requires Chrome 86+, Edge 86+, Safari 15.2+

**3. Ephemeral Mode (`WebStorageMode.none`):**
- Models stored in memory only
- Cleared when browser closes
- For testing/demos

```dart
// Default: Cache API for small models
FlutterGemma.initialize(webStorageMode: WebStorageMode.cacheApi);

// Streaming for large models (>2GB)
FlutterGemma.initialize(webStorageMode: WebStorageMode.streaming);

// Check if streaming is supported
final supported = await FlutterGemma.isStreamingSupported();
```

#### Backend Support
- **GPU only:** See [PreferredBackend Options](#preferredbackend-options) table above

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
  - Gemma3n E2B (3GB) - requires 6GB+ device RAM

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
- **Embedding models:** Supported via TensorFlowLiteC — no extra Podfile configuration needed

The full and complete example you can find in `example` folder

## **Important Considerations**

* **Model Size:** Larger models (such as 7b and 7b-it) might be too resource-intensive for on-device inference.
* **Function Calling Support:** Gemma3n and DeepSeek models support function calling. Other models will ignore tools and show a warning.
* **Thinking Mode:** Only DeepSeek models support thinking mode. Enable with `isThinking: true` and `modelType: ModelType.deepSeek`.
* **Multimodal Models:** Gemma3n models with vision support require more memory and are recommended for devices with 8GB+ RAM.
* **iOS Memory Requirements:** Large models require memory entitlements in `Runner.entitlements` and minimum iOS 16.0.
* **LoRA Weights:** They provide efficient customization without the need for full model retraining.
* **Development vs. Production:** For production apps, do not embed the model or LoRA weights within your assets. Instead, load them once and store them securely on the device or via a network drive.
* **Web Models:** Currently, Web support is available only for GPU backend models. Multimodal support is fully implemented.
* **Image Formats:** The plugin automatically handles common image formats (JPEG, PNG, etc.) when using `Message.withImage()`.

## **🛟 Troubleshooting**

**Multimodal Issues:**
- Ensure you're using a multimodal model (Gemma3n E2B/E4B)
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
// - <think>...</think> blocks (DeepSeek)
// - <|channel>thought\n...<channel|> blocks (Gemma 4 E2B/E4B)
// - Extra whitespace and formatting
```

This is automatically handled by the chat API, but can be useful for custom inference implementations.

## ☕ Support the Project

If you find **Flutter Gemma** useful and want to support its development, consider buying me a coffee! Your support helps me:

- 🔧 Maintain and improve the plugin
- 📚 Keep documentation up-to-date
- 🐛 Fix bugs and resolve issues faster
- ✨ Add new features and model support
- 🧪 Test on more devices and platforms

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/flutter_gemma)

Every contribution, no matter how small, makes a difference. Thank you for your support! 💙