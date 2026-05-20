import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/core/qdrant/qdrant_edge_bindings.dart';

/// Distance metric used by a qdrant-edge shard. Set at open time and fixed
/// for the shard's lifetime.
enum Distance {
  /// 1 - cosine angle between vectors. Most common for text embeddings;
  /// expects (but does not require) unit-norm inputs.
  cosine('cosine'),

  /// Dot product. For unit-norm vectors equivalent to cosine.
  dot('dot'),

  /// Euclidean (L2) distance.
  euclid('euclid'),

  /// Manhattan (L1) distance.
  manhattan('manhattan');

  final String wireName;
  const Distance(this.wireName);
}

/// One search hit returned by [QdrantEdgeClient.search].
class SearchHit {
  /// Point ID as stored — typically a UUIDv5 string for points written via
  /// flutter_gemma's high-level repository.
  final String id;

  /// Similarity score per the shard's [Distance] metric. Cosine returns
  /// in [-1, 1] (close to 1 = similar); for L2/Manhattan, lower = more
  /// similar (semantics inverted from cosine — be careful when threshold-
  /// filtering downstream).
  final double score;

  /// Decoded payload object if the point had one, otherwise null.
  final Map<String, dynamic>? payload;

  const SearchHit({
    required this.id,
    required this.score,
    this.payload,
  });
}

/// Typed wrapper around any failure surfaced by the qdrant-edge FFI shim.
/// The native side writes a human-readable C string into the `error_out`
/// pointer; we lift that into [message] and free the native allocation.
class QdrantException implements Exception {
  final String message;
  const QdrantException(this.message);

  @override
  String toString() => 'QdrantException: $message';
}

/// High-level Dart wrapper over [QdrantEdgeBindings].
///
/// Manages:
///   - One-time native library load (cross-platform).
///   - One opaque `*mut EdgeShard` handle per client instance, with a
///     [Finalizer] safety net in case the caller forgets [close].
///   - Marshalling Dart values to/from the C-FFI surface, including JSON
///     payloads and the `Pointer<Pointer<Char>> error_out` convention.
///
/// Not intended for direct use by application code — sits behind
/// [QdrantVectorStoreRepository], which adapts to the
/// [VectorStoreRepository] interface used by the rest of flutter_gemma.
class QdrantEdgeClient {
  /// Bindings are cheap to look up but the underlying [DynamicLibrary]
  /// should only be opened once per process. Cache it.
  static QdrantEdgeBindings? _bindings;

  /// **Test-only**: override the dylib path that [_ensureBindings] uses on
  /// the first call. Set this from unit tests that run in a plain Dart VM
  /// (no Native Assets framework bundle); leave null in production.
  ///
  /// Setting after the first FFI call has no effect — the bindings are
  /// cached. Reset to null + null out [_bindings] if a test really needs
  /// to swap the dylib mid-process.
  @visibleForTesting
  static String? debugOverrideDylibPath;

  static QdrantEdgeBindings _ensureBindings() {
    final cached = _bindings;
    if (cached != null) return cached;

    final override = debugOverrideDylibPath;
    if (override != null) {
      return _bindings = QdrantEdgeBindings(DynamicLibrary.open(override));
    }

    final String libPath;
    if (Platform.isIOS) {
      // Native Assets puts dylibs in Frameworks/ inside Runner.app on iOS.
      libPath =
          '@executable_path/Frameworks/qdrant_edge_ffi.framework/qdrant_edge_ffi';
    } else if (Platform.isMacOS) {
      libPath = 'qdrant_edge_ffi.framework/qdrant_edge_ffi';
    } else if (Platform.isAndroid || Platform.isLinux) {
      libPath = 'libqdrant_edge_ffi.so';
    } else if (Platform.isWindows) {
      libPath = 'qdrant_edge_ffi.dll';
    } else {
      throw UnsupportedError(
          'qdrant-edge is not available on ${Platform.operatingSystem}');
    }

    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open(libPath);
    } on ArgumentError catch (e) {
      // Native Assets did not bundle the dylib for this host. The most common
      // cause on Apple targets is an Intel Mac / x86_64 simulator — the
      // prebuilt only ships arm64 today.
      final hint = (Platform.isMacOS || Platform.isIOS)
          ? ' (Apple Intel hosts are not supported — Apple Silicon arm64 only)'
          : '';
      throw QdrantException(
          'qdrant-edge native library not found for ${Platform.operatingSystem}$hint. '
          'Did `flutter pub get` complete? Underlying error: $e');
    }
    return _bindings = QdrantEdgeBindings(lib);
  }

  /// Finalizer attached to each [QdrantEdgeClient] instance: if the caller
  /// drops their reference without calling [close], the GC eventually runs
  /// this and releases the shard handle. Belt-and-suspenders — proper
  /// applications always call [close] explicitly.
  static final Finalizer<Pointer<Void>> _finalizer = Finalizer((handle) {
    if (handle != nullptr) {
      _ensureBindings().qe_shard_close(handle);
    }
  });

  final QdrantEdgeBindings _b;
  Pointer<Void> _shard = nullptr;
  bool _closed = false;

  QdrantEdgeClient._() : _b = _ensureBindings();

  /// Open (or create) a shard on disk.
  ///
  /// `path` is a directory — qdrant-edge stores its WAL + segment files
  /// under it. The directory is created if it doesn't exist.
  ///
  /// `dim` is the vector dimension. Once a shard is created with a given
  /// dim, subsequent opens **must** pass the same value (the C shim's
  /// build_edge_config will fail compatibility check otherwise).
  static Future<QdrantEdgeClient> open({
    required String path,
    required int dim,
    Distance distance = Distance.cosine,
  }) async {
    final client = QdrantEdgeClient._();
    final pathPtr = path.toNativeUtf8();
    final distPtr = distance.wireName.toNativeUtf8();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final handle = client._b.qe_shard_open(
        pathPtr.cast(),
        dim,
        distPtr.cast(),
        errorOut.cast(),
      );
      if (handle == nullptr) {
        throw QdrantException(_consumeString(client._b, errorOut) ??
            'qe_shard_open returned null');
      }
      client._shard = handle;
      _finalizer.attach(client, handle, detach: client);
      return client;
    } finally {
      malloc.free(pathPtr);
      malloc.free(distPtr);
      calloc.free(errorOut);
    }
  }

  /// Library version string. Reads from the shim's compiled-in constant.
  String version() {
    final ptr = _b.qe_version();
    if (ptr == nullptr) return '';
    final s = ptr.cast<Utf8>().toDartString();
    _b.qe_string_free(ptr);
    return s;
  }

  /// Upsert one point. `payload` may be omitted (`null`) or any
  /// JSON-encodable Map.
  Future<void> upsert({
    required String id,
    required List<double> vector,
    Map<String, dynamic>? payload,
  }) async {
    _checkOpen();
    final idPtr = id.toNativeUtf8();
    final vecPtr = _allocFloatVec(vector);
    final payloadPtr =
        payload == null ? nullptr : jsonEncode(payload).toNativeUtf8();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _b.qe_shard_upsert(
        _shard,
        idPtr.cast(),
        vecPtr,
        vector.length,
        (payloadPtr == nullptr ? nullptr : payloadPtr.cast()),
        errorOut.cast(),
      );
      if (rc != 0) {
        throw QdrantException(
            _consumeString(_b, errorOut) ?? 'qe_shard_upsert rc=$rc');
      }
    } finally {
      malloc.free(idPtr);
      malloc.free(vecPtr);
      if (payloadPtr != nullptr) malloc.free(payloadPtr);
      calloc.free(errorOut);
    }
  }

  /// Bulk upsert. The shim accepts a JSON array of point objects; this
  /// method composes that JSON internally so callers stay in Dart-land.
  Future<void> upsertBatch(
      List<({String id, List<double> vector, Map<String, dynamic>? payload})>
          points) async {
    _checkOpen();
    if (points.isEmpty) return;
    final json = jsonEncode([
      for (final p in points)
        {
          'id': p.id,
          'vector': p.vector,
          if (p.payload != null) 'payload': p.payload,
        }
    ]);
    final jsonPtr = json.toNativeUtf8();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _b.qe_shard_upsert_batch(
        _shard,
        jsonPtr.cast(),
        errorOut.cast(),
      );
      if (rc != 0) {
        throw QdrantException(
            _consumeString(_b, errorOut) ?? 'qe_shard_upsert_batch rc=$rc');
      }
    } finally {
      malloc.free(jsonPtr);
      calloc.free(errorOut);
    }
  }

  /// Top-K nearest-neighbour search. Pass [filterJson] (encoded via
  /// [FilterCodec.encode]) to constrain results by payload; pass null to
  /// run unfiltered.
  Future<List<SearchHit>> search({
    required List<double> queryVector,
    required int topK,
    String? filterJson,
  }) async {
    _checkOpen();
    final vecPtr = _allocFloatVec(queryVector);
    final filterPtr = filterJson == null ? nullptr : filterJson.toNativeUtf8();
    final responseOut = calloc<Pointer<Utf8>>();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final int rc;
      if (filterPtr == nullptr) {
        rc = _b.qe_shard_search(
          _shard,
          vecPtr,
          queryVector.length,
          topK,
          responseOut.cast(),
          errorOut.cast(),
        );
      } else {
        rc = _b.qe_shard_search_with_filter(
          _shard,
          vecPtr,
          queryVector.length,
          topK,
          filterPtr.cast(),
          responseOut.cast(),
          errorOut.cast(),
        );
      }
      if (rc != 0) {
        throw QdrantException(
            _consumeString(_b, errorOut) ?? 'qe_shard_search rc=$rc');
      }
      final responseJson = _consumeString(_b, responseOut);
      if (responseJson == null) return const [];
      return _decodeSearchResponse(responseJson);
    } finally {
      malloc.free(vecPtr);
      if (filterPtr != nullptr) malloc.free(filterPtr);
      calloc.free(responseOut);
      calloc.free(errorOut);
    }
  }

  /// Delete points by IDs. No-op for IDs that don't exist.
  Future<void> delete(List<String> ids) async {
    _checkOpen();
    if (ids.isEmpty) return;
    final json = jsonEncode(ids);
    final jsonPtr = json.toNativeUtf8();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _b.qe_shard_delete(
        _shard,
        jsonPtr.cast(),
        errorOut.cast(),
      );
      if (rc != 0) {
        throw QdrantException(
            _consumeString(_b, errorOut) ?? 'qe_shard_delete rc=$rc');
      }
    } finally {
      malloc.free(jsonPtr);
      calloc.free(errorOut);
    }
  }

  /// Exact total number of points currently in the shard.
  Future<int> count() async {
    _checkOpen();
    final errorOut = calloc<Pointer<Utf8>>();
    try {
      final n = _b.qe_shard_count(_shard, errorOut.cast());
      if (n < 0) {
        throw QdrantException(
            _consumeString(_b, errorOut) ?? 'qe_shard_count returned -1');
      }
      return n;
    } finally {
      calloc.free(errorOut);
    }
  }

  /// Close the shard. Idempotent — safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final h = _shard;
    _shard = nullptr;
    if (h != nullptr) {
      _b.qe_shard_close(h);
    }
    _finalizer.detach(this);
  }

  void _checkOpen() {
    if (_closed || _shard == nullptr) {
      throw const QdrantException('QdrantEdgeClient is closed');
    }
  }

  static Pointer<Float> _allocFloatVec(List<double> v) {
    final ptr = malloc<Float>(v.length);
    final f32 = Float32List.fromList(v);
    ptr.asTypedList(v.length).setAll(0, f32);
    return ptr;
  }

  /// Reads a C string from a slot (used for both error_out and response_json_out),
  /// frees it via `qe_string_free`, and returns the Dart copy. Returns null when
  /// the native side didn't write anything into the slot.
  static String? _consumeString(
      QdrantEdgeBindings b, Pointer<Pointer<Utf8>> slot) {
    final p = slot.value;
    if (p == nullptr) return null;
    final s = p.toDartString();
    b.qe_string_free(p.cast());
    slot.value = nullptr;
    return s;
  }

  static List<SearchHit> _decodeSearchResponse(String json) {
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      return [
        for (final m in list)
          SearchHit(
            id: m['id'].toString(),
            score: (m['score'] as num).toDouble(),
            payload: m['payload'] is Map<String, dynamic>
                ? m['payload'] as Map<String, dynamic>
                : null,
          ),
      ];
    } on FormatException catch (e) {
      throw QdrantException('Malformed search response from native shim: $e');
    } on TypeError catch (e) {
      throw QdrantException(
          'Unexpected search response shape from native shim: $e');
    }
  }
}
