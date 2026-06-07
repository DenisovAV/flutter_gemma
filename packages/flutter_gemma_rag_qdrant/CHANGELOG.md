## 1.0.0-rc.1
- Initial release: qdrant-edge on-device RAG vector store for flutter_gemma (native FFI; ~75× faster search than sqlite).
- Provides `QdrantVectorStore`; implements VectorStoreRepository. Honors the payload-aware `Filter` DSL.
- Native platforms only (Android, iOS, macOS, Linux, Windows); no web (use flutter_gemma_rag_sqlite).
