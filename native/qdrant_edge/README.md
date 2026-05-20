# Qdrant Edge native shim

C-FFI shim over [`qdrant-edge = 0.6.1`](https://crates.io/crates/qdrant-edge)
(crates.io). Backs `QdrantVectorStoreRepository` on native platforms (Android,
iOS, macOS, Linux, Windows).

## Layout

```
native/qdrant_edge/
├── README.md                    # this file
└── qdrant_edge_ffi/
    ├── Cargo.toml               # depends on qdrant-edge = "=0.6.1"
    ├── .gitignore
    └── src/
        └── lib.rs               # extern "C" surface
```

## Build (local, host platform only)

Requires Rust ≥ 1.85 (edition 2024). Homebrew Rust 1.94+ works. No `rustup`
required for host build.

```bash
cd native/qdrant_edge/qdrant_edge_ffi
cargo build --release
# → target/release/libqdrant_edge_ffi.{dylib,so,dll}
```

Cold build is ~4-5 minutes (heavy dep tree from qdrant-edge: ~720 transitive
crates). Warm rebuild is <2 minutes.

## Cross-compile (production, all 9 targets)

CI workflow `.github/workflows/qdrant-edge-build.yml` builds for:

- macOS arm64, macOS x86_64
- iOS arm64 (device), iOS arm64 (simulator)
- Android arm64, Android x86_64 (no armv7 — upstream `bitm` crate doesn't
  support 32-bit; Android v7 deprecated for flutter_gemma anyway)
- Linux x86_64, Linux arm64
- Windows x86_64

Outputs are uploaded to GitHub Release `qdrant-edge-vN.M.K`. SHA256 checksums
are pinned in `hook/build.dart` so consumers get verified prebuilts.

## Public API

See `src/lib.rs` for the full set. Core surface:

| Function | Purpose |
|---|---|
| `qe_version()` | Returns shim version string |
| `qe_shard_open(path, dim, distance, error)` | Open or create a shard. `distance` is `"cosine" \| "dot" \| "euclid" \| "manhattan"` |
| `qe_shard_upsert(shard, id, vec, len, payload_json, error)` | Upsert single point |
| `qe_shard_upsert_batch(shard, points_json, error)` | Bulk upsert (JSON array) |
| `qe_shard_search(shard, vec, len, top_k, response, error)` | Top-K nearest |
| `qe_shard_search_with_filter(shard, vec, len, top_k, filter_json, response, error)` | Top-K with Qdrant `Filter` (must/should/must_not) |
| `qe_shard_delete(shard, ids_json, error)` | Delete by IDs |
| `qe_shard_count(shard, error)` | Exact count |
| `qe_shard_close(shard)` | Drop shard |
| `qe_string_free(s)` | Free any string returned by `qe_*` |

## ID handling

`qdrant-edge` requires `PointId::NumId(u64)` or `PointId::Uuid`. Arbitrary
strings are not supported. The shim accepts any string and uses
`ExtendedPointId::FromStr` to parse it:

- `"42"` → `NumId(42)`
- `"6ba7b810-9dad-11d1-80b4-00c04fd430c8"` → `Uuid(...)`
- everything else → error

The Dart-side wrapper (`QdrantVectorStoreRepository`) hashes user-provided
arbitrary strings into UUIDv5 under a fixed namespace, so users can keep
passing `String id` to `addDocument(...)` as before.

## Memory model

- Strings returned by `qe_*` are heap-allocated C strings owned by the caller
  (Dart side). Always free via `qe_string_free`.
- Shard handle is opaque `*mut c_void`. Always close via `qe_shard_close`.
- Vector inputs are borrowed `*const f32 + length`, no ownership transfer.
