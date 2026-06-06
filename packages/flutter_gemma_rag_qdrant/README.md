# flutter_gemma_rag_qdrant

qdrant-edge on-device RAG vector store for [flutter_gemma](https://pub.dev/packages/flutter_gemma).
Opt-in package implementing `VectorStoreRepository` via a Rust FFI shim
(`qdrant-edge`) — ~75× faster search than the legacy sqlite + HNSW path.

**Native only** (Android, iOS, macOS, Linux, Windows). For web, use
[`flutter_gemma_rag_sqlite`](https://pub.dev/packages/flutter_gemma_rag_sqlite)
(`WebSqliteVectorStore`).

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';

await FlutterGemma.initialize(
  vectorStore: QdrantVectorStore(),
);
```

Then use the unchanged RAG API:

```dart
await FlutterGemmaPlugin.instance.initializeVectorStore('rag_store'); // a directory
await FlutterGemmaPlugin.instance.addDocument(/* ... */);
final hits = await FlutterGemmaPlugin.instance.searchSimilar(query, topK: 5);
```

`QdrantVectorStore` also honors the payload-aware `Filter` DSL on
`searchSimilar(..., filter: Filter(must: [FieldEquals('lang', 'en')], mustNot: [...]))`.

> The storage path passed to `initializeVectorStore` is treated as a **shard
> directory** (qdrant creates files under it), not a single `.db` file. Use a
> distinct path from any sqlite store so they don't collide on disk.

## Behavior notes

- **Cross-platform web is not supported** — `QdrantVectorStore` is native-only.
- `enableHnsw` is accepted but a no-op: qdrant decides indexing internally
  (brute-forces below ~20k points, which is already faster than the Dart HNSW
  for typical RAG corpora).
- `addDocument`'s `metadata` is forwarded as a raw JSON string into the payload;
  filtering by metadata fields requires valid JSON.
- Distance defaults to cosine.

## Platforms

| Platform | Support |
|----------|---------|
| Android / iOS | ✅ FFI (qdrant-edge) |
| macOS / Linux / Windows | ✅ FFI (qdrant-edge) |
| Web | ❌ — use `flutter_gemma_rag_sqlite` (`WebSqliteVectorStore`) |

The native library is fetched at build time by the package's Native-Assets hook
(SHA256-verified) — no manual setup.
