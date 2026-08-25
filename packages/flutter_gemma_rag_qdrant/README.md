# flutter_gemma_rag_qdrant

qdrant-edge on-device RAG vector store for [flutter_gemma](https://pub.dev/packages/flutter_gemma).
Opt-in package implementing `VectorStoreRepository` on top of the official
[`qdrant_edge`](https://pub.dev/packages/qdrant_edge) UniFFI Dart SDK
(a binding over the `qdrant-edge` Rust crate). qdrant's HNSW index makes it the fastest **native** RAG store —
roughly **5–11× faster search** than the in-SQLite `sqlite-vec`/`vec0` store at
1k–10k docs, and further ahead as the corpus grows (see
[benchmark](https://github.com/DenisovAV/flutter_gemma/blob/main/docs/benchmarks/rag_sqlite_vec_vs_qdrant.md)).
(The earlier "~75×" figure was against the now-deleted Dart brute-force store.)
For web, or when exact KNN with identical results across platforms matters more
than peak speed, use `flutter_gemma_rag_sqlite`.

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
final hits = await FlutterGemmaPlugin.instance.searchSimilar(query: query, topK: 5);
```

`QdrantVectorStore` also honors the payload-aware `Filter` DSL on
`searchSimilar(..., filter: Filter(must: [FieldEquals(key: 'lang', value: 'en')], mustNot: [...]))`.

Field names here are almost unrestricted — payload keys are free-form UTF-8 —
with one exception: a name containing `.` is rejected, because qdrant reads it
as a nested payload path, so `doc.type` would mean "`type` inside `doc`" here
and a flat column on sqlite. Note this store accepts names `SqliteVectorStore`
refuses; if a schema must work on both, keep it inside sqlite's narrower set.

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


## Upgrading from 1.x

**2.0 cannot read a store written by 1.x.** The shard format changed with the
move to crate 0.8.0, and this release keeps its data in an owned
`qdrant_edge_v1/` subdirectory rather than directly at the path you pass to
`initialize()`.

`initialize()` itself throws a `VectorStoreException` naming the situation —
not the first write, so a read-only session hits it too. The remedy is one
call, and it removes the old on-disk layout for you:

```dart
// VectorStoreException comes from flutter_gemma, not from this package —
// this barrel exports only QdrantVectorStore.
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';

final store = QdrantVectorStore();
try {
  await store.initialize(path);
} on VectorStoreException {
  await store.clear();          // removes the 1.x layout as well as the 2.x one
  await store.initialize(path);
}
// ...then re-index your documents.
```

`clear()` only removes the entries a qdrant shard owns (`edge_config.json`,
`wal/`, `segments/`) — unrelated files you keep alongside the store are left
alone.

If you skip this, nothing silently degrades: the store refuses to open rather
than coming up empty.

## Platforms

| Platform | Support |
|----------|---------|
| Android (arm64, x64) | ✅ |
| iOS (arm64, simulator) | ✅ |
| macOS (arm64) | ✅ |
| Linux | ✅ |
| Windows (x64) | ✅ |
| Web | ❌ — use `flutter_gemma_rag_sqlite` (`WebSqliteVectorStore`) |

An unsupported native target (e.g. Intel macOS, Windows arm64, 32-bit Android)
has no prebuilt archive for the SDK's hook to fetch. The hook prints a warning
naming the slice and skips it, so the build still produces the supported ABIs —
**armeabi-v7a is in `flutter build apk`/`appbundle`'s default set**, and failing
there would break the standard Android release build of every consuming app.
Code that reaches the engine on a skipped ABI fails to load the library at
runtime; restrict the ABI set if you want that to be impossible:

```
flutter build apk --target-platform android-arm64,android-x64
```

The native binary is provisioned by the `qdrant_edge` SDK's own Native Assets
build hook (SHA256-verified per-platform archive) — this package has no
native code, build script, or download logic of its own.
