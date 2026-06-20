---
title: Genkit
description: Use flutter_gemma through Genkit — on-device model/embedder provider and hybrid on-device/cloud routing.
image: https://fluttergemma.dev/images/og-image.png
---

[Genkit](https://pub.dev/packages/genkit) is Google's open-source framework
for building AI-powered features in Dart and Flutter. Two packages bridge
flutter_gemma into Genkit — one wraps the on-device runtime as a standard
Genkit provider, the other adds hybrid routing so you can combine on-device
and cloud models behind a single `ai.generate` call.

## genkit_flutter_gemma

Wraps flutter_gemma as a Genkit model and embedder provider. Once registered,
every Genkit feature (streaming, tool use, embeddings, prompt templates) works
with the on-device model exactly as it would with any cloud provider.

### Add to pubspec.yaml

```yaml
dependencies:
  genkit_flutter_gemma: ^0.4.0
  flutter_gemma: ^1.0.0
  # Add the inference engine(s) you need:
  flutter_gemma_litertlm: ^1.0.0   # .litertlm models (mobile + desktop)
  flutter_gemma_mediapipe: ^1.0.0  # .task / .bin models (mobile + web)
  # Optional — for embeddings:
  flutter_gemma_embeddings: ^1.0.0
```

### Setup

Register the engine packages in `FlutterGemma.initialize()`, install your
model, then create a `Genkit` instance with the plugin:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_flutter_gemma/genkit_flutter_gemma.dart';

// 1. Register providers (call once in main).
await FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()],
);

// 2. Install the model (host app responsibility).
await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
    .fromAsset('assets/gemma-3-1b-it-int4.task')
    .install();

// 3. Create a Genkit instance with the plugin.
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
```

### Generate text

```dart
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Hello!',
);
print(response.text);
```

### Stream text

```dart
final stream = ai.generateStream(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Write a short story.',
);

await for (final chunk in stream) {
  stdout.write(chunk.text);
}
```

### Embeddings

```dart
final embeddings = await ai.embed(
  embedder: flutterGemma.embedder('embedding-gemma-300m'),
  documents: [
    DocumentData(content: [TextPart(text: 'Flutter is a UI toolkit.')]),
  ],
);
```

### Configuration options

Pass `FlutterGemmaModelOptions` to tune inference:

```dart
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Hello!',
  config: FlutterGemmaModelOptions(
    maxTokens: 2048,
    temperature: 0.5,
    topK: 40,
    isThinking: false,
  ),
);
```

<Info>
The plugin does **not** manage model installation. Call
`FlutterGemma.installModel()` (and `FlutterGemma.installEmbedder()` for
embeddings) before using the plugin. See [Getting Started](/docs/getting-started).
</Info>

## genkit_hybrid

Provider-agnostic hybrid routing for Genkit. Combine any two existing Genkit
models — on-device, cloud, or anything else — behind one routing policy. The
result is an ordinary `Model`, so your app still calls a single `ai.generate`.

`genkit_hybrid` depends only on `genkit` — it has no dependency on
flutter_gemma and works with **any** pair of Genkit models.

### Add to pubspec.yaml

```yaml
dependencies:
  genkit_hybrid: ^0.1.0
  genkit: any
```

### Basic usage

```dart
import 'package:genkit_hybrid/genkit_hybrid.dart';

// onDeviceModel and cloudModel are ordinary Genkit Models you already have.
final smart = hybridModelOnDeviceCloud(
  onDevice: onDeviceModel,
  cloud: cloudModel,
  strategy: ConnectivityStrategy(
    isOnline: () => connectivity.isOnline,
    online: kCloud,
    offline: kOnDevice,
  ),
);

final response = await ai.generate(model: smart, prompt: 'Hello!');
```

### Routing strategies

| Strategy | Routes on |
|---|---|
| `PreRoutingStrategy(fn)` | your own function (privacy, cost, user tier…) |
| `FallbackStrategy(order)` | fixed priority order — `kOnDevice` first or `kCloud` first |
| `ConnectivityStrategy(...)` | network availability |
| `InputSizeStrategy(...)` | prompt length |
| `FirstMatch([...])` | first child strategy that decides (chain of rules) |
| `WithFallback(s, fallbackOrder: order)` | any strategy's pick + a guaranteed fallback tail |

### Prefer on-device, fall back to cloud

```dart
hybridModelOnDeviceCloud(
  onDevice: onDeviceModel,
  cloud: cloudModel,
  strategy: FallbackStrategy([kOnDevice, kCloud]),
);
```

### Chain multiple rules

```dart
hybridModelOnDeviceCloud(
  onDevice: onDeviceModel,
  cloud: cloudModel,
  strategy: WithFallback(
    FirstMatch([
      PreRoutingStrategy((c) => userOptedOutOfCloud ? kOnDevice : ''),
      ConnectivityStrategy(
        isOnline: () => net.isOnline,
        online: kCloud,
        offline: kOnDevice,
      ),
    ]),
    fallbackOrder: [kOnDevice],
  ),
);
```

### Streaming and fallback

Fallback during streaming happens **only before the first token**. If a branch
fails before emitting any output, the next branch is tried transparently. Once
the first token has streamed, a later failure propagates as an error — a
partially delivered response cannot be silently re-routed.

<Info>
`genkit_hybrid` works with **any** Genkit models, not just flutter_gemma. You
can combine `gemini-1.5-flash` (cloud) with a local Ollama model, or any other
pair that Genkit supports.
</Info>
