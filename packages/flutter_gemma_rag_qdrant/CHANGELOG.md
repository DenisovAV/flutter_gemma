## 2.0.0
- **Breaking:** move from the hand-rolled C-ABI shim (`native/qdrant_edge/`, ffigen bindings, Native Assets `hook/build.dart`) onto the official `qdrant_edge` UniFFI Dart SDK (pinned `0.8.0-dev.1`). The native binary is now provisioned by the `qdrant_edge` SDK's own Native Assets hook; the supported-platform set changed accordingly.
- **Breaking:** an on-disk store written by 1.x (crate 0.7.x) may not reopen under this release — clear it and re-index.
- `VectorStoreRepository` contract and on-disk payload keys are unchanged; `Filter`/`FilterSchema` behavior is unchanged.

## 1.2.0
- Encode filters by the declared field type, so both backends answer alike.
- **Breaking:** reject a field name containing `.` — qdrant reads it as a nested path.
- Fix numeric equality never matching a float payload (`4` vs `4.0`).
- Fix an unbounded `FieldRange` excluding every non-numeric document instead of matching all.

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
