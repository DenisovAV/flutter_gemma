// Qdrant Edge FFI shim — C header.
//
// Companion to native/qdrant_edge/qdrant_edge_ffi/src/lib.rs. This header is
// the contract between the Rust cdylib and Dart FFI bindings generated via
// `dart run ffigen --config ffigen_qdrant_edge.yaml`. Edit both in lockstep
// when adding or changing functions.
//
// All `qe_*` exported functions are documented at the Rust side; this header
// only declares signatures. Memory ownership:
//
//   - Strings returned via `*mut *mut char` out-parameters (error_out,
//     response_json_out) are heap-allocated C strings owned by the caller.
//     Always free via `qe_string_free`.
//   - The shard handle (`void*`) is opaque. Close via `qe_shard_close` to
//     release all resources.
//   - Vector inputs (`const float*` + length) are borrowed; no ownership
//     transfer to the shim.

#ifndef QDRANT_EDGE_H
#define QDRANT_EDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Version
// ---------------------------------------------------------------------------

/// Returns shim version string. Caller must free with `qe_string_free`.
char *qe_version(void);

// ---------------------------------------------------------------------------
// Shard lifecycle
// ---------------------------------------------------------------------------

/// Open or create a shard at `path` with the given vector dimension and
/// distance metric.
///
/// `distance` is one of "cosine", "dot", "euclid", "manhattan"
/// (case-insensitive).
///
/// Returns an opaque shard handle on success, NULL on failure with details
/// written to `*error_out` (caller frees via `qe_string_free`).
void *qe_shard_open(const char *path,
                    uint32_t dim,
                    const char *distance,
                    char **error_out);

/// Close shard. Frees all resources. Safe to call with NULL.
void qe_shard_close(void *shard);

// ---------------------------------------------------------------------------
// Upsert (single + batch)
// ---------------------------------------------------------------------------

/// Upsert a single point.
///
/// `payload_json` may be NULL (no payload) or a valid JSON object string.
///
/// Returns 0 on success, -1 on error (with details in `*error_out`).
int32_t qe_shard_upsert(void *shard,
                        const char *id,
                        const float *vector,
                        size_t vector_len,
                        const char *payload_json,
                        char **error_out);

/// Bulk upsert. `points_json` is a JSON array of
/// `{"id": "<id>", "vector": [f32...], "payload": {...} | null}` objects.
///
/// Returns 0 on success, -1 on error.
int32_t qe_shard_upsert_batch(void *shard,
                              const char *points_json,
                              char **error_out);

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// Top-K nearest-neighbor search.
///
/// On success, writes a JSON array of `{"id", "score", "payload"}` results
/// to `*response_json_out` (caller frees via `qe_string_free`).
///
/// Returns 0 on success, -1 on error.
int32_t qe_shard_search(void *shard,
                        const float *vector,
                        size_t vector_len,
                        uint32_t top_k,
                        char **response_json_out,
                        char **error_out);

/// Top-K search with a qdrant-edge filter.
///
/// `filter_json` is the JSON-encoded `Filter { must, should, must_not }`
/// envelope. Pass NULL to omit (equivalent to `qe_shard_search`).
int32_t qe_shard_search_with_filter(void *shard,
                                    const float *vector,
                                    size_t vector_len,
                                    uint32_t top_k,
                                    const char *filter_json,
                                    char **response_json_out,
                                    char **error_out);

// ---------------------------------------------------------------------------
// Delete + count
// ---------------------------------------------------------------------------

/// Delete points by IDs. `ids_json` is a JSON array of strings.
int32_t qe_shard_delete(void *shard,
                        const char *ids_json,
                        char **error_out);

/// Exact total point count. Returns count >= 0 on success, -1 on error.
int64_t qe_shard_count(void *shard, char **error_out);

// ---------------------------------------------------------------------------
// Memory management
// ---------------------------------------------------------------------------

/// Free any string returned by the shim through a `char **` out-parameter
/// or the `char *` return of `qe_version`. Safe to call with NULL.
void qe_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif  // QDRANT_EDGE_H
