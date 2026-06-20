# genkit_flutter_gemma

Genkit Dart plugin for [flutter_gemma](https://pub.dev/packages/flutter_gemma) — local on-device AI inference via Google Gemma and other supported models.

<p align="center">
  <img src="https://raw.githubusercontent.com/DenisovAV/flutter_gemma/main/packages/genkit_flutter_gemma/assets/cover.jpeg" alt="genkit_flutter_gemma_cover">
</p>

## Features

- Wraps `flutter_gemma` as a Genkit model provider
- Supports text generation (blocking and streaming)
- Embeddings via `FlutterGemmaEmbedder`
- Multimodal input (images, audio) — supports `data:` URIs, `file://` paths, and `http(s)://` URLs
- Function calling / tool use with `toolChoice` control (`auto`, `required`, `none`)
- Parallel tool calls — multiple function calls in a single model response
- Thinking mode (Gemma 4, DeepSeek)
- Generation latency tracking via `latencyMs` in responses
- Configurable via `@Schema()`-annotated options

## Supported Model Architectures

| Architecture | ModelType | Notes |
|---|---|---|
| Gemma 3 / Gemma 4 IT | `ModelType.gemmaIt` | Default; multimodal (image, audio); thinking mode for Gemma 4 |
| DeepSeek | `ModelType.deepSeek` | Thinking mode |
| Qwen / Qwen3 | `ModelType.qwen` / `ModelType.qwen3` | Qwen3 supports thinking mode |
| Llama | `ModelType.llama` | |
| Phi | `ModelType.phi` | Phi-4 |
| FunctionGemma | `ModelType.functionGemma` | Specialized function calling |

## Setup

`genkit_flutter_gemma` depends only on the **core** `flutter_gemma` package — it
stays engine-agnostic. As of flutter_gemma 1.0.0 the inference engines and
embedding backends ship as **separate, opt-in packages**, and the core
registers none of them by default. Your app must add the packages it needs and
register their providers in `FlutterGemma.initialize()`.

| Package | Provider | Add it when you use… |
|---|---|---|
| `flutter_gemma_litertlm` | `LiteRtLmEngine()` | `.litertlm` models (Gemma 4, desktop) |
| `flutter_gemma_mediapipe` | `MediaPipeEngine()` | `.task` / `.bin` models (Gemma 3, mobile/web) |
| `flutter_gemma_embeddings` | `LiteRtEmbeddingBackend()` | text embeddings (EmbeddingGemma) |

```yaml
# pubspec.yaml (your app)
dependencies:
  genkit_flutter_gemma: ^0.4.0
  flutter_gemma: ^1.0.0
  flutter_gemma_litertlm: ^1.0.0   # only the engines/backends you actually use
  flutter_gemma_mediapipe: ^1.0.0
  flutter_gemma_embeddings: ^1.0.0
```

```dart
// main() — register the providers from the packages you added above.
await FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()],
);
```

> If you skip registration, the first `installModel` / `getActiveModel` throws a
> `StateError` telling you to add the engine package.

## Quick Start

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
// Engines/backends are opt-in (see Setup) — register the ones you need.
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_flutter_gemma/genkit_flutter_gemma.dart';

// Initialize and install model (host app responsibility)
await FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()],
);
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
    .fromAsset('assets/gemma-3-1b-it-int4.task')
    .install();

// Create Genkit with plugin
final ai = Genkit(plugins: [
  GenkitFlutterGemmaPlugin(
    models: [
      FlutterGemmaModelConfig(
        name: 'gemma-3-nano',
        modelType: ModelType.gemmaIt,
      ),
    ],
    embedders: [
      FlutterGemmaEmbedderConfig(name: 'embedding-gemma-300m'),
    ],
  ),
]);

// Generate
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Hello!',
);
print(response.text);
```

## Configuration

Pass `FlutterGemmaModelOptions` to customize inference:

```dart
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Hello!',
  config: FlutterGemmaModelOptions(
    maxTokens: 2048,
    temperature: 0.5,
    topK: 40,
    supportImage: true,
  ),
);
```

| Option | Type | Default | Description |
|---|---|---|---|
| `maxTokens` | `int?` | 1024 | Maximum tokens to generate |
| `temperature` | `double?` | 0.8 | Sampling temperature |
| `topK` | `int?` | 1 | Top-K sampling |
| `topP` | `double?` | null | Top-P (nucleus) sampling |
| `supportImage` | `bool?` | false | Enable multimodal image input |
| `supportAudio` | `bool?` | false | Enable audio input (Gemma 3n) |
| `isThinking` | `bool?` | false | Enable thinking mode (Gemma 4, DeepSeek) |
| `randomSeed` | `int?` | 1 | Random seed for deterministic output |
| `toolChoice` | `String?` | `'auto'` | Tool calling mode: `'auto'`, `'required'`, `'none'` |
| `systemInstruction` | `String?` | null | System-level instruction (overrides system-role messages) |
| `maxFunctionBufferLength` | `int?` | null | Max token buffer for streaming tool-call arguments (increase for large payloads) |
| `enableSpeculativeDecoding` | `bool?` | null | MTP speculative decoding for Gemma 4 E2B/E4B (null = model default, true/false = force on/off) |

## Streaming

```dart
final stream = ai.generateStream(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Write a story.',
);

await for (final chunk in stream) {
  stdout.write(chunk.text);
}
```

## Tool Use

```dart
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'What is the weather in Paris?',
  tools: [weatherTool],
);
```

## Embeddings

```dart
// Install embedding model + tokenizer (host app responsibility)
await FlutterGemma.installEmbedder()
    .modelFromNetwork('https://huggingface.co/.../embeddinggemma-300M.tflite')
    .tokenizerFromNetwork('https://huggingface.co/.../sentencepiece.model')
    .install();

// Generate embeddings
final embeddings = await ai.embed(
  embedder: flutterGemma.embedder('embedding-gemma-300m'),
  documents: [
    DocumentData(content: [TextPart(text: 'Flutter is a UI toolkit.')]),
    DocumentData(content: [TextPart(text: 'Dart is a programming language.')]),
  ],
);

for (final embedding in embeddings) {
  print('Vector (${embedding.embedding.length} dims): '
      '${embedding.embedding.take(5)}...');
}
```

## Known Limitations

- **Engine registration**: With flutter_gemma 1.0.0+ the inference engines and embedding backends are opt-in. The host app must add the relevant packages (`flutter_gemma_litertlm` for `.litertlm`, `flutter_gemma_mediapipe` for `.task`/`.bin`, `flutter_gemma_embeddings` for embeddings) and register their providers in `FlutterGemma.initialize()` before using the plugin.
- **Model installation**: The plugin does NOT manage model installation. The host app must install models via `FlutterGemma.installModel()` and embedders via `FlutterGemma.installEmbedder()` before using the plugin.
- **System role**: System messages are passed natively via `createChat(systemInstruction:)` (requires flutter_gemma ^0.13.0). Only text content is supported in system messages.
- **Thinking mode**: Requires `.litertlm` model format. Supported on Android, iOS, and Desktop. Not supported on Web.
