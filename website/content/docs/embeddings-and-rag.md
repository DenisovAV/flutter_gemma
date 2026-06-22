---
title: Embeddings & RAG
description: Generate text embeddings and run on-device retrieval-augmented generation (RAG) with a payload-aware Filter API.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma can generate vector embeddings from text (EmbeddingGemma / Gecko)
and run on-device RAG with a vector store. Two stores are available, both with
the same Dart API: **qdrant-edge** — the fastest store on native (HNSW
approximate nearest-neighbour) — and **sqlite-vec** — a portable, exact store
that runs on **all six platforms (Android, iOS, macOS, Linux, Windows, Web)**,
and the only store that runs on Web. Your code is portable across both.

## Setup

Embeddings need the `flutter_gemma_embeddings` package, and RAG needs a vector
store package — `flutter_gemma_rag_qdrant` (native, fastest) or
`flutter_gemma_rag_sqlite` (sqlite-vec; all platforms, including Web). Register
them in `FlutterGemma.initialize(...)`:

```dart
FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine()],
  embeddingBackends: const [LiteRtEmbeddingBackend()], // flutter_gemma_embeddings
  vectorStore: QdrantVectorStore(),                    // or WebSqliteVectorStore() on web
);
```

See [Installation](/docs/installation) for the full registration reference.

## Text embeddings

All embedding models generate **768-dimensional vectors**. The number in a model
name (64/256/512/1024/2048) is the max input sequence length in tokens, not the
embedding dimension. See [Models](/docs/models#text-embedding-models) for the full
list.

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
final embedder = FlutterGemmaPlugin.instance.initializedEmbeddingModel!;
final embeddings = await embedder.generateEmbeddings(
  docs.map((d) => d.content).toList(),
  taskType: TaskType.retrievalDocument,
);
```

<Info>
Embedding currently runs on **CPU only**. EmbeddingGemma is an int4 `.tflite`
model, and the TFLite GPU delegate cannot run int4 — so GPU embedding is not
possible for this model format. Embedding runs on a background isolate so it
doesn't block the UI thread.
</Info>

## On-device RAG / vector store

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// 1. Install an embedding model (any of Gecko / EmbeddingGemma) — see above.

// 2. Initialize the vector store (one shard per database path)
await FlutterGemmaPlugin.instance.initializeVectorStore('rag_store');

// 3. Add documents — let the plugin compute embeddings for you
for (final doc in docs) {
  await FlutterGemmaPlugin.instance.addDocument(
    id: doc.id,
    content: doc.content,
    metadata: '{"category":"science","lang":"en"}',
  );
}

// 3b. Or batch-embed yourself and feed pre-computed vectors via
//     addDocumentWithEmbedding(...) for higher throughput.
final embedder = FlutterGemmaPlugin.instance.initializedEmbeddingModel!;
final embeddings = await embedder.generateEmbeddings(
  docs.map((d) => d.content).toList(),
  taskType: TaskType.retrievalDocument,
);
for (var i = 0; i < docs.length; i++) {
  await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: docs[i].id,
    content: docs[i].content,
    embedding: embeddings[i],
    metadata: '{"category":"science","lang":"en"}',
  );
}

// 4. Semantic search, with optional payload-aware Filter
final results = await FlutterGemmaPlugin.instance.searchSimilar(
  query: 'quantum entanglement',
  topK: 10,
  threshold: 0.0,
  filter: Filter(
    must: [FieldEquals(key: 'category', value: 'science')],
    mustNot: [FieldEquals(key: 'lang', value: 'fr')],
  ),
);
```

## The Filter API

`Filter` supports `must` / `should` / `mustNot` lists of conditions:

- `FieldEquals` — exact match on a payload field.
- `FieldRange` — numeric range on a payload field.
- `FieldMatchAny` — match against any value in a set.

Both stores honor `Filter` on **all platforms**. On qdrant-edge the metadata
fields are promoted to payload keys automatically. On sqlite-vec the filterable
fields must be **declared up front** as columns (see below); a filter on an
undeclared field is a no-op — it never throws.

### Declaring filter columns (sqlite-vec)

The sqlite-vec store filters over declared columns. Describe them with a
`FilterSchema` of `FilterField`s, and pass it either to `initialize(...)`:

```dart
FlutterGemma.initialize(
  vectorStore: SqliteVectorStore(),
  filterSchema: const FilterSchema([
    FilterField('category', FilterFieldType.text),
    FilterField('lang', FilterFieldType.text),
    FilterField('year', FilterFieldType.integer),
  ]),
);
```

…or at runtime via `configure(...)` on the `VectorStoreRepository`:

```dart
await store.configure(const FilterSchema([
  FilterField('category', FilterFieldType.text),
]));
```

A `Filter` over the declared fields is then applied inside the store; a filter
referencing an **undeclared** field is silently ignored (no-op, never throws).
`FilterSchema` is optional on qdrant-edge, which promotes any metadata field to a
payload key automatically.

## Platform support

| Feature | Android | iOS | Web | Desktop |
|---|---|---|---|---|
| Text Embeddings | ✅ | ✅ | ✅ | ✅ |
| VectorStore — qdrant-edge | ✅ | ✅ | ❌ | ✅ |
| VectorStore — sqlite-vec | ✅ | ✅ | ✅ | ✅ |
| Payload `Filter` | ✅ | ✅ | ✅ | ✅ |

Both stores expose the identical Dart API, so you can swap one for the other by
changing only the `vectorStore:` you register.

**Which store?** `qdrant-edge` is the fastest **native** option — benchmarked
~5–11× faster search than the `sqlite-vec` store at 1k–10k documents — using HNSW
approximate nearest-neighbour. `sqlite-vec` is exact (brute-force KNN inside
SQLite via the `vec0` extension), portable across all six platforms, and the only
store that runs on Web. Pick qdrant-edge for native throughput; pick sqlite-vec
for exact results or cross-platform / web reach.

Benchmarks comparing the two stores across platforms (EmbeddingGemma 300M,
768-dim) are in the
[repo benchmarks](https://github.com/DenisovAV/flutter_gemma/blob/main/packages/flutter_gemma/example/integration_test/benchmarks/comparison.md).
