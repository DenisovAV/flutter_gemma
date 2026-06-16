## 1.0.0
- Stable 1.0.0.
- Rebuild Android `.so` with 16KB page alignment for Android 15 / Play target SDK 35+ (#319; native tag qdrant-edge-v0.7.3).

## 1.0.0-rc.1
- Initial release: qdrant-edge on-device RAG vector store for flutter_gemma (native FFI; ~75× faster search than sqlite).
- Provides `QdrantVectorStore`; implements VectorStoreRepository. Honors the payload-aware `Filter` DSL.
- Native platforms only (Android, iOS, macOS, Linux, Windows); no web (use flutter_gemma_rag_sqlite).
