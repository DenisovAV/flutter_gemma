---
title: Migration (0.x → 1.0)
description: Upgrade from the 0.16.x monolith to the 1.0 modular packages — one new call, every other API unchanged.
image: https://fluttergemma.dev/images/og-image.png
---

1.0 splits the monolithic `flutter_gemma` plugin into a small **core** package
plus **opt-in** packages, so your app only ships the native weight it actually
uses. This is the **only breaking change**: you add the packages you need and one
`initialize(...)` call. **Every model / session / chat / embedding / RAG API is
unchanged** — your existing inference code keeps working as-is.

## TL;DR

1. Add the opt-in packages for the formats/features you use (see table below).
2. Call `await FlutterGemma.initialize(inferenceEngines: [...], ...)` once in `main()`, passing the engines/backends from the packages you added.
3. Everything else stays the same.

## 1. pubspec.yaml

**Before (0.16.x):**

```
dependencies:
  flutter_gemma: ^0.16.3
```

**After (1.0):**

```
dependencies:
  flutter_gemma: ^1.6.1                 # core — always required
  flutter_gemma_litertlm: ^1.5.0        # add if you run .litertlm models (also provides LiteRtEmbeddingBackend)
  flutter_gemma_mediapipe: ^1.0.4       # add if you run .task / .bin models
  flutter_gemma_embeddings: ^2.0.0      # add if you compute embeddings (needs a backend, see above)
  flutter_gemma_rag_qdrant: ^1.1.0      # add for native on-device RAG (qdrant)
  flutter_gemma_rag_sqlite: ^1.1.0      # add for on-device RAG (sqlite-vec; all platforms incl. web)
```

Pick by what you actually used in 0.16.x:

| In 0.16.x you used… | Add in 1.0 |
|---|---|
| `.litertlm` models (Gemma 4, Qwen3, FastVLM, any desktop) | `flutter_gemma_litertlm` |
| `.task` / `.bin` models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4, …) | `flutter_gemma_mediapipe` |
| `generateEmbedding()` / `installEmbedder()` | `flutter_gemma_embeddings` + `flutter_gemma_litertlm` (`LiteRtEmbeddingBackend`) |
| RAG (`addDocument` / `searchSimilar`), fastest on native | `flutter_gemma_rag_qdrant` |
| RAG on web (or a portable store on any platform) | `flutter_gemma_rag_sqlite` |

<Info>
Not sure which format your models are? Desktop is always `.litertlm`
(`flutter_gemma_litertlm`). On mobile/web check the file extension you install.
You can add **both** engine packages and let the registry route each model by its
file type.
</Info>

> **New opt-in packages since 1.2/1.3** (not migration targets from the 0.16.x
> monolith — they add new capabilities): `flutter_gemma_agent` (on-device agent
> skills — SKILL.md + tool-calling loop), `flutter_gemma_builtin_ai` (OS
> system models — Gemini Nano on Android, Apple Foundation Models on iOS/macOS),
> and `flutter_gemma_onnx` (ONNX Runtime — ORT-GenAI text generation +
> plain-ORT embeddings via `dart:ffi` on native, + Web via Transformers.js /
> onnxruntime-web). Add any of them only if you want that feature. See
> [Getting Started](/docs/getting-started).

## Breaking: embeddings 2.0.0 — `LiteRtEmbeddingBackend` moved

<Warning>
`flutter_gemma_embeddings` **2.0.0** is a breaking change, independent of the
0.16.x → 1.0 migration above. As of `flutter_gemma_litertlm` **1.5.0**,
`flutter_gemma_embeddings` no longer ships a concrete embedding backend — it's
now a runtime-agnostic pipeline (tokenizer, pooling, isolate worker) that any
engine package can implement. `LiteRtEmbeddingBackend` moved to
`flutter_gemma_litertlm`.
</Warning>

If your app registers `LiteRtEmbeddingBackend()`, fix the import and bump both
dependencies:

```dart
// Before (< 2.0.0):
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';

// After (>= 2.0.0):
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
```

```
dependencies:
  flutter_gemma_embeddings: ^2.0.0   # runtime-agnostic pipeline (still required)
  flutter_gemma_litertlm: ^1.5.0     # now provides LiteRtEmbeddingBackend
```

`FlutterGemma.initialize(embeddingBackends: [LiteRtEmbeddingBackend()])` itself
is unchanged — only where the class is imported from. You still depend on
`flutter_gemma_embeddings` (it owns the tokenizer/pooling/worker); you just no
longer import a backend class from it. If you'd rather run embeddings over an
ONNX/ORT model instead, `flutter_gemma_onnx`'s `OnnxEmbeddingBackend` is a
drop-in alternative — see [Packages](/docs/packages#onnx-runtime-engine).

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
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
    embeddingBackends: const [LiteRtEmbeddingBackend()], // flutter_gemma_litertlm
    vectorStore: QdrantVectorStore(),          // or WebSqliteVectorStore() on web
    // '' when the define is absent — an empty token still sends a bare
    // `Authorization: Bearer` header, so pass null instead.
    huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN').isNotEmpty
        ? const String.fromEnvironment('HUGGINGFACE_TOKEN')
        : null,
  );

  runApp(MyApp());
}
```

Only list what you ship. If you don't do embeddings, omit `embeddingBackends`; if
you don't do RAG, omit `vectorStore`.

## 3. Everything else is unchanged

These keep the exact same API — no edits needed:

```dart
// install + run a model
await FlutterGemma.installModel(
    modelType: ModelType.gemma4, fileType: ModelFileType.litertlm)
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
await FlutterGemma.rag.initialize('rag_store');
await FlutterGemma.rag.addDocument(/* ... */);
final hits = await FlutterGemma.rag.searchSimilar(query: query, topK: 5);
```

## What you'll see if you forget step 2

- Calling `getActiveModel()` with no matching `inferenceEngines` registered throws a `StateError` telling you which package to add.
- `createEmbeddingModel()` / auto-embedding RAG with no `embeddingBackends` throws a clear "add `flutter_gemma_litertlm`" error.
- RAG calls with no `vectorStore` throw "add a RAG package" (the default store is an unconfigured sentinel).

## Platform setup

Native setup moved to the package that owns it:

- **MediaPipe Gradle / Pod deps + the `@mediapipe/tasks-genai` web CDN** are now in `flutter_gemma_mediapipe` (bundled automatically on Android/iOS; add the CDN `<script>` for web).
- **The `.litertlm` native library + the `@litert-lm/core` web CDN** are in `flutter_gemma_litertlm`.
- **The sqlite-vec web loader** (`sqlite3.wasm` with `sqlite-vec` statically linked) is in `flutter_gemma_rag_sqlite`.

The iOS/Android entitlements and manifest entries still apply when you ship an
inference engine. See the full [Installation guide](/docs/installation).

## Troubleshooting

**`dlopen` "library not found" after removing a package:** if you had both
`flutter_gemma_litertlm` and `flutter_gemma_embeddings` and removed one, run
`flutter clean` and delete `~/Library/Caches/flutter_gemma/native` (Windows:
`%LOCALAPPDATA%\flutter_gemma\native`), then `flutter pub get`.
`flutter_gemma_litertlm` owns the native LiteRT library;
`flutter_gemma_embeddings` (and `flutter_gemma_speech`) consume it
transitively — they have no Native-Assets hook of their own.
