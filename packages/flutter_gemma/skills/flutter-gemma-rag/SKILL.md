---
name: flutter-gemma-rag
description: Use when building retrieval over on-device documents with flutter_gemma — embeddings via flutter_gemma_embeddings plus a vector store (rag_sqlite or rag_qdrant). Query and document embeddings need DIFFERENT TaskType prefixes or retrieval quality collapses, and embedding is CPU-only by design.
---

# On-device RAG with flutter_gemma

Three pieces: an embedding model, a vector store, and the retrieval call. All
three are opt-in packages.

```dart
await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  embeddingBackends: [LiteRtEmbeddingBackend()],   // flutter_gemma_embeddings
  vectorStore: SqliteVectorStore(),                // flutter_gemma_rag_sqlite
);
```

Without a `vectorStore` the default sentinel throws a clear "add a RAG package"
error on first use. Without an embedding backend, `getActiveEmbedder` throws the
same way.

## Query and document must use DIFFERENT task types

This is the mistake that silently ruins retrieval. Embedding models are trained
asymmetrically: a question and the passage that answers it are encoded with
different prefixes, and using one prefix for both collapses the similarity
signal. Nothing errors — results are just bad.

```dart
// Indexing a document
final docVector = await embedder.generateEmbedding(
  chunk,
  taskType: TaskType.retrievalDocument,
);

// Searching with a question
final queryVector = await embedder.generateEmbedding(
  question,
  taskType: TaskType.retrievalQuery,
);
```

The prefix strings live in one place in Dart and are applied for you — pass the
right `TaskType` and do not prepend anything yourself.

## Embedding is CPU-only, and that is permanent

EmbeddingGemma ships as int4, and the TFLite GPU delegate cannot execute int4.
This is not a missing feature or a bug to work around: there is no GPU path.
Asking for `PreferredBackend.gpu` on an embedder gains nothing.

Budget accordingly — embedding a large corpus on device is minutes of CPU, so
do it in the background, batched, and persist the vectors rather than
recomputing at startup.

## Picking a vector store

| Package | Platforms | Notes |
| --- | --- | --- |
| `flutter_gemma_rag_sqlite` | all six, web included | `sqlite-vec` KNN inside SQLite |
| `flutter_gemma_rag_qdrant` | native only, no web | the official `qdrant_edge` SDK |

`rag_sqlite` on web needs a custom `sqlite3.wasm` with `vec0` linked in — copy
it into the app's own `web/` directory. Nothing does that automatically.

## Filtering

Both stores take the same sealed `Filter` DSL from core, so a query written
against one works against the other:

```dart
final results = await FlutterGemma.rag.search(
  queryVector,
  limit: 5,
  filter: Filter(must: [Condition.equals('lang', 'en')]),
);
```

## Chunking is yours

The package embeds what you give it. Splitting documents, choosing chunk size
and overlap, and storing the text alongside the vector are all application
decisions. A chunk longer than the model's input window is truncated silently —
check the model's limit rather than assuming.

## Do not double-normalise

`meanPoolAndNormalize` accepts only token-level output shaped `[1, seq, dim]`
and deliberately rejects rank-2 input. A model that already returns a pooled,
normalised vector must not be pooled again — doing so distorts every distance in
the index, and the failure is invisible until retrieval quality is measured. If
a rank-2 rejection fires, the model's output contract is pooled-final; wire it
as such rather than reshaping to get past the check.
