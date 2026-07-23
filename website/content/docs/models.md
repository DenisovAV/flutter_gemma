---
title: Models
description: Supported models, file formats, capabilities, ModelType reference, and download URLs.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma supports Gemma 4, Gemma3n, FastVLM, Qwen2-VL, SmolVLM2,
LLaVA-OneVision, Gemma 3, FunctionGemma, Qwen3, Qwen 2.5, Phi-4 (incl. Phi-4 Mini
Reasoning), DeepSeek R1, SmolLM, SmolLM3 and more. Desktop platforms (macOS,
Windows, Linux) require the `.litertlm` model format.

## Model file types

Flutter Gemma supports different model file formats, grouped into **two types**
based on how chat templates are handled.

### Type 1: MediaPipe-managed templates

- **`.task` files:** MediaPipe-optimized format for mobile (Android/iOS).
- **`.litertlm` files:** LiteRT-LM format for Android, iOS, and Desktop.

Both formats have **identical behavior** — chat templates are handled internally.

### Type 2: Manual template formatting

- **`.bin` files:** standard binary format.
- **`.tflite` files:** LiteRT format (formerly TensorFlow Lite).

Both formats require **manual chat template formatting** in your code.

### Type 3: System OS models (no file)

- **Gemini Nano** (Android, via AICore / ML Kit GenAI) and **Apple Foundation
  Models** (iOS 26+/macOS) are **built into the OS** — there is no model file to
  bundle or download; the OS owns the weights.
- Add [`flutter_gemma_builtin_ai`](/docs/packages) and register `BuiltInAiEngine()`.
  Use `ModelFileType.builtIn` (the engine's `BuiltInAiModels.geminiNano` /
  `.appleFoundationModels` specs set it for you). Chat templates are handled by
  the OS runtime. Availability is device-gated — probe with `BuiltInAi.availability()`
  / `BuiltInAi.ensureReady()` before use (Gemini Nano needs Pixel 9+/Galaxy S25+;
  Apple FM needs Apple Intelligence enabled on iPhone 15 Pro+/M-series).

<Info>
The plugin automatically detects the file extension and applies the appropriate
formatting. When specifying `ModelFileType` in code: use `ModelFileType.task` for
`.task` and `.litertlm` files (same behavior), and `ModelFileType.binary` for
`.bin` and `.tflite` files (same behavior).
</Info>

### Format by platform

| Format | Android | iOS | Web | Desktop | Use Case |
|---|:---:|:---:|:---:|:---:|---|
| `.task` | ✅ | ✅ | ✅ | ❌ | Older models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) |
| `.litertlm` | ✅ | ✅ ¹ | ❌ | ✅ | Newer models (Gemma 4, Qwen3, FastVLM + desktop for all) |
| `-web.task` | ❌ | ❌ | ✅ | ❌ | Web-specific builds (e.g. Gemma 4, Gemma3n) |
| `.bin` | ✅ | ✅ | ✅ | ❌ | Manual chat template formatting required |
| `.tflite` | ✅ | ✅ | ✅ | ✅ | Embeddings only (EmbeddingGemma, Gecko) |

¹ iOS `.litertlm` runs on the FFI engine — vision and audio supported on physical
devices. The Simulator stays CPU-only because Metal sim has a 256 MB
single-allocation cap.

## Model capabilities

| Model Family | Best For | Function Calling | Thinking Mode | Vision | Languages | Size |
|---|---|:---:|:---:|:---:|---|---|
| **Gemma 4 E2B** | Next-gen multimodal chat — text, image, audio | ✅ | ✅ | ✅ | Multilingual | 2.4GB |
| **Gemma 4 E4B** | Next-gen multimodal chat — text, image, audio | ✅ | ✅ | ✅ | Multilingual | 4.3GB |
| **Gemma3n** | On-device multimodal chat and image analysis | ✅ | ❌ | ✅ | Multilingual | 3-6GB |
| **FastVLM 0.5B** | Fast vision-language inference | ❌ | ❌ | ✅ | Multilingual | 0.5GB |
| **Qwen2-VL 2B** | Vision-language chat (image + text) | ❌ | ❌ | ✅ | Multilingual | 1.8GB |
| **SmolVLM2 500M** | Compact vision-language model | ❌ | ❌ | ✅ | Multilingual | 0.36GB |
| **LLaVA-OneVision 0.5B** | Compact vision-language model | ❌ | ❌ | ✅ | Multilingual | 0.83GB |
| **Phi-4 Mini** | Advanced reasoning and instruction following | ✅ | ❌ | ❌ | Multilingual | 3.9GB |
| **Phi-4 Mini Reasoning** | Step-by-step reasoning | ❌ | ✅ | ❌ | Multilingual | 2.8GB |
| **DeepSeek R1** | High-performance reasoning and code generation | ✅ | ✅ | ❌ | Multilingual | 1.7GB |
| **Qwen3 0.6B** | Compact multilingual chat with function calling | ✅ | ✅ | ❌ | Multilingual | 586MB |
| **Qwen 2.5** | Strong multilingual chat and instruction following | ✅ | ❌ | ❌ | Multilingual | 0.5-1.6GB |
| **Gemma 3 1B** | Balanced and efficient text generation | ✅ | ❌ | ❌ | Multilingual | 0.5GB |
| **Gemma 3 270M** | Ideal for fine-tuning (LoRA) for specific tasks | ❌ | ❌ | ❌ | Multilingual | 0.3GB |
| **FunctionGemma 270M** | Specialized for function calling on-device | ✅ | ❌ | ❌ | Multilingual | 284MB |
| **SmolLM 135M** | Ultra-compact, resource-constrained devices | ❌ | ❌ | ❌ | English | 135MB |
| **SmolLM3 3B** | Multilingual small LLM with reasoning mode | ❌ | ✅ | ❌ | Multilingual | 2.0GB |
| **TranslateGemma 4B** † | Single-shot 55-language translation | ❌ | ❌ | ❌ | 55 languages | 2-4GB |

<Warning>
† **TranslateGemma is CPU-only for now.** Google hasn't released a
mobile/desktop `.litertlm` bundle
([HF discussion #5](https://huggingface.co/google/translategemma-4b-it/discussions/5)).
The community-converted bundle from
[`barakplasma/translategemma-4b-it-android-task-quantized`](https://huggingface.co/barakplasma/translategemma-4b-it-android-task-quantized)
keeps `EMBEDDING_LOOKUP` weights in float32 for MediaPipe `.task` compatibility,
which crashes the LiteRT GPU partitioner on Metal/WebGPU across all platforms
(tracked at [LiteRT-LM#1748](https://github.com/google-ai-edge/LiteRT-LM/issues/1748)).
Until Google ships the `litert-lm` quantization CLI, translation runs on CPU only
(≈90 s prefill on a 4 B int4 bundle on M-series Macs).
</Warning>

## ModelType reference

When installing models, specify the correct `ModelType`:

| Model Family | ModelType | Examples |
|---|---|---|
| **Gemma 4** | `ModelType.gemma4` | Gemma 4 E2B, Gemma 4 E4B (native function-call tokens) |
| **Gemma 3 / Gemma3n** | `ModelType.gemmaIt` | Gemma 3 1B, Gemma 3 270M, Gemma3n E2B/E4B |
| **DeepSeek** | `ModelType.deepSeek` | DeepSeek R1 |
| **Qwen 2.5** | `ModelType.qwen` | Qwen 2.5 1.5B, Qwen 2.5 0.5B |
| **Qwen 3** | `ModelType.qwen3` | Qwen3 0.6B |
| **FunctionGemma** | `ModelType.functionGemma` | FunctionGemma 270M IT |
| **Phi** | `ModelType.phi` | Phi-4 Mini |
| **General** | `ModelType.general` | FastVLM 0.5B, SmolLM 135M, SmolLM3 3B, Phi-4 Mini Reasoning, Qwen2-VL 2B, SmolVLM2 500M, LLaVA-OneVision 0.5B |

<Info>
Gemma 4 uses `ModelType.gemma4` so its native tool-call tokens are routed through
the LiteRT-LM SDK's chat-template path. For Gemma 3 and earlier, keep
`ModelType.gemmaIt`.
</Info>

**Usage example:**

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

## Supported models & platforms

| Model | Size | Desktop | Mobile | Web |
|---|---|:---:|:---:|:---:|
| [Gemma 4 E2B](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) | 2.4GB | ✅ | ✅ | ✅ |
| [Gemma 4 E4B](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) | 4.3GB | ✅ | ✅ | ✅ |
| [Gemma3n E2B](https://huggingface.co/google/gemma-3n-E2B-it-litert-preview) | 3.1GB | ✅ | ✅ | ✅ |
| [Gemma3n E4B](https://huggingface.co/google/gemma-3n-E4B-it-litert-preview) | 6.5GB | ✅ | ✅ | ✅ |
| [FastVLM 0.5B](https://huggingface.co/litert-community/FastVLM-0.5B) | 0.5GB | ✅ | ❌ | ❌ |
| [Qwen2-VL 2B](https://huggingface.co/litert-community/Qwen2-VL-2B) | 1.8GB | ✅ | ✅ | ❌ |
| [SmolVLM2 500M](https://huggingface.co/litert-community/SmolVLM2-500M) | 0.36GB | ✅ | ✅ | ❌ |
| [LLaVA-OneVision 0.5B](https://huggingface.co/litert-community/LLaVA-OneVision-0.5B) | 0.83GB | ✅ | ✅ | ❌ |
| [Gemma-3 1B](https://huggingface.co/litert-community/Gemma3-1B-IT) | 0.5GB | ✅ | ✅ | ✅ |
| [Gemma 3 270M](https://huggingface.co/litert-community/gemma-3-270m-it) | 0.3GB | ✅ | ✅ | ✅ |
| [FunctionGemma 270M](https://huggingface.co/sasha-denisov/function-gemma-270M-it) | 284MB | ✅ | ✅ | ❌ |
| [Qwen3 0.6B](https://huggingface.co/litert-community/Qwen3-0.6B) | 586MB | ✅ | ✅ | ✅ |
| [Qwen 2.5 1.5B](https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct) | 1.6GB | ✅ | ✅ | ❌ |
| [Qwen 2.5 0.5B](https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct) | 0.5GB | ❌ | ✅ | ❌ |
| [SmolLM 135M](https://huggingface.co/litert-community/SmolLM-135M-Instruct) | 135MB | ❌ | ✅ | ❌ |
| [SmolLM3 3B](https://huggingface.co/litert-community/SmolLM3-3B) | 2.0GB | ✅ | ✅ | ❌ |
| [Phi-4 Mini](https://huggingface.co/litert-community/Phi-4-mini-instruct) | 3.9GB | ✅ | ✅ | ✅ |
| [Phi-4 Mini Reasoning](https://huggingface.co/litert-community/Phi-4-mini-reasoning) | 2.8GB | ✅ | ✅ | ❌ |
| [DeepSeek R1](https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B) | 1.7GB | ❌ | ✅ | ❌ |

## Installation sources

```dart
// Network — .litertlm is the cross-platform default (Android/iOS/Desktop).
// For mobile-only or web-only apps you can substitute a .task URL.
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork('https://example.com/model.litertlm', token: 'optional')
  .install();

// Flutter assets
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromAsset('assets/models/model.litertlm')
  .install();

// Native bundle
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromBundled('model.litertlm')
  .install();

// External file (native only)
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromFile('/path/to/model.litertlm')
  .install();
```

### Source capabilities

| Source Type | Platform | Progress | Resume | Authentication | Use Case |
|---|---|---|---|---|---|
| **NetworkSource** | All | ✅ Detailed | ⚠️ Server-dependent | ✅ Supported | HuggingFace, CDNs, private servers |
| **AssetSource** | All | ⚠️ End only | ❌ No | ❌ N/A | Models bundled in app assets |
| **BundledSource** | All | ⚠️ End only | ❌ No | ❌ N/A | Native platform resources |
| **FileSource** | Native (no Web) | ⚠️ End only | ❌ No | ❌ N/A | User-selected files (file picker) |

<Info>
Resume after interruption is server-dependent and **not supported by the
HuggingFace CDN** — flutter_gemma uses smart retry logic with exponential
backoff and automatic restart instead. See [Troubleshooting](/docs/troubleshooting).
</Info>

### Android foreground service (large downloads)

Android has a 9-minute background execution limit. For large models (>500MB) the
plugin auto-detects and uses a foreground service (shows a notification) to
bypass it:

```dart
// Auto-detect based on file size (>500MB = foreground) — DEFAULT
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url)  // foreground: null (auto-detect)
  .install();

// Force foreground mode
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url, foreground: true)
  .install();
```

iOS uses native URLSession which handles long downloads automatically — no
foreground service needed.

### Cancelling downloads

```dart
import 'package:flutter_gemma/core/model_management/cancel_token.dart';

final cancelToken = CancelToken();

final future = FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  .fromNetwork(url)
  .withCancelToken(cancelToken)
  .withProgress((progress) => print('Progress: $progress%'))
  .install();

// Cancel from elsewhere (e.g. user pressed a cancel button)
cancelToken.cancel('User cancelled download');

try {
  await future;
} catch (e) {
  if (CancelToken.isCancel(e)) {
    print('Download was cancelled by user');
  }
}
```

`CancelToken` cancels all files in multi-file downloads (e.g. embedding model +
tokenizer), works on mobile + web, and throws `DownloadCancelledException`.

## Text embedding models

All embedding models generate **768-dimensional vectors**. The numbers in names
(64/256/512/1024/2048) indicate **maximum input sequence length in tokens**, not
embedding dimension. See [Embeddings & RAG](/docs/embeddings-and-rag) for usage.

| Model | Parameters | Dimensions | Max Seq Length | Size | Auth Required |
|---|---|---|---|---|---|
| **[Gecko 64](https://huggingface.co/litert-community/Gecko-110m-en)** | 110M | 768D | 64 tokens | 110MB | ❌ |
| **[Gecko 256](https://huggingface.co/litert-community/Gecko-110m-en)** | 110M | 768D | 256 tokens | 114MB | ❌ |
| **[Gecko 512](https://huggingface.co/litert-community/Gecko-110m-en)** | 110M | 768D | 512 tokens | 116MB | ❌ |
| **[EmbeddingGemma 256](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 256 tokens | 179MB | ✅ |
| **[EmbeddingGemma 512](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 512 tokens | 179MB | ✅ |
| **[EmbeddingGemma 1024](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 1024 tokens | 183MB | ✅ |
| **[EmbeddingGemma 2048](https://huggingface.co/litert-community/embeddinggemma-300m)** | 300M | 768D | 2048 tokens | 196MB | ✅ |

**Performance (Android Pixel 8, GPU acceleration):**

- **Gecko 64**: ~109 ms/doc embedding, 130 ms search (fastest — 2.6× faster than EmbeddingGemma).
- **EmbeddingGemma 256**: ~286 ms/doc embedding, 342 ms search (more accurate — 300M vs 110M params).
