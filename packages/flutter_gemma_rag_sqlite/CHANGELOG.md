## 1.0.0
- Stable 1.0.0; RAG logging routed through `gemmaLog` (silent in release builds).

## 1.0.0-rc.1
- Initial release: SQLite + HNSW on-device RAG vector store for flutter_gemma.
- Provides `SqliteVectorStore` (native, sqlite3) and `WebSqliteVectorStore` (web, wa-sqlite); implements VectorStoreRepository.
- All platforms (native sqlite3 + web wa-sqlite).
