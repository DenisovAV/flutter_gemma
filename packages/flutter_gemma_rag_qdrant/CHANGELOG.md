## 1.1.0
- Fix metadata filtering: declared `FilterSchema` fields are promoted to top-level payload keys, so `Filter` predicates actually match (previously narrowed to zero).
- Implement `configure(FilterSchema)`; requires `flutter_gemma ^1.1.0`.
- Correct the "~75×" search-speed claim to the re-measured ~5–11× vs the new in-SQLite vec0 store (was vs the deleted Dart brute-force path).

## 1.0.1
- Point `homepage` to fluttergemma.dev. No code change.

## 1.0.0
- Stable 1.0.0.
- Rebuild Android `.so` with 16KB page alignment for Android 15 / Play target SDK 35+ (#319; native tag qdrant-edge-v0.7.3).

## 1.0.0-rc.1
- Initial release: qdrant-edge on-device RAG vector store for flutter_gemma (native FFI; ~75× faster search than the legacy Dart brute-force sqlite store).
- Provides `QdrantVectorStore`; implements VectorStoreRepository. Honors the payload-aware `Filter` DSL.
- Native platforms only (Android, iOS, macOS, Linux, Windows); no web (use flutter_gemma_rag_sqlite).
