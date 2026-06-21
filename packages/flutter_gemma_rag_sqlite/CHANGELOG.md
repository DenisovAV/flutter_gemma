## 1.1.0
- In-SQLite KNN on `sqlite-vec`/`vec0` (native + web); removed Dart brute-force and HNSW.
- Declared-column `Filter` (must/should/mustNot) via `configure(FilterSchema)`; undeclared keys no-op.
- Web rewritten on `package:sqlite3/wasm.dart` + custom `sqlite3.wasm`; wa-sqlite worker dropped.
- `vec0` loadable bundled per-platform via Native Assets hook; `enableHnsw` is now a deprecated no-op.

## 1.0.1
- Point `homepage` to fluttergemma.dev. No code change.

## 1.0.0
- Stable 1.0.0; RAG logging routed through `gemmaLog` (silent in release builds).

## 1.0.0-rc.1
- Initial release: SQLite + HNSW on-device RAG vector store for flutter_gemma.
- Provides `SqliteVectorStore` (native, sqlite3) and `WebSqliteVectorStore` (web, wa-sqlite); implements VectorStoreRepository.
- All platforms (native sqlite3 + web wa-sqlite).
