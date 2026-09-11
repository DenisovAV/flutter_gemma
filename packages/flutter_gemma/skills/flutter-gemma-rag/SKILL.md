---
name: flutter-gemma-rag
description: Use when adding RAG, semantic search or text embeddings to a flutter_gemma app — searching the user's documents on-device, an embedding model plus a vector store (flutter_gemma_rag_sqlite or flutter_gemma_rag_qdrant). Also use when a metadata filter returns unfiltered results, retrieval quality is poor, addDocument throws about a missing embedding model, or the vector store throws UnimplementedError on web.
---

# On-device RAG with flutter_gemma

## Rules

1. Use the `FlutterGemma.rag` facade: `initialize`, `addDocument`, `searchSimilar`. It embeds documents and queries with the correct task types for you.
2. Declare every field you will filter on in `filterSchema:` at `initialize`. A filter on an undeclared field — or any filter with no schema — is silently ignored and returns unfiltered results.
3. Activate an embedding model with `getActiveEmbedder()` before `addDocument`.
4. `LiteRtEmbeddingBackend` comes from `flutter_gemma_litertlm`, not `flutter_gemma_embeddings`.
5. On web use `WebSqliteVectorStore`; `SqliteVectorStore` throws `UnimplementedError` there. `flutter_gemma_rag_qdrant` is native-only.
6. Android needs `minSdk 30`.

## Setup

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
  embeddingBackends: [LiteRtEmbeddingBackend()],
  vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
  filterSchema: const FilterSchema(fields: [
    FilterField(name: 'lang', type: FilterFieldType.string),
    FilterField(name: 'year', type: FilterFieldType.number),
  ]),
);

await FlutterGemma.installEmbedder()
    .modelFromNetwork(url)
    .tokenizerFromNetwork(url)
    .install();
await FlutterGemma.getActiveEmbedder();

await FlutterGemma.rag.initialize('rag.db');
```

`rag.initialize` takes a database file for sqlite and a directory for qdrant.

## Index and search

```dart
import 'dart:convert';

await FlutterGemma.rag.addDocument(
  id: 'doc-1',
  content: chunk,
  metadata: jsonEncode({'lang': 'en', 'year': 2024}),
);

final hits = await FlutterGemma.rag.searchSimilar(
  query: question,
  topK: 5,
  filter: const Filter(
    must: [FieldEquals(key: 'lang', value: 'en')],
    mustNot: [FieldRange(key: 'year', lte: 2010)],
  ),
);
for (final hit in hits) {
  print('${hit.similarity.toStringAsFixed(2)} ${hit.content}');
}
```

`searchSimilar` takes the question as text and embeds it itself. Filter operators: `FieldEquals`, `FieldRange` (`gte`, `lte`), `FieldMatchAny`, combined with `must`, `should` and `mustNot`.

## Traps

**Filter has no effect**
- Symptom: results ignore the filter; no error.
- Fix: declare the field in `filterSchema`. Names must match `^[A-Za-z][A-Za-z0-9_]*$` and cannot be `id`, `embedding`, `content`, `metadata`, `distance` or `k`. At most 16 fields.

**Poor retrieval after embedding by hand**
- Query and document embeddings are trained asymmetrically. `generateEmbedding` defaults to `TaskType.retrievalQuery`, so text embedded for indexing without a task type gets the query prefix.
- Fix: pass `TaskType.retrievalDocument` when indexing yourself:

```dart
final vector = await embedder.generateEmbedding(
  chunk,
  taskType: TaskType.retrievalDocument,
);
await FlutterGemma.rag.addDocumentWithEmbedding(
  id: 'doc-2',
  content: chunk,
  embedding: vector,
);
```

**`addDocument` throws**
- Cause: no active embedding model. Call `FlutterGemma.getActiveEmbedder()` after installing one.

## Backend

Leave the embedder on the default CPU backend. The GPU delegate does not produce valid vectors for EmbeddingGemma.

## Web

- Copy `web/rag/sqlite3.wasm` from the `flutter_gemma_rag_sqlite` package into the app as `web/rag/sqlite3.wasm`.
- Web embeddings need `litert_embeddings.js` and `sentencepiece.js` from the `flutter_gemma_embeddings` package's `web/` directory, copied into the app's `web/`, plus `<script type="module" src="litert_embeddings.js"></script>` in `web/index.html`.

Find a package's directory with `grep -A1 '"name": "flutter_gemma_rag_sqlite"' .dart_tool/package_config.json`.

## Chunking

Splitting documents, chunk size and overlap are yours to decide. A chunk longer than the embedding model's input window is truncated without an error.
