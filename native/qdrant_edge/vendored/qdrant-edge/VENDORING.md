# Vendored qdrant-edge

**TEMPORARY** vendored copy of the `qdrant-edge` Rust crate, exposing the
`EdgeShard::load_with_wal_options` public API.

## Why this exists

`qdrant-edge 0.6.1` on crates.io does not expose WAL configuration, which
forces all consumers to use the default 32 MiB segment capacity. On
embedded/mobile (flutter_gemma's target) that means a freshly-opened empty
shard pre-allocates 64 MiB on disk. We need 4 MiB segments → 8 MiB total.

Upstream tracking PR: https://github.com/qdrant/qdrant/pull/9067

## How this was produced

The `qdrant-edge` crate on crates.io is not a single repository — it is the
amalgamation of 9 workspace crates (`common`, `edge`, `gridstore`,
`posting_list`, `quantization`, `segment`, `shard`, `sparse`, `wal`), produced
by `lib/edge/publish/amalgamate.py` in `qdrant/qdrant`. To get a buildable
crate with our `load_with_wal_options` patch:

```bash
# In a clone of DenisovAV/qdrant, on branch flutter-gemma-wal-options:
uv run lib/edge/publish/amalgamate.py
# → produces lib/edge/publish/qdrant-edge/ — that is what was copied here.
```

The patched method lives in `src/edge/mod.rs`. Pure Rust, no behavior change
for existing callers — `EdgeShard::load(...)` keeps its prior semantics.

## How to remove this

Once upstream PR #9067 is merged and qdrant-edge is published to crates.io
with the public API:

1. Delete this entire directory: `native/qdrant_edge/vendored/`
2. Bump the dependency in `../qdrant_edge_ffi/Cargo.toml`:
   ```toml
   qdrant-edge = "=0.6.2"  # or whichever version contains the patch
   ```
3. Remove the `[patch.crates-io]` block from `../qdrant_edge_ffi/Cargo.toml`.

That's it. No data migration, no API changes — the FFI shim continues to
work because it already calls `load_with_wal_options`, which is now in the
stock crate.

## How to refresh this

If upstream qdrant-edge gains an important fix while we're still waiting on
PR #9067, rebase our `flutter-gemma-wal-options` branch onto the latest
upstream `dev`, re-run `amalgamate.py`, then re-`rsync` the output here:

```bash
rsync -a --delete \
  /path/to/qdrant/lib/edge/publish/qdrant-edge/ \
  /path/to/flutter_gemma/native/qdrant_edge/vendored/qdrant-edge/
```
