//! Production C-FFI shim over qdrant-edge 0.6.1.
//!
//! API surface:
//!   open / upsert / upsert_batch / search / search_with_filter /
//!   delete / clear / count / optimize / close / version
//!
//! Memory model:
//!   - Strings out (version, errors, JSON results) are heap-allocated
//!     C strings; caller MUST free via `qe_string_free`.
//!   - Shard handle is opaque `*mut c_void` over `Box<EdgeShard>`;
//!     caller MUST close via `qe_shard_close`.
//!   - Vector inputs are `*const f32 + length`, no ownership transfer.
//!
//! ID handling:
//!   - PointId comes in as a C string. qdrant-edge `ExtendedPointId::FromStr`
//!     parses it: pure-numeric → NumId(u64), UUID → Uuid, otherwise error.
//!   - Dart side wraps user String IDs into UUIDv5 (deterministic hash) before
//!     passing — see `lib/core/infrastructure/qdrant_vector_store_repository.dart`.

use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::Path;
use std::ptr;
use std::slice;
use std::str::FromStr;

use std::num::NonZero;

use qdrant_edge::external::serde_json;
use qdrant_edge::{
    CountRequest, DEFAULT_VECTOR_NAME, Distance, EdgeConfig, EdgeShard, EdgeVectorParams, Filter,
    NamedQuery, PointId, PointInsertOperations, PointOperations, PointStruct, QueryEnum,
    SearchRequest, UpdateOperation, WalOptions, WithPayloadInterface, WithVector,
};

/// WAL segment capacity for embedded/mobile deployments.
///
/// qdrant-edge defaults to 32 MiB which is a server-friendly number. The WAL
/// pre-allocates each segment to its full capacity on disk (not sparse —
/// real allocated blocks on APFS/ext4/NTFS), so on a freshly-opened empty
/// shard the WAL alone consumes 64 MiB (2 segments × 32 MiB). 4 MiB reduces
/// that to 8 MiB on disk while still leaving enough headroom for any
/// reasonable single batch upsert.
const FLUTTER_GEMMA_WAL_SEGMENT_CAPACITY: usize = 4 * 1024 * 1024;

fn flutter_gemma_wal_options() -> WalOptions {
    WalOptions {
        segment_capacity: FLUTTER_GEMMA_WAL_SEGMENT_CAPACITY,
        segment_queue_len: 0,
        retain_closed: NonZero::new(1).expect("1 is non-zero"),
    }
}

// ====================================================================
// Helpers
// ====================================================================

fn cstring_into_raw(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

unsafe fn write_error(error_out: *mut *mut c_char, msg: impl ToString) {
    if !error_out.is_null() {
        unsafe { *error_out = cstring_into_raw(msg.to_string()) };
    }
}

unsafe fn cstr_to_str<'a>(p: *const c_char) -> Result<&'a str, &'static str> {
    if p.is_null() {
        return Err("null C string");
    }
    unsafe { CStr::from_ptr(p).to_str().map_err(|_| "invalid utf-8") }
}

unsafe fn shard_ref<'a>(shard: *mut c_void) -> Option<&'a EdgeShard> {
    if shard.is_null() {
        return None;
    }
    Some(unsafe { &*(shard as *const EdgeShard) })
}

fn parse_point_id(s: &str) -> Result<PointId, String> {
    PointId::from_str(s).map_err(|_| {
        format!(
            "id must be u64 or UUID; got '{s}' \
             (Dart side should hash arbitrary strings via UUIDv5)"
        )
    })
}

fn point_id_to_json(id: &PointId) -> serde_json::Value {
    match id {
        PointId::NumId(n) => serde_json::Value::Number((*n).into()),
        PointId::Uuid(u) => serde_json::Value::String(u.to_string()),
    }
}

fn distance_from_str(s: &str) -> Result<Distance, String> {
    match s.to_ascii_lowercase().as_str() {
        "cosine" => Ok(Distance::Cosine),
        "dot" => Ok(Distance::Dot),
        "euclid" | "euclidean" => Ok(Distance::Euclid),
        "manhattan" => Ok(Distance::Manhattan),
        other => Err(format!("unknown distance: {other}")),
    }
}

fn build_edge_config(dim: u32, distance: Distance) -> EdgeConfig {
    EdgeConfig {
        on_disk_payload: false,
        vectors: HashMap::from([(
            DEFAULT_VECTOR_NAME.to_string(),
            EdgeVectorParams {
                size: dim as usize,
                distance,
                quantization_config: None,
                multivector_config: None,
                datatype: None,
                on_disk: None,
                hnsw_config: None,
            },
        )]),
        sparse_vectors: HashMap::new(),
        hnsw_config: Default::default(),
        quantization_config: None,
        optimizers: Default::default(),
    }
}

// ====================================================================
// Version
// ====================================================================

/// Returns shim version string. Caller must free with `qe_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn qe_version() -> *mut c_char {
    cstring_into_raw(format!("qdrant-edge-ffi 0.0.1 (qdrant-edge=0.6.1)"))
}

// ====================================================================
// Shard lifecycle
// ====================================================================

/// Open or create a shard at `path` with given vector dimension and distance.
///
/// `distance` is one of "cosine", "dot", "euclid", "manhattan" (case-insensitive).
/// On error, returns null and writes message to *error_out.
///
/// # Safety
/// - `path` must be a valid null-terminated UTF-8 C string.
/// - `distance_str` must be a valid null-terminated UTF-8 C string.
/// - `error_out` may be null (errors silently dropped).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_open(
    path: *const c_char,
    dim: u32,
    distance_str: *const c_char,
    error_out: *mut *mut c_char,
) -> *mut c_void {
    let path_s = match unsafe { cstr_to_str(path) } {
        Ok(s) => s,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return ptr::null_mut();
        }
    };
    let dist_s = match unsafe { cstr_to_str(distance_str) } {
        Ok(s) => s,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return ptr::null_mut();
        }
    };
    let distance = match distance_from_str(dist_s) {
        Ok(d) => d,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return ptr::null_mut();
        }
    };

    let path = Path::new(path_s);
    if let Err(e) = std::fs::create_dir_all(path) {
        unsafe { write_error(error_out, format!("create_dir_all failed: {e}")) };
        return ptr::null_mut();
    }

    let config = build_edge_config(dim, distance);

    match EdgeShard::load_with_wal_options(path, Some(config), flutter_gemma_wal_options()) {
        Ok(shard) => Box::into_raw(Box::new(shard)) as *mut c_void,
        Err(e) => {
            unsafe {
                write_error(error_out, format!("EdgeShard::load_with_wal_options failed: {e}"))
            };
            ptr::null_mut()
        }
    }
}

/// Close shard. Frees all resources.
///
/// # Safety
/// `shard` must be obtained from `qe_shard_open` and not yet closed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_close(shard: *mut c_void) {
    if shard.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(shard as *mut EdgeShard) });
}

// ====================================================================
// Upsert (single + batch)
// ====================================================================

/// Upsert one point.
/// Returns 0 on success, -1 on error.
///
/// `id_str` is parsed as u64 or UUID by qdrant-edge `FromStr`.
///
/// # Safety
/// - `shard` must be valid.
/// - `vector_ptr` must point to `vector_len` f32 values.
/// - `payload_json` may be null (no payload) or a valid JSON object string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_upsert(
    shard: *mut c_void,
    id_str: *const c_char,
    vector_ptr: *const f32,
    vector_len: usize,
    payload_json: *const c_char,
    error_out: *mut *mut c_char,
) -> i32 {
    let Some(shard_ref) = (unsafe { shard_ref(shard) }) else {
        unsafe { write_error(error_out, "null shard handle") };
        return -1;
    };
    if vector_ptr.is_null() || vector_len == 0 {
        unsafe { write_error(error_out, "empty vector") };
        return -1;
    }
    let id_s = match unsafe { cstr_to_str(id_str) } {
        Ok(s) => s,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return -1;
        }
    };
    let id = match parse_point_id(id_s) {
        Ok(p) => p,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return -1;
        }
    };
    let vector: Vec<f32> = unsafe { slice::from_raw_parts(vector_ptr, vector_len) }.to_vec();
    let payload = match unsafe { parse_payload(payload_json) } {
        Ok(p) => p,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return -1;
        }
    };

    let point = PointStruct::new(id, vector, payload);
    let op = UpdateOperation::PointOperation(PointOperations::UpsertPoints(
        PointInsertOperations::PointsList(vec![point.into()]),
    ));
    match shard_ref.update(op) {
        Ok(_) => 0,
        Err(e) => {
            unsafe { write_error(error_out, format!("upsert failed: {e}")) };
            -1
        }
    }
}

/// Upsert multiple points in one call. `points_json` is a JSON array of
/// `{"id": "<id>", "vector": [f32...], "payload": {...} | null}` objects.
///
/// # Safety
/// - `shard` must be valid.
/// - `points_json` must be a valid null-terminated UTF-8 C string with valid JSON.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_upsert_batch(
    shard: *mut c_void,
    points_json: *const c_char,
    error_out: *mut *mut c_char,
) -> i32 {
    let Some(shard_ref) = (unsafe { shard_ref(shard) }) else {
        unsafe { write_error(error_out, "null shard handle") };
        return -1;
    };
    let s = match unsafe { cstr_to_str(points_json) } {
        Ok(s) => s,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return -1;
        }
    };
    let parsed: serde_json::Value = match serde_json::from_str(s) {
        Ok(v) => v,
        Err(e) => {
            unsafe { write_error(error_out, format!("points_json parse: {e}")) };
            return -1;
        }
    };
    let arr = match parsed.as_array() {
        Some(a) => a,
        None => {
            unsafe { write_error(error_out, "points_json must be a JSON array") };
            return -1;
        }
    };

    let mut points = Vec::with_capacity(arr.len());
    for (i, item) in arr.iter().enumerate() {
        let obj = match item.as_object() {
            Some(o) => o,
            None => {
                unsafe { write_error(error_out, format!("entry {i} is not an object")) };
                return -1;
            }
        };
        let id_raw = match obj.get("id").and_then(|v| v.as_str()) {
            Some(s) => s,
            None => {
                unsafe { write_error(error_out, format!("entry {i}: missing string 'id'")) };
                return -1;
            }
        };
        let id = match parse_point_id(id_raw) {
            Ok(p) => p,
            Err(e) => {
                unsafe { write_error(error_out, format!("entry {i}: {e}")) };
                return -1;
            }
        };
        let vec_arr = match obj.get("vector").and_then(|v| v.as_array()) {
            Some(a) => a,
            None => {
                unsafe { write_error(error_out, format!("entry {i}: missing array 'vector'")) };
                return -1;
            }
        };
        let mut vector = Vec::with_capacity(vec_arr.len());
        for (j, v) in vec_arr.iter().enumerate() {
            match v.as_f64() {
                Some(f) => vector.push(f as f32),
                None => {
                    unsafe { write_error(error_out, format!("entry {i}: vector[{j}] not a number")) };
                    return -1;
                }
            }
        }
        let payload = obj
            .get("payload")
            .cloned()
            .filter(|v| !v.is_null())
            .unwrap_or_else(|| serde_json::json!({}));
        if !payload.is_object() {
            unsafe { write_error(error_out, format!("entry {i}: payload must be object or null")) };
            return -1;
        }
        points.push(PointStruct::new(id, vector, payload).into());
    }

    let op = UpdateOperation::PointOperation(PointOperations::UpsertPoints(
        PointInsertOperations::PointsList(points),
    ));
    match shard_ref.update(op) {
        Ok(_) => 0,
        Err(e) => {
            unsafe { write_error(error_out, format!("upsert_batch failed: {e}")) };
            -1
        }
    }
}

unsafe fn parse_payload(payload_json: *const c_char) -> Result<serde_json::Value, String> {
    if payload_json.is_null() {
        return Ok(serde_json::json!({}));
    }
    let s = unsafe { cstr_to_str(payload_json) }.map_err(str::to_string)?;
    let v: serde_json::Value =
        serde_json::from_str(s).map_err(|e| format!("payload JSON: {e}"))?;
    if !v.is_object() {
        return Err("payload must be a JSON object".to_string());
    }
    Ok(v)
}

// ====================================================================
// Search
// ====================================================================

/// Top-K nearest by distance. Returns 0/-1, writes JSON array to
/// `*response_json_out` on success — caller must `qe_string_free` it.
///
/// Each result entry: `{"id": <u64|string>, "score": f32, "payload": {...}}`.
///
/// # Safety
/// - `shard` must be valid.
/// - `vector_ptr`/`vector_len` must describe a valid f32 slice.
/// - `response_json_out` must be a non-null writable pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_search(
    shard: *mut c_void,
    vector_ptr: *const f32,
    vector_len: usize,
    top_k: u32,
    response_json_out: *mut *mut c_char,
    error_out: *mut *mut c_char,
) -> i32 {
    unsafe { do_search(shard, vector_ptr, vector_len, top_k, ptr::null(), response_json_out, error_out) }
}

/// Same as `qe_shard_search` but with a Qdrant filter.
/// `filter_json` is the qdrant-edge JSON `Filter { must, should, must_not }`.
/// Pass null to omit filter (equivalent to `qe_shard_search`).
///
/// # Safety
/// Same as `qe_shard_search`. `filter_json` may be null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_search_with_filter(
    shard: *mut c_void,
    vector_ptr: *const f32,
    vector_len: usize,
    top_k: u32,
    filter_json: *const c_char,
    response_json_out: *mut *mut c_char,
    error_out: *mut *mut c_char,
) -> i32 {
    unsafe { do_search(shard, vector_ptr, vector_len, top_k, filter_json, response_json_out, error_out) }
}

#[allow(clippy::too_many_arguments)]
unsafe fn do_search(
    shard: *mut c_void,
    vector_ptr: *const f32,
    vector_len: usize,
    top_k: u32,
    filter_json: *const c_char,
    response_json_out: *mut *mut c_char,
    error_out: *mut *mut c_char,
) -> i32 {
    let Some(shard_ref) = (unsafe { shard_ref(shard) }) else {
        unsafe { write_error(error_out, "null shard handle") };
        return -1;
    };
    if response_json_out.is_null() {
        unsafe { write_error(error_out, "null response_json_out") };
        return -1;
    }
    if vector_ptr.is_null() || vector_len == 0 {
        unsafe { write_error(error_out, "empty vector") };
        return -1;
    }
    let vector: Vec<f32> = unsafe { slice::from_raw_parts(vector_ptr, vector_len) }.to_vec();

    let filter = if filter_json.is_null() {
        None
    } else {
        let s = match unsafe { cstr_to_str(filter_json) } {
            Ok(s) => s,
            Err(e) => {
                unsafe { write_error(error_out, e) };
                return -1;
            }
        };
        match serde_json::from_str::<Filter>(s) {
            Ok(f) => Some(f),
            Err(e) => {
                unsafe { write_error(error_out, format!("filter JSON: {e}")) };
                return -1;
            }
        }
    };

    let req = SearchRequest {
        query: QueryEnum::Nearest(NamedQuery {
            query: vector.into(),
            using: None,
        }),
        filter,
        params: None,
        limit: top_k as usize,
        offset: 0,
        with_payload: Some(WithPayloadInterface::Bool(true)),
        with_vector: Some(WithVector::Bool(false)),
        score_threshold: None,
    };
    let points = match shard_ref.search(req) {
        Ok(p) => p,
        Err(e) => {
            unsafe { write_error(error_out, format!("search failed: {e}")) };
            return -1;
        }
    };

    let mut out = Vec::with_capacity(points.len());
    for p in points {
        let id_v = point_id_to_json(&p.id);
        let payload_v = p
            .payload
            .map(|pl| serde_json::to_value(pl).unwrap_or(serde_json::Value::Null))
            .unwrap_or(serde_json::Value::Null);
        out.push(serde_json::json!({
            "id": id_v,
            "score": p.score,
            "payload": payload_v,
        }));
    }
    let json = match serde_json::to_string(&out) {
        Ok(s) => s,
        Err(e) => {
            unsafe { write_error(error_out, format!("serialize results: {e}")) };
            return -1;
        }
    };
    unsafe { *response_json_out = cstring_into_raw(json) };
    0
}

// ====================================================================
// Delete / clear / count
// ====================================================================

/// Delete points by IDs. `ids_json` is a JSON array of strings.
///
/// # Safety
/// - `shard` must be valid.
/// - `ids_json` must be a valid null-terminated UTF-8 C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_delete(
    shard: *mut c_void,
    ids_json: *const c_char,
    error_out: *mut *mut c_char,
) -> i32 {
    let Some(shard_ref) = (unsafe { shard_ref(shard) }) else {
        unsafe { write_error(error_out, "null shard handle") };
        return -1;
    };
    let s = match unsafe { cstr_to_str(ids_json) } {
        Ok(s) => s,
        Err(e) => {
            unsafe { write_error(error_out, e) };
            return -1;
        }
    };
    let arr: Vec<String> = match serde_json::from_str(s) {
        Ok(a) => a,
        Err(e) => {
            unsafe { write_error(error_out, format!("ids_json parse: {e}")) };
            return -1;
        }
    };
    let mut ids = Vec::with_capacity(arr.len());
    for (i, raw) in arr.iter().enumerate() {
        match parse_point_id(raw) {
            Ok(p) => ids.push(p),
            Err(e) => {
                unsafe { write_error(error_out, format!("entry {i}: {e}")) };
                return -1;
            }
        }
    }
    let op = UpdateOperation::PointOperation(PointOperations::DeletePoints { ids });
    match shard_ref.update(op) {
        Ok(_) => 0,
        Err(e) => {
            unsafe { write_error(error_out, format!("delete failed: {e}")) };
            -1
        }
    }
}

/// Exact total point count.
/// Returns count >= 0 on success, -1 on error.
///
/// # Safety
/// `shard` must be valid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_shard_count(shard: *mut c_void, error_out: *mut *mut c_char) -> i64 {
    let Some(shard_ref) = (unsafe { shard_ref(shard) }) else {
        unsafe { write_error(error_out, "null shard handle") };
        return -1;
    };
    match shard_ref.count(CountRequest { filter: None, exact: true }) {
        Ok(n) => n as i64,
        Err(e) => {
            unsafe { write_error(error_out, format!("count failed: {e}")) };
            -1
        }
    }
}

// ====================================================================
// String free
// ====================================================================

/// Free a string returned by any qe_* function.
///
/// # Safety
/// `s` must be a pointer returned by a qe_* function and not yet freed,
/// or null (no-op).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn qe_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    drop(unsafe { CString::from_raw(s) });
}
