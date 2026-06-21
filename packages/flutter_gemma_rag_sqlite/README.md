# flutter_gemma_rag_sqlite

First-class SQLite vector store for [flutter_gemma](https://pub.dev/packages/flutter_gemma).
KNN runs **inside SQLite** via [`sqlite-vec`](https://github.com/asg017/sqlite-vec)
(`vec0` virtual table) — no Dart brute-force, no in-memory index.

Opt-in package implementing `VectorStoreRepository`:
- **Native** (Android/iOS/macOS/Linux/Windows): `SqliteVectorStore` — `package:sqlite3`
  (dart:ffi) + the per-platform `vec0` loadable extension.
- **Web**: `WebSqliteVectorStore` — `package:sqlite3/wasm.dart` driving a custom
  `sqlite3.wasm` with `sqlite-vec`/`vec0` statically linked.

Both arms speak the same `vec0` SQL dialect, so KNN and `Filter` behave
identically across all six platforms. A `vec0` table declares an `id TEXT
PRIMARY KEY`, so KNN returns the document id directly — no JOIN, no rowid bridge.

## Usage

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

await FlutterGemma.initialize(
  vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
);
```

`searchSimilar` returns **cosine similarity** (1 = identical, higher = better),
sorted descending, filtered by `threshold` — the same contract as the qdrant
store (vec0 returns distance; the store converts `1 - distance` at the boundary).

## Declared-column filters

`vec0` filters KNN only on **declared, typed metadata columns** (not arbitrary
JSON). Declare the filterable fields once at init via `filterSchema:`; the store
promotes those fields out of each document's metadata JSON into real columns and
translates `Filter` (`must`/`should`/`mustNot`) into a vec0 `WHERE`:

```dart
await FlutterGemma.initialize(
  vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
  filterSchema: const FilterSchema(fields: [
    FilterField(name: 'lang', type: FilterFieldType.string),
    FilterField(name: 'year', type: FilterFieldType.number),
    FilterField(name: 'archived', type: FilterFieldType.bool),
  ]),
);

// later, at query time:
final hits = await store.searchSimilar(
  queryEmbedding: queryVec,
  topK: 10,
  filter: const Filter(
    must:    [FieldRange(key: 'year', gte: 2000)],
    mustNot: [FieldEquals(key: 'archived', value: true)],
  ),
);
```

Filtering on an **undeclared** key is a safe no-op (never throws). With no
`filterSchema`, the store ignores filters entirely — identical to `filter: null`.
Supported operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `BETWEEN`, `IN`
(`FieldEquals`, `FieldRange`, `FieldMatchAny`); max 16 declared columns.

## Setup

**Native** needs no setup — the `vec0` loadable extension is fetched per platform
by this package's Native Assets hook (`hook/build.dart`), SHA256-verified, and
loaded automatically before any database is opened.

**Web** ships the custom `sqlite3.wasm` (with `sqlite-vec` linked in) as the
package web asset `web/rag/sqlite3.wasm`. Copy it into your app's web root so it
sits next to `index.html` at `rag/sqlite3.wasm` — that's the URL
`WasmSqlite3.loadFromUrl` fetches. Resolve the package directory with
`dart pub deps`/`flutter pub` (the path printed by your IDE) and copy the asset:

```sh
mkdir -p web/rag
# <pkg> = the flutter_gemma_rag_sqlite directory in your pub cache / workspace
cp <pkg>/web/rag/sqlite3.wasm web/rag/sqlite3.wasm
```

OPFS persistence and `SharedArrayBuffer` require your web server to send the
cross-origin isolation headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

There is no CDN `<script>`, no wa-sqlite worker, and no `index.html` wiring
anymore.
