---
title: Embeddings & RAG
description: Generate text embeddings and run on-device retrieval-augmented generation (RAG) with a payload-aware Filter API.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma can generate vector embeddings from text (EmbeddingGemma / Gecko on
LiteRT, or BERT / MiniLM / WordPiece models via the ONNX backend)
and run on-device RAG with a vector store. Two stores are available, both with
the same Dart API: **qdrant-edge** — the fastest store on native (HNSW
approximate nearest-neighbour) — and **sqlite-vec** — a portable, exact store
that runs on **all six platforms (Android, iOS, macOS, Linux, Windows, Web)**,
and the only store that runs on Web. Your code is portable across both.

## Setup

Embeddings need the `flutter_gemma_embeddings` package plus a backend that
implements it — `flutter_gemma_litertlm`'s `LiteRtEmbeddingBackend` (or
`flutter_gemma_onnx`'s `OnnxEmbeddingBackend` for ONNX/ORT models, which also
runs on Web via onnxruntime-web). RAG also
needs a vector store package — `flutter_gemma_rag_qdrant` (native, fastest) or
`flutter_gemma_rag_sqlite` (sqlite-vec; all platforms, including Web). Register
them in `await FlutterGemma.initialize(...)`:

```dart
await FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()], // flutter_gemma_litertlm
  vectorStore: QdrantVectorStore(),                    // or WebSqliteVectorStore() on web
);
```

See [Installation](/docs/installation) for the full registration reference.

## Text embeddings

The embedding **dimension depends on the model and backend**. The LiteRT models
(EmbeddingGemma / Gecko) generate **768-dimensional vectors**; with
`OnnxEmbeddingBackend` the dimension is model-dependent (e.g. all-MiniLM-L6-v2 is
384-dim). The number in a model name (64/256/512/1024/2048) is the max input
sequence length in tokens, not the embedding dimension. See
[Models](/docs/models#text-embedding-models) for the full list.

### Install an embedding model

```dart
await FlutterGemma.installEmbedder()
    .modelFromNetwork(
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite',
      token: 'hf_...',
    )
    .tokenizerFromNetwork(
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
      token: 'hf_...',
    )
    .install();
```

### Generate embeddings

```dart
final embedder = await FlutterGemma.getActiveEmbedder();
final embeddings = await embedder.generateEmbeddings(
  docs.map((d) => d.content).toList(),
  taskType: TaskType.retrievalDocument,
);
```

<Info>
The LiteRT `LiteRtEmbeddingBackend` runs embedding on **CPU only**: EmbeddingGemma
is an int4 `.tflite` model, and the TFLite GPU delegate cannot run int4 — so GPU
embedding is not possible for that model format. The `OnnxEmbeddingBackend` is not
bound by this — it runs embeddings on **WebGPU** on Web (onnxruntime-web). Either
way, embedding runs on a background isolate so it doesn't block the UI thread.
</Info>

## On-device RAG / vector store

All RAG operations live on the `FlutterGemma.rag` namespace — the canonical
entry point. (The store is opt-in: register a `vectorStore:` in
`await FlutterGemma.initialize(...)`, or every `rag` call throws a clear "add a RAG
package" error.)

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// 1. Install an embedding model (any of Gecko / EmbeddingGemma) — see above.

// 2. Initialize the vector store (one shard per database path)
await FlutterGemma.rag.initialize('rag_store');

// 3. Add documents — let flutter_gemma compute embeddings for you
for (final doc in docs) {
  await FlutterGemma.rag.addDocument(
    id: doc.id,
    content: doc.content,
    metadata: '{"category":"science","lang":"en"}',
  );
}

// 3b. Or batch-embed yourself and feed pre-computed vectors via
//     addDocumentWithEmbedding(...) for higher throughput.
final embedder = await FlutterGemma.getActiveEmbedder();
final embeddings = await embedder.generateEmbeddings(
  docs.map((d) => d.content).toList(),
  taskType: TaskType.retrievalDocument,
);
for (var i = 0; i < docs.length; i++) {
  await FlutterGemma.rag.addDocumentWithEmbedding(
    id: docs[i].id,
    content: docs[i].content,
    embedding: embeddings[i],
    metadata: '{"category":"science","lang":"en"}',
  );
}

// 4. Semantic search, with optional payload-aware Filter
final results = await FlutterGemma.rag.searchSimilar(
  query: 'quantum entanglement',
  topK: 10,
  threshold: 0.0,
  filter: Filter(
    must: [FieldEquals(key: 'category', value: 'science')],
    mustNot: [FieldEquals(key: 'lang', value: 'fr')],
  ),
);

// 5. Maintain the store: remove one document (no-op if the id is absent),
//    read stats, or clear everything.
await FlutterGemma.rag.removeDocument(id: 'doc-42');
final stats = await FlutterGemma.rag.stats();
await FlutterGemma.rag.clear();
```

## The Filter API

`Filter` supports `must` / `should` / `mustNot` lists of conditions:

- `FieldEquals` — exact match on a payload field.
- `FieldRange` — numeric range on a payload field.
- `FieldMatchAny` — match against any value in a set.

Both stores honor `Filter` on **all platforms**, and both need the filterable
fields declared up front in a `FilterSchema` (see below). qdrant-edge promotes
exactly the declared fields to payload keys at write time; sqlite-vec creates
them as columns at table-creation time. On either store a filter on an
undeclared field is a no-op — it matches nothing and never throws, so a missing
declaration looks like "no results" rather than an error.

### Declaring filter fields

The sqlite-vec store filters over declared columns. Describe them with a
`FilterSchema` of `FilterField`s, and pass it either to `initialize(...)`:

```dart
await FlutterGemma.initialize(
  vectorStore: SqliteVectorStore(),
  filterSchema: const FilterSchema(fields: [
    FilterField(name: 'category', type: FilterFieldType.string),
    FilterField(name: 'lang', type: FilterFieldType.string),
    FilterField(name: 'year', type: FilterFieldType.number),
  ]),
);
```

…or at runtime via `configure(...)` on the `VectorStoreRepository` — it returns
`void`, so do not `await` it:

```dart
store.configure(FilterSchema(fields: [
  FilterField(name: 'category', type: FilterFieldType.string),
]));
```

`FilterFieldType` has exactly three values: `string`, `number`, `bool`.

What a field may be NAMED is decided by the store, and the two differ — the
check runs in `configure()`, so you find out when you hand the schema over, not
at the first insert.

`SqliteVectorStore` is the strict one: a name must match
`^[A-Za-z][A-Za-z0-9_]*$` and must not be one vec0 already uses (`id`,
`embedding`, `content`, `metadata`, `distance`, `k`). The name becomes a real
`vec0` column and sqlite-vec's DDL grammar has no quoted identifier form, so
`doc-type` is unrepresentable there rather than merely unescaped.

`QdrantVectorStore` accepts far more — payload keys are free-form UTF-8 — with
one rule of its own: no `.`, which qdrant reads as a nested-path separator.

So the portable set is sqlite's. If you may ever switch backends, stay inside
it. Regardless of store, a schema with a duplicate or empty name is rejected.

A `Filter` over the declared fields is then applied inside the store; a filter
referencing an **undeclared** field is silently ignored (no-op, never throws).

<Warning>
Declare a `FilterSchema` on **both** stores. qdrant-edge promotes only the fields
named in the schema to payload keys — an undeclared field is absent from the
payload, so a `Filter` on it matches nothing and the search returns zero hits
rather than an error. The difference between the two stores is not "schema
optional": it is that sqlite-vec needs the schema at table-creation time, while
qdrant promotes at write time.
</Warning>

## Platform support

| Feature | Android | iOS | Web | Desktop |
|---|---|---|---|---|
| Text Embeddings | ✅ | ✅ | ✅ | ✅ |
| VectorStore — qdrant-edge | ✅ | ✅ | ❌ | ✅ |
| VectorStore — sqlite-vec | ✅ | ✅ | ✅ | ✅ |
| Payload `Filter` | ✅ | ✅ | ✅ | ✅ |

Both stores expose the identical Dart API, so you can swap one for the other by
changing only the `vectorStore:` you register.

| | qdrant-edge | sqlite-vec (`vec0`) |
|---|---|---|
| **Platforms** | Native only (Android, iOS, macOS, Linux, Windows) | All six — native **+ Web** |
| **KNN** | HNSW approximate | Exact (brute-force inside SQLite) |
| **Speed** | Fastest native (~5–11× faster search at 1k–10k docs) | Portable, identical results everywhere |
| **When to use** | Native throughput at scale | Web reach, or exact results across every platform |

<Info>
**`sqlite-vec` fetches its native library at build time (1.3.0+).** The
per-platform `vec0` extension comes from this repository's
`native-sqlite-vec-v*` GitHub Release, downloaded and SHA256-verified by the
package's build hook the first time you build for a given platform, then cached
under `~/.cache/flutter_gemma/native/` (`~/Library/Caches/…` on macOS,
`%LOCALAPPDATA%\…` on Windows). So the **first** build of each platform needs
`github.com` reachable; later builds do not. `flutter_gemma_litertlm` has always
worked this way — as of 1.3.0 both packages behave the same.

Before 1.3.0 the loadables were committed into the package, which shipped all
seven platforms' binaries to every consumer to use one of them. If you build in
an air-gapped environment, pre-populate that cache directory, or vendor the
archives and point the build at them.
</Info>

**Which store?** `qdrant-edge` is the fastest **native** option — benchmarked
~5–11× faster search than the `sqlite-vec` store at 1k–10k documents — using HNSW
approximate nearest-neighbour. `sqlite-vec` is exact (brute-force KNN inside
SQLite via the `vec0` extension), portable across all six platforms, and the only
store that runs on Web. Pick qdrant-edge for native throughput; pick sqlite-vec
for exact results or cross-platform / web reach.

Benchmarks comparing the two stores across platforms (EmbeddingGemma 300M,
768-dim) are in the
[repo benchmarks](https://github.com/DenisovAV/flutter_gemma/blob/main/packages/flutter_gemma/example/integration_test/benchmarks/comparison.md).
