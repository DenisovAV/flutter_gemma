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

```
dependencies:
  genkit_flutter_gemma: ^0.6.0
  flutter_gemma: ^1.7.0
  # Add the inference engine(s) you need:
  flutter_gemma_litertlm: ^1.6.1   # .litertlm models (mobile + desktop) + LiteRtEmbeddingBackend
  flutter_gemma_mediapipe: ^1.0.5  # .task / .bin models (mobile + web)
  # Optional — for embeddings (needs a backend, e.g. flutter_gemma_litertlm above):
  flutter_gemma_embeddings: ^2.1.0
```

### Setup

Register the engine packages in `FlutterGemma.initialize()`, install your
model, then create a `Genkit` instance with the plugin:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_flutter_gemma/genkit_flutter_gemma.dart';

// 1. Register providers (call once in main).
await FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()], // flutter_gemma_litertlm
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
    supportImage: true,
    toolChoice: 'auto',             // tool calling mode: 'auto' / 'required' / 'none'
    // Optional per-component backend ('cpu'/'gpu'/'npu'):
    preferredBackend: 'gpu',        // text decoder
    preferredAudioBackend: 'gpu',   // audio encoder (~2x on Metal; defaults to CPU)
    // preferredVisionBackend defaults to CPU (Metal/WebGPU can't run its ops).
  ),
);
```

`toolChoice` maps to Genkit 0.15's native top-level `toolChoice`: `'auto'`
lets the model decide, `'required'` forces a tool call, `'none'` forbids one.

<Info>
The plugin does **not** manage model installation. Call
`FlutterGemma.installModel()` (and `FlutterGemma.installEmbedder()` for
embeddings) before using the plugin. See [Getting Started](/docs/getting-started).
</Info>

### Structured (JSON) output

The plugin advertises `output: ['text', 'json']`. On-device Gemma has no native
schema-constrained decoder, so Genkit's instruction-injection fallback drives
JSON output — the plugin returns raw model text and Genkit's `extractJson`
populates `response.output`. Pass an `outputSchema` and read the parsed object:

```dart
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Give me a pancake recipe.',
  outputSchema: Recipe.$schema, // any @Schema()-annotated type
);

final Recipe? recipe = response.output;
```

### Context-window trimming

On-device models run with a fixed, small context window (`maxTokens` — 1024 for
most `.litertlm` models). A long multi-turn chat overflows it and the native
runtime fails to allocate the KV cache mid-generation. `trimContext()` is a
middleware that drops the oldest **non-system** turns before each model call,
always keeping every system message and the most recent message:

```dart
final response = await ai.generate(
  model: flutterGemma.model('gemma-3-nano'),
  prompt: 'Continue our conversation…',
  messages: longHistory,
  use: [trimContext(maxInputTokens: 800)],
);
```

With no arguments the budget is derived from the request's `maxTokens` (the
model's context window) minus 256 tokens of response headroom.

## genkit_hybrid

Provider-agnostic hybrid routing for Genkit. Combine any two existing Genkit
models — on-device, cloud, or anything else — behind one routing policy. The
result is an ordinary `Model`, so your app still calls a single `ai.generate`.

`genkit_hybrid` depends only on `genkit` — it has no dependency on
flutter_gemma and works with **any** pair of Genkit models.

### Add to pubspec.yaml

```
dependencies:
  genkit_hybrid: ^0.2.1
  genkit: ^0.16.0
```

### Basic usage

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/genkit_hybrid.dart';

final ai = Genkit();

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

// A hybrid model is an ordinary Model — register it, then use it like any other.
ai.registry.register(smart);

final response = await ai.generate(model: smart, prompt: 'Hello!');
```

### Routing strategies

| Strategy | Routes on |
|---|---|
| `PreRoutingStrategy(fn)` | your own function (privacy, cost, user tier…) |
| `FallbackStrategy(order)` | fixed priority order — `kOnDevice` first or `kCloud` first |
| `ConnectivityStrategy(...)` | network availability |
| `InputSizeStrategy(...)` | prompt length |
| `CapabilityStrategy(supports: {...})` | the capabilities a request needs — vision / audio / tools / json — routing to branches that declare them |
| `CostStrategy(budgetAvailable:, premium:, cheap:)` | a budget signal — the premium branch while the budget holds, the cheap branch once it's spent |
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

### Route by required capabilities

`CapabilityStrategy` inspects what the request actually needs — an image or
audio part, tool definitions, or JSON output — and keeps only the branches that
declare those capabilities (or `[]` when none qualifies, so compose it with
`WithFallback`). Capabilities are declared explicitly per branch; nothing is
inferred from model metadata.

```dart
final smart = hybridModel(
  branches: {'onDevice': onDeviceModel, 'cloud': cloudModel},
  strategy: WithFallback(
    CapabilityStrategy(supports: {
      'onDevice': {},                                   // text only
      'cloud': {ModelCapability.vision, ModelCapability.tools},
    }),
    fallbackOrder: ['cloud'],
  ),
);
```

A plain-text request can use either branch; a request carrying an image or tool
definitions is routed to `cloud`, the only branch that declares those
capabilities.

### Budget-gate a paid branch

`CostStrategy` sends traffic to a premium branch only while an app-supplied
budget signal holds, and falls back to the cheap branch once it's spent. Your
app owns the accounting (running spend, a daily cap, a quota) and reduces it to
one `bool` — the package depends on no billing SDK.

```dart
hybridModel(
  branches: {'onDevice': onDeviceModel, 'cloud': cloudModel},
  strategy: CostStrategy(
    budgetAvailable: () => spend.today < dailyCap,
    premium: 'cloud',
    cheap: 'onDevice',
  ),
);
```

### Streaming and fallback

Fallback during streaming happens **only before the first token**. If a branch
fails before emitting any output, the next branch is tried transparently. Once
the first token has streamed, a later failure propagates as an error — a
partially delivered response cannot be silently re-routed.

### Escalate on a quality check with `cascadeModel`

`cascadeModel` is a `Model` (not a strategy): it runs branches in order and
escalates to the next one only when your `accept` predicate rejects the
response — "try the cheap on-device model; go to the cloud only if the answer
isn't good enough". `accept` is any check you like (a length or regex test, a
JSON-parses check) and may be async, e.g. an LLM-as-judge.

```dart
import 'package:genkit_hybrid/genkit_hybrid.dart';

final smart = cascadeModel(
  branches: {'onDevice': onDeviceModel, 'cloud': cloudModel},
  order: ['onDevice', 'cloud'],
  accept: (r) => r.text.trim().length > 20,
);

final response = await ai.generate(model: smart, prompt: 'Explain quantum tunnelling.');
```

> **`cascadeModel` is non-streaming in v1.** A quality verdict needs the whole
> response, and a streamed response can't be un-sent, so a streaming request is
> run non-streamed and the accepted response is emitted as a single final chunk.

<Info>
`genkit_hybrid` works with **any** Genkit models, not just flutter_gemma. You
can combine `gemini-1.5-flash` (cloud) with a local Ollama model, or any other
pair that Genkit supports.
</Info>
