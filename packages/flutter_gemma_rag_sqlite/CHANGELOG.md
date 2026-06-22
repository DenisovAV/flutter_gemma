## 1.1.0
- Un-deprecated: first-class on-device vector store on all 6 platforms with in-SQLite KNN via `sqlite-vec`/`vec0`; removed Dart brute-force + HNSW.
- Declared-column `Filter` (must/should/mustNot) via `configure(FilterSchema)`; undeclared keys no-op. Requires `flutter_gemma ^1.1.0`.
- Web rewritten on `package:sqlite3/wasm.dart` + a custom `sqlite3.wasm` (vec0 statically linked); wa-sqlite worker dropped.
- Per-platform `vec0` loadable bundled in-package via Native Assets; Android `.so` rebuilt 16 KB-aligned for Android 15 / Play targetSdk 35+ (#319).
- `enableHnsw` is now a deprecated no-op (search runs in SQLite).

## 1.0.1
- Point `homepage` to fluttergemma.dev. No code change.

## 1.0.0
- Stable 1.0.0; RAG logging routed through `gemmaLog` (silent in release builds).

## 1.0.0-rc.1
- Initial release: SQLite + HNSW on-device RAG vector store for flutter_gemma.
- Provides `SqliteVectorStore` (native, sqlite3) and `WebSqliteVectorStore` (web, wa-sqlite); implements VectorStoreRepository.
- All platforms (native sqlite3 + web wa-sqlite).
