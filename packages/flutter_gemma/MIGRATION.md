# Migrating to flutter_gemma 1.0

1.0 splits the monolithic `flutter_gemma` plugin into a small **core** package
plus **opt-in** packages, so your app only ships the native weight it actually
uses. This is the **only breaking change**: you add the packages you need and one
`initialize(...)` call. **Every model / session / chat / embedding / RAG API is
unchanged** — your existing inference code keeps working as-is.

## TL;DR

1. Add the opt-in packages for the formats/features you use (see table below).
2. Call `FlutterGemma.initialize(inferenceEngines: [...], ...)` once in `main()`,
   passing the engines/backends from the packages you added.
3. Everything else stays the same.

## 1. pubspec.yaml

**Before (0.16.x):**
```yaml
dependencies:
  flutter_gemma: ^0.16.3
```

**After (1.0):**
```yaml
dependencies:
  flutter_gemma: ^1.0.0                 # core — always required
  flutter_gemma_litertlm: ^1.0.0        # add if you run .litertlm models
  flutter_gemma_mediapipe: ^1.0.0       # add if you run .task / .bin models
  flutter_gemma_embeddings: ^1.0.0      # add if you compute embeddings
  flutter_gemma_rag_qdrant: ^1.0.0      # add for native on-device RAG
  flutter_gemma_rag_sqlite: ^1.0.0      # add for web (or native sqlite) RAG
```

Pick by what you actually used in 0.16.x:

| In 0.16.x you used… | Add in 1.0 |
|---|---|
| `.litertlm` models (Gemma 4, Qwen3, FastVLM, any desktop) | `flutter_gemma_litertlm` |
| `.task` / `.bin` models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4, …) | `flutter_gemma_mediapipe` |
| `generateEmbedding()` / `installEmbedder()` | `flutter_gemma_embeddings` |
| RAG (`addDocument` / `searchSimilar`) on native | `flutter_gemma_rag_qdrant` |
| RAG on web | `flutter_gemma_rag_sqlite` |

> Not sure which format your models are? Desktop is always `.litertlm`
> (`flutter_gemma_litertlm`). On mobile/web check the file extension you install.
> You can add **both** engine packages and let the registry route each model by
> its file type.

## 2. main.dart — the one new call

**Before (0.16.x):** engines were bundled into core; `initialize()` was optional.
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // (initialize was optional — only for HF token / retries)
  runApp(MyApp());
}
```

**After (1.0):** register the packages you added.
```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
    embeddingBackends: const [LiteRtEmbeddingBackend()],
    vectorStore: QdrantVectorStore(),          // or WebSqliteVectorStore() on web
    huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN'),
  );

  runApp(MyApp());
}
```

Only list what you ship. If you don't do embeddings, omit `embeddingBackends`;
if you don't do RAG, omit `vectorStore`.

## 3. Everything else is unchanged

These keep the exact same API — no edits needed:

```dart
// install + run a model
await FlutterGemma.installModel(modelType: ModelType.gemma4)
    .fromNetwork(url, token: token).install();
final model = await FlutterGemma.getActiveModel(maxTokens: 2048);
final chat  = await model.createChat();
await chat.addQueryChunk(Message.text(text: 'Hello', isUser: true));
await for (final r in chat.generateChatResponseAsync()) { /* r is a ModelResponse */ }

// embeddings + RAG
await FlutterGemma.installEmbedder()
    .modelFromNetwork(modelUrl, token: token)
    .tokenizerFromNetwork(tokenizerUrl, token: token)
    .install();
await FlutterGemmaPlugin.instance.addDocument(/* ... */);
final hits = await FlutterGemmaPlugin.instance.searchSimilar(query, topK: 5);
```

## What you'll see if you forget step 2

- Calling `getActiveModel()` with no matching `inferenceEngines` registered throws
  a `StateError` telling you which package to add.
- `createEmbeddingModel()` / auto-embedding RAG with no `embeddingBackends` throws
  a clear "add `flutter_gemma_embeddings`" error.
- RAG calls with no `vectorStore` throw "add a RAG package" (the default store is
  an unconfigured sentinel).

## Platform setup

Native setup moved to the package that owns it:

- **MediaPipe Gradle / Pod deps + the `@mediapipe/tasks-genai` web CDN** are now in
  `flutter_gemma_mediapipe` (bundled automatically on Android/iOS; add the CDN
  `<script>` for web — see the main README).
- **The `.litertlm` native library + the `@litert-lm/core` web CDN** are in
  `flutter_gemma_litertlm`.
- **wa-sqlite web loader** is in `flutter_gemma_rag_sqlite`.

The iOS/Android entitlements and manifest entries from the main README still
apply when you ship an inference engine. See the
[README Setup section](README.md#setup) for the full list.

## Troubleshooting

- **`dlopen` "library not found" after removing a package:** if you had both
  `flutter_gemma_litertlm` and `flutter_gemma_embeddings` and removed one, run
  `flutter clean` and delete `~/Library/Caches/flutter_gemma/native` (Windows:
  `%LOCALAPPDATA%\flutter_gemma\native`), then `flutter pub get`. They share one
  native library; see those packages' READMEs.
