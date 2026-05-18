# Vector store benchmarks: qdrant-edge vs legacy Dart HNSW

Apples-to-apples comparison of the two vector store backends shipped by
flutter_gemma:

* **`qdrant`** — `QdrantVectorStoreRepository` (new default in 0.16, FFI
  shim over qdrant-edge 0.6.1)
* **`dart`** — legacy `DartVectorStoreRepository` (sqlite3 +
  `local_hnsw`), `@Deprecated` in 0.16, removal planned in 1.0

Both bench tests use identical inputs:

* EmbeddingGemma 300M, 768-dimensional, seq256 mixed-precision
* 5000 deterministic lorem-ipsum chunks (~360 chars each), shuffled with a
  fixed seed (42) so each run sees the same vectors
* 100 search queries per measurement, p50/p95/p99 in microseconds
* Hardware: Apple M1 mac arm64 / Google Pixel 8 (Android 16, API 36)

The embedding-generation phase (~7 minutes on mac, ~25 minutes on Pixel 8)
is excluded from the numbers — it's the same for both backends.

## macOS m1

| Workload | dart (legacy) | qdrant | speedup |
|---|---:|---:|---:|
| upsert 1k (points/sec) | 91 | **2 991** | **33×** |
| upsert 5k (points/sec) | 15 | **3 886** | **259×** |
| search p50 @ 1k | 3 880 µs | **98 µs** | 40× |
| search p50 @ 5k | 7 519 µs | **286 µs** | 26× |
| search p95 @ 5k | 62 529 µs (62 ms) | **348 µs** | 180× |
| search p99 @ 5k | 66 363 µs (66 ms) | **1 045 µs** | 64× |
| filter p50 @ 5k | — (not supported) | 1 224 µs | n/a |

## Android (Pixel 8)

| Workload | dart (legacy) | qdrant | speedup |
|---|---:|---:|---:|
| upsert 1k (points/sec) | 26 | **1 322** | **51×** |
| upsert 5k (points/sec) | 6 | **1 450** | **242×** |
| search p50 @ 1k | 5 636 µs | **369 µs** | 15× |
| search p50 @ 5k | 19 094 µs (19 ms) | **1 029 µs** | 19× |
| search p95 @ 5k | 99 408 µs (99 ms) | **1 293 µs** | 77× |
| search p99 @ 5k | 122 840 µs (123 ms) | **1 694 µs** | 73× |
| filter p50 @ 5k | — (not supported) | 4 275 µs | n/a |

## Wall-clock impact for typical RAG ingest

5 000-document ingest (one-time setup of a personal knowledge base):

| Backend | macOS m1 | Pixel 8 |
|---|---:|---:|
| dart (legacy) upsert | 5 min 24 s | **14 min 15 s** |
| qdrant upsert | 1.3 s | 3.5 s |

The embedding step itself (EmbeddingGemma generating 5 000 vectors) takes
~7 min on mac and ~25 min on Pixel 8 regardless of backend — it's the
real bottleneck on mobile. But the legacy backend **doubled** the
total wall time on Android (25 min embed + 14 min HNSW rebuild = 39 min)
where qdrant adds essentially nothing (25 min + 3.5 s).

## Search latency interpretation

For a 5 000-document RAG corpus, the p95 latency dictates how often a
user perceives lag during retrieval:

* dart (legacy) on Pixel 8: **p95 = 99 ms** — one in twenty searches has
  noticeable lag on the UI thread.
* qdrant on Pixel 8: **p95 = 1.3 ms** — every search feels instant.

Even on macOS, where dart's p50 looks acceptable (7.5 ms), the p95 of
62 ms shows tail-latency spikes that surface as occasional UI hitches.
qdrant's p95 stays under 0.4 ms.

## Filter overhead (qdrant only)

The legacy backend has no payload-filter support. qdrant filtering with a
single `FieldEquals` predicate adds ~4× the unfiltered p50 latency on
5k points (still under 5 ms on Pixel 8). For typical RAG flows where
filters narrow the candidate set by language / tag / date this is well
within the budget.

## Raw data

* [qdrant_bench_macos.json](qdrant_bench_macos.json)
* [qdrant_bench_android.json](qdrant_bench_android.json)
* [qdrant_bench_dart_macos.json](qdrant_bench_dart_macos.json)
* [qdrant_bench_dart_android.json](qdrant_bench_dart_android.json)
