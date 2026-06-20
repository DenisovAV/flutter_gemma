---
title: Embeddings & RAG
description: Generate text embeddings and run on-device retrieval-augmented generation (RAG) with a payload-aware Filter API.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma can generate vector embeddings from text (EmbeddingGemma / Gecko)
and run on-device RAG with a vector store: **qdrant-edge** on native, **wa-sqlite**
on Web. The same Dart API works on both, so your code is portable across
platforms.

## Setup

Embeddings need the `flutter_gemma_embeddings` package, and RAG needs a vector
store package — `flutter_gemma_rag_qdrant` (native) or `flutter_gemma_rag_sqlite`
(web). Register them in `FlutterGemma.initialize(...)`:

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

// 4. Semantic search, with optional payload-aware Filter (native only)
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

<Warning>
On **Web**, the `filter` argument is silently ignored — wa-sqlite has no
payload-filter support. Payload-aware `Filter` is native-only (qdrant-edge).
</Warning>

## Platform support

| Feature | Android | iOS | Web | Desktop |
|---|---|---|---|---|
| Text Embeddings | ✅ | ✅ | ✅ | ✅ |
| VectorStore (RAG) | ✅ qdrant-edge | ✅ qdrant-edge | ✅ wa-sqlite (WASM) | ✅ qdrant-edge |
| Payload `Filter` | ✅ | ✅ | ❌ | ✅ |

Benchmarks comparing qdrant-edge to the legacy sqlite + local_hnsw backend across
5 platforms (5,000 documents, EmbeddingGemma 300M, 768-dim) are in the
[repo benchmarks](https://github.com/DenisovAV/flutter_gemma/blob/main/packages/flutter_gemma/example/integration_test/benchmarks/comparison.md).
