author: Sasha Denisov
summary: Hybrid AI in Flutter with Genkit Dart — From Cloud to On-Device
id: hybrid-ai-flutter-genkit
categories: flutter, ai, gemma, genkit
environments: web, android, ios
status: Published

# Hybrid AI in Flutter: From Cloud to On-Device with Genkit Dart

## Overview
Duration: 5

### What you'll build

A Flutter chat application that progressively integrates AI capabilities using Genkit Dart:

1. **Cloud Chat** — Streaming responses from Gemini via `genkit_google_genai`
2. **Local Inference** — On-device AI with Gemma 3 1B via `genkit_flutter_gemma`
3. **Hybrid Strategy** — Cloud/local routing via `genkit_hybrid` (fallback, capability, cascade, budget)
4. **Smart Routing & Images** — multimodal input and image-aware policy routing
5. **Embeddings** — Semantic vector representations with EmbeddingGemma via Genkit
6. **RAG** — Context-augmented generation using a local tourist guide

### What you'll learn

- How to use the Genkit Dart framework for AI inference in Flutter
- How to route between cloud and on-device models using a single `Genkit`
  instance and `genkit_hybrid`'s routing strategies
- How to run AI models locally on device with `genkit_flutter_gemma`
- How to send images to a vision-capable model and gate routing on model
  capabilities
- How text embeddings work and how to build a RAG pipeline with Genkit

### What you'll need

- Flutter 3.47.2 (latest stable) installed
- A GEMINI_API_KEY from [aistudio.google.com](https://aistudio.google.com)
- A HuggingFace account (for model downloads)
- Android device/emulator, iOS simulator, or macOS
- ~1 GB free disk space (for the AI model)

### Architecture

```
┌──────────────────────────────────────────┐
│              Flutter App                 │
├──────────────────────────────────────────┤
│                AiEngine                  │
│          one Genkit, two plugins         │
├──────────────────┬───────────────────────┤
│  googleAI plugin │  GenkitFlutterGemma   │
│  gemini-3.7-flash│  Gemma 3 1B +         │
│     (kCloud)     │  EmbeddingGemma       │
│                  │    (kOnDevice)        │
└──────────────────┴───────────────────────┘
```

`genkit_hybrid` composes both branches into one routable `Model` —
`hybridModel()` / `cascadeModel()` — selected by a `PolicyMode`: cloud, local,
smart, cascade, budget.

The key insight: `AiEngine` builds a single `Genkit` instance with both
plugins registered, resolves the cloud and on-device models once, and hands
them to `genkit_hybrid` as a `Map<String, Model>` of branches. For each
`PolicyMode` it composes one branch map into an ordinary Genkit `Model` and
registers it on `ai.registry` — once, during `initialize()`. `engine.modelFor(policy)`
just returns that already-registered `Model`. The chat screen always calls
the same
`ai.generateStream(model: engine.modelFor(policy), messages: [...])`; only
which `Model` `modelFor` returns changes with the policy.

## Step 1: Starter Project
Duration: 5

### Clone the repository

```bash
git clone https://github.com/DenisovAV/workshop-genkit-flutter-hybrid-ai.git
cd workshop-genkit-flutter-hybrid-ai
git checkout step-00-starter
flutter pub get
```

### Explore the project

Open the project in your IDE. The starter includes:

- **`lib/main.dart`** — Simple app entry point, no async setup needed
- **`lib/screens/chat_screen.dart`** — Chat UI with TextField, ListView, send button
- **`lib/widgets/message_bubble.dart`** — Styled message bubbles (user right, AI left)
- **`lib/models/message_model.dart`** — Simple `ChatMessage` data class
- **`lib/services/ai_service.dart`** — Abstract `AIService` interface
- **`assets/tourist_data/`** — 10 JSON files with city descriptions (Paris, Tokyo, New York…)

### The AIService interface

All our AI services implement this contract:

```dart
abstract class AIService {
  Future<void> initialize();
  Stream<String> generateResponseStream(String prompt);
  Future<void> dispose();
}
```

`generateResponseStream` returns a `Stream<String>` — responses stream
token-by-token for a real-time chat feel.

### Run the starter

```bash
flutter run
```

You'll see the chat UI. Messages echo back with a placeholder. Let's replace
that with real AI next.

## Step 2: Cloud Chat with Genkit
Duration: 15

### Get your API key

Go to [aistudio.google.com](https://aistudio.google.com), sign in with your
Google account, and click **Get API key**. Copy the key — you'll use it with
`--dart-define`.

> No Firebase project, no CLI setup — just an API key.

> **Model choice**: this workshop pins `gemini-3.7-flash` — the older
> `gemini-2.5-flash` is being phased out.

### Update dependencies

In `pubspec.yaml`, uncomment the Genkit dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # Step 2: Cloud AI
  genkit: ^0.16.0
  genkit_google_genai: ^0.3.1
```

Run `flutter pub get`.

### Create CloudAIService

Create `lib/services/cloud_ai_service.dart`:

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'ai_service.dart';

// Pass at build time: flutter run --dart-define=GEMINI_API_KEY=AIza...
const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

class CloudAIService implements AIService {
  Genkit? _ai;

  @override
  Future<void> initialize() async {
    if (_apiKey.isEmpty) {
      throw StateError('GEMINI_API_KEY is not set. '
          'Run with --dart-define=GEMINI_API_KEY=your_key');
    }
    _ai = Genkit(plugins: [googleAI(apiKey: _apiKey)]);
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    final ai = _ai;
    if (ai == null) throw StateError('CloudAIService not initialized');

    final stream = ai.generateStream(
      model: googleAI.gemini('gemini-3.7-flash'),
      prompt: prompt,
    );

    await for (final chunk in stream) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Future<void> dispose() async => _ai = null;
}
```

### Wire it up in chat_screen.dart

Replace the echo stub:

```dart
import '../services/cloud_ai_service.dart';

// in _ChatScreenState:
late final CloudAIService _cloudService;

// in initState:
_cloudService = CloudAIService();
_initServices();

// in _initServices:
await _cloudService.initialize();

// in _sendMessage:
await for (final chunk in _cloudService.generateResponseStream(prompt)) {
  buffer.write(chunk);
  // ... update UI
}
```

### Run with your API key

```bash
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

Type "Tell me about Paris" — Gemini streams a response token by token.

> **What happened?** `Genkit(plugins: [googleAI(...)])` registered Gemini as a
> model provider. `ai.generateStream(model: googleAI.gemini('gemini-3.7-flash'), ...)`
> streams the response. The `Genkit` instance is the single point of contact
> for all AI operations.

## Step 3: Local Inference with genkit_flutter_gemma
Duration: 20

### Platform setup

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Required for local model download</string>
```
Minimum deployment target: iOS 16+.

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### Update dependencies

Add `genkit_flutter_gemma` and `flutter_gemma`:

```yaml
  # Step 3: On-device AI (LiteRT-LM engine)
  genkit_flutter_gemma: ^0.6.0
  flutter_gemma: ^1.7.0
  # flutter_gemma 1.x registers no engine by default — opt into LiteRT-LM
  # (.litertlm inference) here.
  flutter_gemma_litertlm: ^1.6.1
```

Run `flutter pub get`.

### Get a HuggingFace token

Go to [huggingface.co](https://huggingface.co), sign in, and create a
read-access token at **Settings → Access Tokens**.

### Create LocalAIService

Create `lib/services/local_ai_service.dart`:

```dart
import 'package:flutter/material.dart' show WidgetsFlutterBinding;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_flutter_gemma/genkit_flutter_gemma.dart';
import 'ai_service.dart';

// The on-device LLM installs straight from Hugging Face by repo + file.
const String _hfRepo = 'litert-community/Gemma3-1B-IT';
const String _hfModelFile = 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';
const String _hfToken = String.fromEnvironment('HF_TOKEN');
const String _modelName = 'gemma-3-1b-it';

class LocalAIService implements AIService {
  Genkit? _ai;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize({void Function(int)? onProgress}) async {
    WidgetsFlutterBinding.ensureInitialized();

    // flutter_gemma 1.x registers no engine by default — opt into LiteRT-LM.
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

    // Download the .litertlm model (skipped if already installed).
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    )
        .fromHuggingFace(
          _hfRepo,
          file: _hfModelFile,
          token: _hfToken.isEmpty ? null : _hfToken,
        )
        .withProgress((p) => onProgress?.call(p)) // p is int 0..100
        .install();

    // Register the model with Genkit
    _ai = Genkit(plugins: [
      GenkitFlutterGemmaPlugin(
        models: [
          FlutterGemmaModelConfig(
            name: _modelName,
            modelType: ModelType.gemmaIt,
            fileType: ModelFileType.litertlm,
          ),
        ],
      ),
    ]);

    _isInitialized = true;
  }

  @override
  Stream<String> generateResponseStream(String prompt) async* {
    final ai = _ai;
    if (ai == null) throw StateError('LocalAIService not initialized');

    final stream = ai.generateStream(
      model: flutterGemma.model(_modelName),
      prompt: prompt,
    );

    await for (final chunk in stream) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  Future<void> dispose() async {
    _ai = null;
    _isInitialized = false;
  }
}
```

### Run with HuggingFace token

```bash
flutter run --dart-define=GEMINI_API_KEY=your_key --dart-define=HF_TOKEN=hf_xxx
```

The first run downloads ~550 MB. Subsequent runs use the cached model.

> **Key insight**: Notice that `generateResponseStream` looks identical to
> `CloudAIService` — only the `model:` parameter changes. Genkit decouples
> _what model to use_ from _how to call it_.

```dart
// Cloud:
ai.generateStream(model: googleAI.gemini('gemini-3.7-flash'), prompt: prompt)

// Local:
ai.generateStream(model: flutterGemma.model('gemma-3-1b-it'), prompt: prompt)
```

Same API. Different backends.

> **Coming up**: In Step 4 we retire `CloudAIService` and `LocalAIService` as
> separate classes. A single `AiEngine` builds one `Genkit` with both plugins
> registered, and `genkit_hybrid` composes the two resolved models into one
> routable `Model` — the app still calls `ai.generateStream(model: ..., ...)`,
> it just gets that one `Model` from `AiEngine` instead of picking a service.

## Step 4: Hybrid Strategy
Duration: 15

### Update dependencies

Add `genkit_hybrid` — the routing layer. Everything else (the cloud + on-device
plugins and `flutter_gemma_litertlm`) is already in place from Steps 2–3:

```yaml
  # Hybrid on-device ↔ cloud routing
  genkit_hybrid: ^0.2.1
```

Run `flutter pub get`.

### Retire CloudAIService, LocalAIService

```bash
git rm lib/services/ai_service.dart lib/services/cloud_ai_service.dart \
       lib/services/local_ai_service.dart
```

They're replaced by one `AiEngine` that owns a single `Genkit` instance for
both plugins.

### Create AiEngine

Create `lib/services/ai_engine.dart`:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart' show GenkitPlugin;
import 'package:genkit_flutter_gemma/genkit_flutter_gemma.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_hybrid/genkit_hybrid.dart';

// The on-device LLM installs straight from Hugging Face by repo + file (the
// plugin applies the configured token to gated huggingface.co URLs).
const _hfRepo = 'litert-community/Gemma3-1B-IT';
const _hfModelFile = 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';
const _embeddingModelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
const _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

// Pass at build time: --dart-define=HF_TOKEN=hf_xxx --dart-define=GEMINI_API_KEY=AIza...
const _hfToken = String.fromEnvironment('HF_TOKEN');
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

const kLocalModel = 'gemma-3-1b-it';
const kCloudModel = 'gemini-3.7-flash';
const kEmbedder = 'embedding-gemma-300m';

/// The five routing policies the chat exposes. Each maps to one genkit_hybrid
/// construct (see [modelFor] / [strategyFor]).
enum PolicyMode { cloud, local, smart, cascade, budget }

/// Owns a single Genkit instance with both plugins (cloud + on-device),
/// resolves the two base models, and composes them via genkit_hybrid per the
/// selected [PolicyMode]. Replaces the old Cloud/Local/HybridAIService trio.
class AiEngine {
  Genkit? _ai;
  Model? _local;
  Model? _cloud;

  /// One composite [Model] per policy, built AND registered once by
  /// [_registerPolicyModels] — genkit reduces `generate(model: ...)` to the
  /// model's name and looks it up in the registry, so a freshly built,
  /// never-registered composite would fail every call with NOT_FOUND.
  final Map<PolicyMode, Model> _models = {};

  bool cloudReady = false;
  bool localReady = false;

  // CostStrategy demo signal: the app counts cloud calls against a small cap.
  int cloudCallsSpent = 0;
  int budgetCap = 3;
  bool get budgetAvailable => cloudCallsSpent < budgetCap;

  Genkit get ai {
    final ai = _ai;
    if (ai == null) throw StateError('AiEngine not initialized');
    return ai;
  }

  String get embedderName => kEmbedder;

  Future<void> initialize({
    void Function(int progress)? onProgress,
    // Skip the embedder download when RAG isn't needed for a given run.
    bool downloadEmbedder = true,
  }) async {
    // Declarative plugin config — always includes the on-device plugin (its
    // models/embedders are looked up by name later, independent of whether
    // the install below actually succeeds).
    final plugins = <GenkitPlugin>[
      if (_geminiApiKey.isNotEmpty) googleAI(apiKey: _geminiApiKey),
      GenkitFlutterGemmaPlugin(
        models: [
          FlutterGemmaModelConfig(
            name: kLocalModel,
            modelType: ModelType.gemmaIt,
            fileType: ModelFileType.litertlm,
          ),
        ],
        embedders: downloadEmbedder
            ? [FlutterGemmaEmbedderConfig(name: kEmbedder)]
            : const [],
      ),
    ];

    // Build Genkit BEFORE any on-device engine registration/install so `_ai`
    // (and `_resolve`, and the `ai` getter) are always available afterward —
    // the plugin list above is purely declarative, so cloud resolution below
    // needs no on-device engine and must not be taken down by a failure
    // registering/installing it.
    _ai = Genkit(plugins: plugins);

    // CLOUD: needs no install, so its readiness never depends on the local
    // LLM or the (optional) embedder below.
    if (_geminiApiKey.isNotEmpty) {
      try {
        _cloud = await _resolve(googleAI.gemini(kCloudModel));
        cloudReady = true;
      } catch (e) {
        debugPrint('⚠️ AiEngine: CLOUD backend unavailable — $e');
        cloudReady = false;
      }
    }

    // LOCAL: register the on-device engine, then install + resolve the LLM.
    // flutter_gemma 1.x registers no engines by default; that registration
    // lives inside this try/catch (not before Genkit is built above) so an
    // engine-init failure only suppresses localReady, never cloud.
    try {
      // Opt into LiteRT-LM (.litertlm inference) + its LiteRT embedding
      // backend.
      await FlutterGemma.initialize(
        inferenceEngines: [LiteRtLmEngine()],
        embeddingBackends: [LiteRtEmbeddingBackend()],
      );

      // fileType MUST be litertlm to match the LiteRT-LM engine registered
      // above.
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      )
          .fromHuggingFace(
            _hfRepo,
            file: _hfModelFile,
            token: _hfToken.isEmpty ? null : _hfToken,
          )
          .withProgress((p) => onProgress?.call(p)) // p is int 0..100
          .install();
      _local = await _resolve(flutterGemma.model(kLocalModel));
      localReady = true;
    } catch (e) {
      debugPrint('⚠️ AiEngine: on-device backend unavailable — $e');
      localReady = false;
    }

    // EMBEDDER (OPTIONAL): RAG-only, never blocks chat — a failure here must
    // not flip localReady or rethrow.
    if (downloadEmbedder && localReady) {
      try {
        await FlutterGemma.installEmbedder()
            .modelFromNetwork(
              _embeddingModelUrl,
              token: _hfToken.isEmpty ? null : _hfToken,
            )
            .tokenizerFromNetwork(
              _tokenizerUrl,
              token: _hfToken.isEmpty ? null : _hfToken,
            )
            .install();
      } catch (e) {
        debugPrint('⚠️ AiEngine: embedder install failed, RAG disabled — $e');
      }
    }

    // Build AND register every policy's composite model once, right here —
    // not lazily inside modelFor. ai.generate(model: ...) resolves by name
    // via the registry, so an unregistered composite throws NOT_FOUND.
    _registerPolicyModels();
  }

  // A plugin model is registered by name; genkit's `Model` is an `Action`, so
  // look the concrete model up from the registry and cast.
  Future<Model> _resolve(ModelRef ref) async {
    final action = await ai.registry.lookupAction(ActionType.model, ref.name);
    if (action == null) {
      throw StateError('model "${ref.name}" is not registered');
    }
    return action as Model;
  }

  Map<String, Model> get _branches => {
    if (_local != null) kOnDevice: _local!,
    if (_cloud != null) kCloud: _cloud!,
  };

  /// Builds AND registers one composite [Model] per [PolicyMode] whose
  /// required branches are available. A mode that needs `kCloud` (every mode
  /// but `local`) is skipped when there's no API key, instead of crashing on
  /// a half-built `cascadeModel` (its `order` validates eagerly against
  /// `branches`, unlike `hybridModel`).
  void _registerPolicyModels() {
    final branches = _branches;
    for (final mode in PolicyMode.values) {
      if (!_hasRequiredBranches(mode, branches)) continue;
      final model = _buildModel(mode);
      ai.registry.register(model);
      _models[mode] = model;
    }
  }

  bool _hasRequiredBranches(PolicyMode mode, Map<String, Model> branches) {
    switch (mode) {
      case PolicyMode.cloud:
        return branches.containsKey(kCloud);
      case PolicyMode.local:
        return branches.containsKey(kOnDevice);
      case PolicyMode.smart:
      case PolicyMode.cascade:
      case PolicyMode.budget:
        return branches.containsKey(kOnDevice) && branches.containsKey(kCloud);
    }
  }

  /// The composable Genkit `Model` for [mode]. Cascade is a `cascadeModel`;
  /// every other mode is `hybridModel(strategy: strategyFor(mode))`. Called
  /// once per mode by [_registerPolicyModels] — not a per-request factory.
  Model _buildModel(PolicyMode mode) {
    if (mode == PolicyMode.cascade) {
      return cascadeModel(
        branches: _branches,
        order: const [kOnDevice, kCloud],
        accept: (r) => r.text.trim().length > 20,
        name: 'cascade',
      );
    }
    return hybridModel(
      branches: _branches,
      strategy: strategyFor(mode),
      name: mode.name,
    );
  }

  /// The registered, resolvable `Model` for [mode] — built once by
  /// [_registerPolicyModels] during [initialize].
  Model modelFor(PolicyMode mode) {
    final model = _models[mode];
    if (model == null) {
      throw StateError(
        'No model registered for $mode — call initialize() first (or, if '
        'this mode needs the cloud branch, make sure a cloud API key is set).',
      );
    }
    return model;
  }

  /// Pure policy → RoutingStrategy mapping (no models needed), so the routing
  /// decisions are unit-testable. [PolicyMode.cascade] has no strategy — it is
  /// a Model, built in [_buildModel].
  RoutingStrategy strategyFor(PolicyMode mode) {
    switch (mode) {
      case PolicyMode.cloud:
        return PreRoutingStrategy((_) => kCloud);
      case PolicyMode.local:
        return PreRoutingStrategy((_) => kOnDevice);
      case PolicyMode.smart:
        // Image → cloud (only it declares vision). Text → cloud-first (kCloud
        // listed first), on-device as the transient-failure fallback (an
        // offline cloud call throws → hybridModel falls to on-device).
        return WithFallback(
          CapabilityStrategy(
            supports: {
              kCloud: {ModelCapability.vision},
              kOnDevice: <ModelCapability>{},
            },
          ),
          fallbackOrder: const [kOnDevice],
        );
      case PolicyMode.budget:
        return CostStrategy(
          budgetAvailable: () => budgetAvailable,
          premium: kCloud,
          cheap: kOnDevice,
        );
      case PolicyMode.cascade:
        throw ArgumentError('cascade has no RoutingStrategy; use modelFor');
    }
  }

  /// True when [mode]'s primary route starts on the text-only on-device model,
  /// so an attached image cannot be handled (used to block send with a hint).
  bool requiresTextOnly(PolicyMode mode) =>
      mode == PolicyMode.local || mode == PolicyMode.cascade;

  Future<void> dispose() async {
    _ai = null;
    _local = null;
    _cloud = null;
    _models.clear();
  }
}
```

`kOnDevice` and `kCloud` are branch-key constants exported by `genkit_hybrid`
itself — reuse them instead of inventing your own strings so every strategy
agrees on the same keys.

For **Step 4** we only need `PolicyMode.cloud` and `PolicyMode.local`:
`strategyFor` maps each straight to a `PreRoutingStrategy` that always
returns one key. `smart`, `cascade`, and `budget` are covered in Step 4.5 —
`strategyFor(PolicyMode.cascade)` deliberately throws, because cascade isn't
a `RoutingStrategy` at all; `_buildModel` builds it as a `cascadeModel`
directly.

### The hybrid is itself a Model

> **The punchline**: `hybridModel()` (and `cascadeModel()`) return an
> ordinary Genkit `Model`. Nothing downstream needs to know routing
> happened — the result composes with everything a normal model composes
> with: streaming, a RAG-augmented prompt, images. `AiEngine.modelFor(mode)`
> is a drop-in replacement for `googleAI.gemini(...)` or
> `flutterGemma.model(...)`.
>
> **But an ordinary `Model` still has to be registered.** genkit resolves
> `generate(model: ...)` (and `generateStream`) by reducing it to its `.name`
> and looking that name up in `ai.registry` — a `Model` you built but never
> registered fails every call with `NOT_FOUND`. That's why `initialize()`
> calls `_registerPolicyModels()` right after resolving `_local`/`_cloud`:
> it builds and registers all five policy composites *once*, up front, and
> `modelFor` just returns the already-registered instance from `_models`.
> Building a fresh `hybridModel`/`cascadeModel` inside `modelFor` itself —
> without registering it — is the one thing to avoid here.

### Add the policy picker

In `chat_screen.dart`, replace the strategy toggle with a `DropdownButton`
over all five `PolicyMode` values (options are disabled until their
prerequisite is ready — `smart`/`cascade`/`budget` need both cloud and local):

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  child: DropdownButton<PolicyMode>(
    value: _policy,
    isExpanded: true,
    items: [
      DropdownMenuItem(
        value: PolicyMode.cloud,
        enabled: _cloudReady,
        child: const Text('Cloud'),
      ),
      DropdownMenuItem(
        value: PolicyMode.local,
        enabled: _localReady,
        child: const Text('Local'),
      ),
      DropdownMenuItem(
        value: PolicyMode.smart,
        enabled: _cloudReady && _localReady,
        child: const Text('Smart (image-aware)'),
      ),
      DropdownMenuItem(
        value: PolicyMode.cascade,
        enabled: _cloudReady && _localReady,
        child: const Text('Cascade (escalate on quality)'),
      ),
      DropdownMenuItem(
        value: PolicyMode.budget,
        enabled: _cloudReady && _localReady,
        child: const Text('Budget (cost-gated)'),
      ),
    ],
    onChanged: (m) {
      if (m != null) setState(() => _policy = m);
    },
  ),
),
```

### Drive generateStream from modelFor

`_sendMessage()` no longer picks between two services — it always calls the
same `Genkit`, and lets `AiEngine.modelFor(_policy)` decide who answers:

```dart
final userMessage = Message(
  role: Role.user,
  content: [TextPart(text: prompt)],
);

// Captured before the call: genkit_hybrid doesn't report which branch
// actually ran, so this is a best-effort demo counter, not an exact count
// of cloud calls — see the accounting comment below.
final wasBudgetAvailable = _engine.budgetAvailable;

final stream = _engine.ai.generateStream(
  model: _engine.modelFor(_policy),
  messages: [userMessage],
);
await for (final chunk in stream) {
  buffer.write(chunk.text);
  // ... same throttled setState loop as Step 2/3
}

// Best-effort demo counter for CostStrategy: genkit_hybrid exposes no
// "which branch ran" signal, so a Budget call that transiently fell back
// to on-device still counts here as spent; Budget stops climbing once the
// cap is hit either way.
if (_policy == PolicyMode.cloud) {
  _engine.cloudCallsSpent++;
} else if (_policy == PolicyMode.budget && wasBudgetAvailable) {
  _engine.cloudCallsSpent++;
}
```

`prompt` here is still `text` unless RAG rewrote it — that wiring is
unchanged and lands for real in Step 6.

### Test it

1. Switch to **Cloud** and send a message — Gemini answers.
2. Switch to **Local** and send a message — Gemma 3 1B answers.
3. Leave **Smart**, **Cascade**, and **Budget** for Step 4.5 — right now
   `strategyFor` treats them correctly, but nothing exercises their
   interesting behavior (an image, a bad on-device answer, a spent budget)
   until then.

## Step 4.5: Smart routing & images
Duration: 20

Three of the five `PolicyMode` values only get interesting once the app can
send more than plain text, and once there's a signal to route on besides "the
user picked cloud or local." This step adds image input, wires it through
`CapabilityStrategy`, and walks through what `smart`, `cascade`, and `budget`
actually decide.

### Update dependencies

```yaml
  # Image input (multimodal)
  image_picker: ^1.2.3
```

Run `flutter pub get`.

### Attach an image

In `chat_screen.dart`, add the picker and its state:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

// in _ChatScreenState:
final _picker = ImagePicker();
Uint8List? _attachedImage;
String? _attachedMime;

Future<void> _attachImage() async {
  final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
  if (picked == null) return;
  final bytes = await picked.readAsBytes();
  if (!mounted) return;
  setState(() {
    _attachedImage = bytes;
    _attachedMime = picked.mimeType ?? 'image/jpeg';
  });
}
```

Add an `IconButton(icon: const Icon(Icons.image_outlined))` next to the send
button that calls `_attachImage`, and a small thumbnail preview (`Image.memory`
+ a close button) shown above the input row while `_attachedImage != null`.

### Build a multimodal message

`_sendMessage()` now builds a `content` list instead of a single `TextPart`:

```dart
final content = <Part>[TextPart(text: prompt)];
if (_attachedImage != null) {
  final mime = _attachedMime ?? 'image/jpeg';
  final dataUri = 'data:$mime;base64,${base64Encode(_attachedImage!)}';
  // contentType MUST be set: the on-device plugin drops media without an
  // image/* contentType, and CapabilityStrategy reads it to detect vision.
  content.add(
    MediaPart(
      media: Media(contentType: mime, url: dataUri),
    ),
  );
}
final userMessage = Message(role: Role.user, content: content);
```

`contentType` is the load-bearing detail: `CapabilityStrategy` (below) only
recognizes a `MediaPart` as vision when its `Media.contentType` starts with
`image/` — an `image_picker` file with no MIME type falls back to
`'image/jpeg'` so it's never silently dropped.

### Smart, Cascade, and Budget

Back in `AiEngine.strategyFor`, the three remaining cases:

```dart
case PolicyMode.smart:
  // Image → cloud (only it declares vision). Text → cloud-first (kCloud
  // listed first), on-device as the transient-failure fallback (an
  // offline cloud call throws → hybridModel falls to on-device).
  return WithFallback(
    CapabilityStrategy(
      supports: {
        kCloud: {ModelCapability.vision},
        kOnDevice: <ModelCapability>{},
      },
    ),
    fallbackOrder: const [kOnDevice],
  );
case PolicyMode.budget:
  return CostStrategy(
    budgetAvailable: () => budgetAvailable,
    premium: kCloud,
    cheap: kOnDevice,
  );
```

- **Smart** — `CapabilityStrategy` inspects the outgoing `ModelRequest` for
  media parts. A text-only request has no required capability, so both
  branches qualify and it returns `[kCloud, kOnDevice]` (cloud-first, in
  `supports`' insertion order). An image request requires `vision`, which
  only `kCloud` declares, so `CapabilityStrategy` alone returns `[kCloud]`.
  `WithFallback` then appends `kOnDevice` as a tail either way — that tail
  exists for a *transient* cloud failure (offline, timeout), not to hand the
  image to a model that can't see it.
- **Cascade** — built in `_buildModel`, not `strategyFor`:
  `cascadeModel(branches: _branches, order: [kOnDevice, kCloud], accept: (r) => r.text.trim().length > 20)`.
  It tries the on-device model first; if the response passes `accept` (here,
  "longer than 20 characters") it's returned as-is, otherwise it escalates to
  cloud. `cascadeModel` is **non-streaming internally** — even through
  `ai.generateStream`, a cascade-routed request buffers the whole winning
  response and emits it as a single chunk.
- **Budget** — `CostStrategy` returns `[premium, cheap]` while
  `budgetAvailable()` is true, `[cheap]` once it isn't. `AiEngine` owns the
  budget itself: `cloudCallsSpent` is a plain int the app increments after
  every `cloud`/`budget` call (see the `_sendMessage` snippet above) and
  compares against `budgetCap` (3 by default). `genkit_hybrid` has no billing
  SDK — it only ever sees the resulting `bool`.

> **Smart + image on a cloud outage**: with an attached image, Smart routes
> to cloud for vision — but if that cloud call itself fails, `WithFallback`
> still falls back to on-device, which can't see the image and answers from
> the text alone. Smart silently degrades to text-only on a cloud outage; it
> doesn't surface that degradation to the user.
>
> **Budget shares its counter with Cloud**: `cloudCallsSpent` is one counter,
> not one per policy — a Cloud-mode send also spends the Budget allowance.
> Demo Cloud before Budget and the allowance may already be partly (or
> fully) spent by the time you switch.

### The capability block

An image can't reach a policy whose primary route is the text-only on-device
model. `AiEngine.requiresTextOnly` flags that:

```dart
bool requiresTextOnly(PolicyMode mode) =>
    mode == PolicyMode.local || mode == PolicyMode.cascade;
```

`_sendMessage()` checks it before doing anything else:

```dart
if (_attachedImage != null && _engine.requiresTextOnly(_policy)) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        "The on-device model can't see images — switch to Smart or Cloud.",
      ),
    ),
  );
  return;
}
```

`local` always starts on-device; `cascade`'s first hop is always on-device
too — both are blocked. `smart` and `cloud` always keep `kCloud` reachable
(as the primary route or the `WithFallback` tail), so they're let through.
`budget` is let through as well, but that's the one optimistic case: once
`cloudCallsSpent` hits `budgetCap`, `CostStrategy` routes to `[kOnDevice]`
only — `requiresTextOnly` checks the policy, not its current spend, so an
image sent on a spent budget still isn't guaranteed a vision-capable branch.

### Manual runbook

1. Send a text message in each of the five modes — Cloud, Local, Smart,
   Cascade, Budget — and confirm each one answers.
2. Attach an image, switch to **Smart**, and send — the response comes from
   Gemini (`CapabilityStrategy` routes the vision request straight to
   `kCloud`).
3. Turn off WiFi, stay on **Smart**, and send a text message — the cloud
   attempt fails transiently and `WithFallback` reroutes to the on-device
   model (slower, but it answers).
4. Turn WiFi back on, switch to **Budget**, and keep sending text messages.
   `cloudCallsSpent` counts every completed Cloud- or Budget-mode call
   cumulatively for the whole session — including the Cloud-mode message
   from step 1 — so it may already be close to `budgetCap` (3) by the time
   you get here. Once it reaches the cap, routing flips to on-device only
   (`CostStrategy` sees `budgetAvailable == false`); a hot restart resets
   the counter to 0 if you want to watch it flip from a clean count.
5. Switch to **Local** and attach an image — send is blocked before any
   request goes out, with the "can't see images" snackbar.

`flutter test test/ai_engine_policy_test.dart` exercises the same
`strategyFor`/`requiresTextOnly` decisions as a fast, deviceless unit test —
useful to rerun after touching routing logic instead of redoing the whole
runbook by hand.

## Step 5: Embeddings with Genkit
Duration: 20

### How embeddings work

An embedding turns text into a vector of numbers that captures semantic meaning.
Similar texts have similar vectors. EmbeddingGemma 300M runs entirely on-device.

### Install the embedding model

```dart
await FlutterGemma.installEmbedder()
    .modelFromNetwork(embeddingModelUrl, token: token)
    .tokenizerFromNetwork(tokenizerUrl, token: token)
    .install();
```

### Register the embedder with Genkit

There's no second `Genkit` to build — `AiEngine` already declared the embedder
back in Step 4, right next to the on-device model in the *same*
`GenkitFlutterGemmaPlugin`:

```dart
GenkitFlutterGemmaPlugin(
  models: [FlutterGemmaModelConfig(name: kLocalModel, /* … */)],
  embedders: [FlutterGemmaEmbedderConfig(name: kEmbedder)], // 'embedding-gemma-300m'
),
```

So the one `AiEngine` Genkit already exposes the embedder — you just call
`ai.embed(...)` on it (next).

### Generate embeddings

```dart
final embeddings = await ai.embed(
  embedder: flutterGemma.embedder('embedding-gemma-300m'),
  document: DocumentData(content: [TextPart(text: content)]),
);
final vector = embeddings.first.embedding; // List<double>
```

### Index the tourist data

Create `lib/services/rag_service.dart`. In `initialize()`, loop over 10 city
JSON files and embed each one. Store the `List<double>` vectors in memory.

```dart
for (final city in _cityFiles) {
  final content = _buildContent(data); // description + attractions + cuisine...
  final embeddings = await ai.embed(
    embedder: flutterGemma.embedder(_embedderName),
    document: DocumentData(content: [TextPart(text: content)]),
  );
  _store.add(_VectorDocument(id: city, content: content,
      city: name, embedding: embeddings.first.embedding));
}
```

> **Key insight**: `ai.embed(embedder: ...)` is model-agnostic. Replace
> `flutterGemma.embedder(...)` with any other registered embedder — the rest
> of the code stays the same.

## Step 6: RAG — Retrieval-Augmented Generation
Duration: 20

### Wire RagService to AiEngine

`RagService` doesn't manage its own `Genkit` instance or model installation —
it takes both from `AiEngine`, the same way `_sendMessage` does:

```dart
final rag = RagService(
  ai: _engine.ai,
  embedderName: _engine.embedderName,
);
await rag.initialize(
  onStatus: (s) {
    if (mounted) setState(() => _statusMessage = s);
  },
);
_ragService = rag;
_ragReady = true;
```

### Semantic search

When the user sends a query, embed it and find the closest city documents
using cosine similarity:

```dart
Future<RagResult> searchAndBuildContext(String query) async {
  // 1. Embed the query
  final queryEmbeddings = await _ai.embed(
    embedder: flutterGemma.embedder(_embedderName),
    document: DocumentData(content: [TextPart(text: query)]),
  );
  final queryVector = queryEmbeddings.first.embedding;

  // 2. Score all documents
  final scored = _store
      .map((doc) => (doc: doc, score: _cosine(queryVector, doc.embedding)))
      .where((r) => r.score >= 0.5)
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  // 3. Build augmented prompt with top 3 results
  final topK = scored.take(3);
  final context = topK.map((r) => r.doc.content).join('\n\n');
  final augmentedPrompt =
      'Based on the following travel information:\n\n$context\n\n'
      'Answer the question: $query';

  return RagResult(augmentedPrompt: augmentedPrompt, ...);
}
```

### Add RAG toggle to the UI

In `chat_screen.dart`:
1. Add a `Switch` in the `AppBar` to toggle RAG
2. In `_sendMessage()`, if RAG is enabled call `searchAndBuildContext(text)` before generating
3. Display `ragResult.sources` in a banner below the AppBar

### Test it

Try these queries:
- "What should I eat in Tokyo?" → sources: Tokyo (92%)
- "Best European city for history?" → sources: Prague (78%), Istanbul (71%)
- "Tell me about the Eiffel Tower" → sources: Paris (95%)

## Step 7: Polish and Conclusion
Duration: 10

### Error handling and loading states

- Show download progress during model installation
- Disable strategy buttons when a service fails to initialize
- Show "Generating..." indicator during streaming
- Graceful error messages in the chat

### What we built

| Capability | Technology |
|------------|-----------|
| Cloud inference | `genkit_google_genai` → Gemini 3.7 Flash |
| On-device inference | `genkit_flutter_gemma` → Gemma 3 1B |
| Hybrid routing | `genkit_hybrid` — `hybridModel`/`cascadeModel` (cloud, local, smart, cascade, budget) |
| Multimodal input | `image_picker` + `MediaPart`, routed by `CapabilityStrategy` |
| On-device embeddings | `genkit_flutter_gemma` → EmbeddingGemma 300M |
| RAG pipeline | Genkit `embed()` + in-memory cosine search |

### The Genkit advantage

The old approach needed two completely different APIs — Firebase AI Logic for
cloud and raw flutter_gemma calls for local. With Genkit:

```dart
// Both use the same API — only model: changes
ai.generateStream(model: googleAI.gemini('gemini-3.7-flash'), prompt: prompt)
ai.generateStream(model: flutterGemma.model('gemma-3-1b-it'), prompt: prompt)
ai.embed(embedder: flutterGemma.embedder('embedding-gemma-300m'), document: ...)

// genkit_hybrid composes both into one routable model — still the same call:
ai.generateStream(model: engine.modelFor(policy), messages: [userMessage])
```

Routing, fallback, observability, and tool calling all work the same way
regardless of which model backend you use.

### What's next

- **Production embeddings**: Persist the vector store with SQLite + `drift` so
  you don't re-embed on every cold start
- **More models**: Swap `gemini-3.7-flash` for `gemini-3.7-pro` for complex
  queries, or add a second on-device model for specialized tasks
- **Genkit flows**: Wrap the hybrid routing in a `defineFlow` to add
  observability, retries, and structured output
- **On-device RAG with Qdrant**: Replace the in-memory store with
  [Qdrant](https://qdrant.tech) for persistent, scalable vector search

### Resources

- [genkit_flutter_gemma on pub.dev](https://pub.dev/packages/genkit_flutter_gemma)
- [genkit_hybrid on pub.dev](https://pub.dev/packages/genkit_hybrid)
- [genkit on pub.dev](https://pub.dev/packages/genkit)
- [genkit_google_genai on pub.dev](https://pub.dev/packages/genkit_google_genai)
- [flutter_gemma on pub.dev](https://pub.dev/packages/flutter_gemma)
- [Genkit Dart documentation](https://genkit.dev)
