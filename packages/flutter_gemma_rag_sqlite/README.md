# flutter_gemma_rag_sqlite

SQLite + HNSW on-device RAG vector store for [flutter_gemma](https://pub.dev/packages/flutter_gemma).
Opt-in package implementing `VectorStoreRepository`:
- **Native** (Android/iOS/macOS/Linux/Windows): `SqliteVectorStore` — `sqlite3` (dart:ffi) + HNSW.
- **Web**: `WebSqliteVectorStore` — wa-sqlite (WASM) + HNSW.

## Usage

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

await FlutterGemma.initialize(
  vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
);
```

## Web setup

On web the wa-sqlite engine is loaded from a `<script>` in your app's
`web/index.html` `<head>` (it exposes the global the package binds to). Pin a
release tag and include the Subresource Integrity hash so a CDN compromise
cannot inject code:

```html
<script type="module"
        src="https://cdn.jsdelivr.net/gh/DenisovAV/flutter_gemma@<tag>/web/sqlite_vector_store.js"
        integrity="sha384-IHmYOhCWsp68Nh9VJD6E6eFk2uLipbclH2+nLjc2GdGQKral9Re53FShwFStJms3"
        crossorigin="anonymous"></script>
```

The worker (`sqlite_vector_store_worker.js`, integrity
`sha384-065e421XLyAFCTrUgXx4D1tSVNDft1/3bbpauywRiVEFaCY0BE6TrkHD2CxNt6R+`) is
fetched by the main script from the same CDN path — no separate tag needed.

> Regenerate a hash after upgrading the JS with:
> `openssl dgst -sha384 -binary web/sqlite_vector_store.js | openssl base64 -A`

Native platforms need no setup — `sqlite3` bundles its own native library.
