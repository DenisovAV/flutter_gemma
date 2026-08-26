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
  flutter_gemma: ^1.6.5                 # core — always required
  flutter_gemma_litertlm: ^1.5.3        # add if you run .litertlm models (also provides LiteRtEmbeddingBackend)
  flutter_gemma_mediapipe: ^1.0.5       # add if you run .task / .bin models
  flutter_gemma_embeddings: ^2.0.0      # add if you compute embeddings (needs a backend, see above)
  flutter_gemma_rag_qdrant: ^1.3.0      # add for native on-device RAG (qdrant)
  flutter_gemma_rag_sqlite: ^1.3.1      # add for on-device RAG (sqlite-vec; all platforms incl. web)
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
  flutter_gemma_litertlm: ^1.5.3     # now provides LiteRtEmbeddingBackend
```

`FlutterGemma.initialize(embeddingBackends: [LiteRtEmbeddingBackend()])` itself
is unchanged — only where the class is imported from. You still depend on
`flutter_gemma_embeddings` (it owns the tokenizer/pooling/worker); you just no
longer import a backend class from it. If you'd rather run embeddings over an
ONNX/ORT model instead, `flutter_gemma_onnx`'s `OnnxEmbeddingBackend` is a
drop-in alternative — see [Packages](/docs/packages#onnx-runtime-engine).

## Breaking: rag_sqlite 1.1.0 — the index does not carry over

<Warning>
`flutter_gemma_rag_sqlite` **1.1.0** replaced the Dart brute-force/HNSW store
with in-SQLite `vec0` KNN, and with it the table the index lives in:
`documents` became `vec_documents`. **An index written by 1.0.x is not read by
1.1.0+.** This shipped as a minor version with no note — if you upgraded and
your RAG answers went vague, this is why.
</Warning>

Nothing errors. `initialize()` succeeds, `getStats()` reports **0 documents**,
`searchSimilar()` returns **no hits**, and your rows are still sitting in the
old `documents` table, unread. The model then answers without the context it
used to have, which reads as the model getting worse rather than as a
migration you missed.

**Your data is recoverable.** Unlike the qdrant break below, nothing is lost:
1.0.x stored `id`, `content`, the `embedding` as a `Float32` BLOB and
`metadata` in a plain table, all still readable. Move it once at startup — no
re-embedding, no model needed:

```dart
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';   // add sqlite3 to your own pubspec

final store = SqliteVectorStore();
await store.initialize(path);

final db = sqlite3.open(path);
final hasLegacy = db
    .select("SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='documents'")
    .isNotEmpty;

if (hasLegacy) {
  for (final row
      in db.select('SELECT id, content, embedding, metadata FROM documents')) {
    // 1.0.x wrote each element with setFloat32(..., Endian.little); read it
    // back the same way. ByteData.sublistView needs no 4-byte alignment,
    // which a raw asFloat32List view of the BLOB would.
    final bytes = ByteData.sublistView(row['embedding'] as Uint8List);
    await store.addDocument(
      id: row['id'] as String,
      content: row['content'] as String,
      embedding: List<double>.generate(
        bytes.lengthInBytes ~/ 4,
        (i) => bytes.getFloat32(i * 4, Endian.little),
      ),
      metadata: row['metadata'] as String?,
    );
  }
  db.execute('DROP TABLE documents');   // only after the loop succeeds
}
db.dispose();
```

Guard it with your own "already migrated" flag if you prefer, but the
`sqlite_master` check is enough: dropping the table is what makes the block a
no-op on every later launch.

There is no built-in migration call — this is a one-time fix for an upgrade
that has already happened, not an ongoing API.

## Breaking: rag_qdrant 1.3.0 — the on-disk store is not readable

<Warning>
`flutter_gemma_rag_qdrant` **1.3.0** moves onto the official `qdrant_edge`
UniFFI SDK, and **an index written by 1.2 or earlier cannot be read**. This is a
data change, not an API change: your `addDocument` / `searchSimilar` calls are
unchanged, but the documents already on the device are not.
</Warning>

An upgraded app finds no documents where its corpus used to be. 2.0 refuses
loudly rather than starting empty — `initialize()` throws a
`QdrantLegacyStoreException` naming the old store — so this shows up the first
time the store opens, not as silently unanswered questions later.

Remove the old store's files once, then re-index. 2.0 will not do it for you:
it never deletes data it cannot read, and the three entries a 1.x shard owns
(`edge_config.json`, `wal/`, `segments/`) may sit beside files of your own.

```dart
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';

final store = QdrantVectorStore();
try {
  await store.initialize(path);
} on QdrantLegacyStoreException catch (e) {
  // e.message names the three entries a 1.x shard owns. Remove them with the
  // file APIs you already use for `path`, then initialize() again.
  rethrow;
}
// ...then re-add your documents.
```

<Warning>
Catch `QdrantLegacyStoreException`, not the base `VectorStoreException`.
`initialize()` also throws the base type when a 2.0 shard is present but will
not open right now — a WAL held by another store, a permission problem — and
treating that as "the old format is here" is how a recovery step can act on a
store that is perfectly fine.
</Warning>

`clear()` no longer deletes anything: it empties the shard in place, and it
refuses when a 1.x layout is present rather than removing files it cannot
read.

If your app has no re-indexing path of its own, do the re-index behind the same
progress UI you use for the first run — from the user's side this is a rebuild
of the index, not a migration they can be asked to wait through silently.

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
