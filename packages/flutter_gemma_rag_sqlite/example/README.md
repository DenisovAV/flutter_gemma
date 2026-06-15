# flutter_gemma_rag_sqlite example

`flutter_gemma_rag_sqlite` is an opt-in vector store for
[`flutter_gemma`](https://pub.dev/packages/flutter_gemma) that works on every
platform: native (`sqlite3` + HNSW via dart:ffi) and web (wa-sqlite WASM).
Register it once at startup, then use the unchanged RAG API on
`FlutterGemmaPlugin.instance`.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Native uses SqliteVectorStore; web uses WebSqliteVectorStore.
  await FlutterGemma.initialize(
    vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
  );

  final gemma = FlutterGemmaPlugin.instance;

  await gemma.initializeVectorStore('rag_store.db');

  // Add a document with a pre-computed embedding (e.g. from
  // flutter_gemma_embeddings).
  await gemma.addDocumentWithEmbedding(
    id: 'doc-1',
    content: 'Gemma runs fully on-device.',
    embedding: List<double>.filled(768, 0.0), // your real embedding here
    metadata: '{"lang":"en"}',
  );

  final hits = await gemma.searchSimilar(query: 'on-device LLM', topK: 5);
  for (final h in hits) {
    print('${h.id}: ${h.content} (score ${h.similarity})');
  }
}
```

On web, load the wa-sqlite engine from a `<script>` in `web/index.html` — see
the [package README](https://pub.dev/packages/flutter_gemma_rag_sqlite) for the
SRI-pinned tag setup. Native platforms need no setup (`sqlite3` bundles its own
library). A full runnable app wiring every engine and RAG store together lives
in the
[`flutter_gemma` example](https://github.com/DenisovAV/flutter_gemma/tree/main/packages/flutter_gemma/example).
