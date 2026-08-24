import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/src/filter_codec.dart';
import 'package:flutter_gemma_rag_qdrant/src/point_id_hasher.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
import 'package:path/path.dart' as p;

/// Native-only RAG vector store backed by qdrant-edge (FFI). Implements
/// flutter_gemma's [VectorStoreRepository]. Its HNSW index makes it the fastest
/// native option — roughly 5–11× faster search than the in-SQLite sqlite-vec
/// store at 1k–10k docs (with identical top-K results). Web is unsupported
/// (qdrant-edge can't compile to WASM); use flutter_gemma_rag_sqlite there.
///
/// Public API parity with the existing contract:
///
/// * `String id` continues to be the user-facing identifier. Internally
///   each id is mapped to a stable UUIDv5 via [PointIdHasher] and stored
///   alongside the document content in the qdrant payload so that
///   [searchSimilar] returns the original String back without a sidecar
///   mapping table.
/// * `addDocument`'s `metadata` is still a JSON string. We do **not**
///   parse it eagerly — we forward the raw string into the payload under
///   the key `metadata`. Filtering by metadata fields therefore requires
///   that callers pass valid JSON; this matches the existing constraint.
/// * `enableHnsw` is accepted but ignored — qdrant decides indexing
///   internally based on its `indexing_threshold` (~20k points). Below
///   that it brute-forces a plain segment, which is already faster than
///   our Dart HNSW for typical RAG corpora.
///
/// Distance defaults to cosine, matching the historical behaviour.
///
/// ### On-disk layout
///
/// The store never opens or deletes the caller's [initialize] path directly.
/// It owns a bounded, format-scoped subdirectory — `databasePath/qdrant_edge_v1`
/// — created on first write. This means:
///
///   * a pre-existing (e.g. legacy 1.x / crate 0.7.x) shard sitting at the
///     bare `databasePath` is never opened, so there is no partial-open or
///     WAL-corruption risk from mixing engine versions;
///   * [clear] only ever deletes the owned subdirectory, never the caller's
///     directory or any sibling inside it.
class QdrantVectorStore implements VectorStoreRepository {
  QdrantEdgeClient? _client;

  /// Dimension is captured on the first `addDocument` call (matches the
  /// existing auto-detection contract). Subsequent inserts must agree.
  int? _dim;

  /// Cached for [getStats] — the shim never exposes the configured dim,
  /// only the count. We keep it in Dart-land instead.
  Distance _distance = Distance.cosine;

  /// The path passed to [initialize]. The store never opens or deletes this
  /// path directly — only the owned subdirectory under it (see [_storeDirFor]).
  String? _databasePath;

  /// `enableHnsw` is part of the contract but a no-op for qdrant.
  bool _enableHnsw = true;

  /// Declared filterable-metadata schema (via [configure]). Empty by default,
  /// so callers that never declare a schema get byte-identical payloads. When
  /// non-empty, [addDocument] promotes each declared field to a TOP-LEVEL
  /// payload key (alongside the opaque [_metadataKey] blob) so qdrant's
  /// [FilterCodec] — which already targets top-level keys — can match on them.
  FilterSchema _filterSchema = const FilterSchema();

  /// Payload key under which we stash the original String id sent by the
  /// caller. qdrant point ids are UUID-hashed for storage; this lets
  /// [searchSimilar] reconstruct the original on the way out.
  static const _userIdKey = '__flutter_gemma_id';
  static const _contentKey = '__flutter_gemma_content';
  static const _metadataKey = '__flutter_gemma_metadata';

  /// The package's on-disk format namespace. A new location for the 0.8.0
  /// SDK / crate-0.8.0 shard format — a pre-existing shard written by an
  /// older (1.x / crate 0.7.x) release of this package sits at the bare
  /// [_databasePath] and is simply orphaned in place, never opened.
  static const _storeDirName = 'qdrant_edge_v1';

  /// Test-only seam: when set, [clear] calls this instead of
  /// `dir.deleteSync(recursive: true)` on the owned shard directory. Lets
  /// tests deterministically exercise the delete-failure / fail-closed
  /// recovery path (see `clear()`) by throwing a [FileSystemException] from
  /// here, without OS-level fault injection (permission bits, symlinks) that
  /// would not behave identically across POSIX and Windows.
  @visibleForTesting
  void Function(Directory dir)? debugDeleteDirOverride;

  @override
  bool get isInitialized => _databasePath != null;

  @override
  bool get enableHnsw => _enableHnsw;

  @override
  set enableHnsw(bool value) => _enableHnsw = value;

  @override
  FilterSchema get filterSchema => _filterSchema;

  @override
  void configure(FilterSchema schema) {
    // Validate here, not only in FilterField's assert: asserts are stripped in
    // release, and a field name read from config at runtime would otherwise
    // reach the storage layer unchecked. Rejecting at configure() points the
    // error at the schema the developer wrote rather than at a query built
    // from it much later.
    // Core checks what is wrong on every backend; this store checks what
    // ITS storage cannot take. Splitting them keeps one backend's grammar
    // out of a package that has no backends.
    FilterField.validateSchema(schema);
    for (final field in schema.fields) {
      FilterCodec.validateFieldName(field.name);
    }
    _filterSchema = schema;
  }

  @override
  Future<void> initialize(String databasePath) async {
    // Re-init is allowed and matches the DartVectorStoreRepository contract:
    // close any prior shard, then arm the new path. Dimension is detected
    // lazily on the first addDocument so we don't have to commit to one
    // before we've seen an embedding.
    final existing = _client;
    if (existing != null) {
      try {
        await existing.close();
      } on QdrantException catch (e) {
        gemmaLog('[QdrantVectorStore] close() failed (best-effort): $e');
      }
    }
    _client = null;
    _dim = null;
    _databasePath = databasePath;
  }

  /// The owned, format-scoped shard directory for [databasePath] — the only
  /// path this store ever opens or deletes. Never the bare [databasePath]
  /// itself.
  static String _storeDirFor(String databasePath) =>
      p.join(databasePath, _storeDirName);

  Future<QdrantEdgeClient> _ensureClient({required int dim}) async {
    final databasePath = _databasePath;
    if (databasePath == null) {
      throw const VectorStoreException(
        'Vector store not initialized — call initialize(path) first.',
      );
    }
    final existing = _client;
    if (existing != null) {
      if (_dim != dim) {
        throw ArgumentError(
          'Embedding dimension mismatch: shard was opened with dim=$_dim, '
          'got vector of length $dim',
        );
      }
      return existing;
    }
    // First open. The store owns `<databasePath>/qdrant_edge_v1` — created
    // recursively — and never opens the bare databasePath itself, so a
    // pre-existing (e.g. legacy) directory or file sitting directly at
    // databasePath is left untouched.
    final storeDir = _storeDirFor(databasePath);
    try {
      Directory(storeDir).createSync(recursive: true);
    } on FileSystemException catch (e) {
      throw VectorStoreException(
        'Failed to create qdrant shard directory at $storeDir: $e',
      );
    }
    try {
      final c = await QdrantEdgeClient.open(
        path: storeDir,
        dim: dim,
        distance: _distance,
      );
      _client = c;
      _dim = dim;
      return c;
    } on QdrantException catch (e) {
      // Wrap and rethrow — never auto-rename/delete/rebuild. Whether the
      // failure is transient (permissions, lock, missing native lib, I/O) or
      // a real format incompatibility, it surfaces the same safe way: thrown,
      // data untouched.
      throw VectorStoreException(
        'Failed to open qdrant shard at $storeDir — this may be an older '
        'store; clear and re-index if the problem persists',
        e,
      );
    }
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    final c = await _ensureClient(dim: embedding.length);
    final payload = <String, dynamic>{
      _userIdKey: id,
      _contentKey: content,
      _metadataKey: ?metadata,
    };
    // Filter-field promotion: only when a schema is declared AND metadata is
    // present. Without a schema this branch never runs, so existing callers
    // get byte-identical payloads (the opaque blob under _metadataKey only).
    // With a schema, expand each DECLARED field to a top-level payload key so
    // FilterCodec's top-level-key predicates actually match.
    if (!_filterSchema.isEmpty && metadata != null) {
      _promoteFilterFields(payload, metadata);
    }
    try {
      await c.upsert(
        id: PointIdHasher.hash(id),
        vector: embedding,
        payload: payload,
      );
    } on QdrantException catch (e) {
      throw VectorStoreException('addDocument failed for id=$id', e);
    }
  }

  /// Expands the declared [FilterField]s out of the raw [metadata] JSON into
  /// top-level [payload] keys (in addition to the opaque [_metadataKey] blob).
  ///
  /// Defensive by design — promotion must never break an `addDocument` that
  /// would otherwise succeed:
  /// * non-object or unparseable [metadata] → logged, left as the opaque blob;
  /// * a declared field absent from the metadata → skipped (no key written),
  ///   so a [Filter] on it matches nothing (documented no-op, never a throw).
  void _promoteFilterFields(Map<String, dynamic> payload, String metadata) {
    Object? decoded;
    try {
      decoded = jsonDecode(metadata);
    } on FormatException catch (e) {
      gemmaLog(
        '[QdrantVectorStore] metadata is not valid JSON — filter fields not '
        'promoted (round-trip blob kept): $e',
      );
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      gemmaLog(
        '[QdrantVectorStore] metadata JSON is not an object — filter fields '
        'not promoted (round-trip blob kept)',
      );
      return;
    }
    for (final field in _filterSchema.fields) {
      if (decoded.containsKey(field.name)) {
        payload[field.name] = decoded[field.name];
      }
    }
  }

  @override
  Future<void> removeDocument({required String id}) async {
    final c = _client;
    if (c == null) {
      gemmaLog(
        '[QdrantVectorStore] removeDocument($id) called before initialize() — ignored',
      );
      return;
    }
    try {
      await c.delete([PointIdHasher.hash(id)]);
    } on QdrantException catch (e) {
      throw VectorStoreException('removeDocument failed for id=$id', e);
    }
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
    Filter? filter,
  }) async {
    final c = _client;
    if (c == null || _dim == null) {
      // No documents yet — nothing to retrieve.
      return const [];
    }
    if (queryEmbedding.length != _dim) {
      throw ArgumentError(
        'Query embedding dimension ${queryEmbedding.length} does not '
        'match stored dimension $_dim',
      );
    }
    final filterJson = FilterCodec.encode(filter, _filterSchema);
    final List<SearchHit> hits;
    try {
      hits = await c.search(
        queryVector: queryEmbedding,
        topK: topK,
        filterJson: filterJson,
      );
    } on QdrantException catch (e) {
      throw VectorStoreException('searchSimilar failed', e);
    }
    return [
      for (final hit in hits)
        if (hit.score >= threshold)
          RetrievalResult(
            id: hit.payload?[_userIdKey] as String? ?? hit.id,
            content: hit.payload?[_contentKey] as String? ?? '',
            similarity: hit.score,
            metadata: hit.payload?[_metadataKey] as String?,
          ),
    ];
  }

  @override
  Future<VectorStoreStats> getStats() async {
    final c = _client;
    if (c == null) {
      return VectorStoreStats(documentCount: 0, vectorDimension: 0);
    }
    final int n;
    try {
      n = await c.count();
    } on QdrantException catch (e) {
      throw VectorStoreException('getStats failed', e);
    }
    return VectorStoreStats(documentCount: n, vectorDimension: _dim ?? 0);
  }

  @override
  Future<void> clear() async {
    final c = _client;
    final databasePath = _databasePath;
    if (databasePath == null) return;

    // qdrant-edge has no truncate primitive — close the client, delete the
    // OWNED shard subdirectory (never the bare databasePath), and let the
    // next addDocument reopen fresh.
    if (c != null) {
      try {
        await c.close();
      } catch (e) {
        throw VectorStoreException(
          'Failed to close qdrant client during clear: $e',
        );
      }
    }
    // The client (if any) is now closed. Drop the in-memory handle
    // immediately — before the guard/delete below, which can themselves
    // throw — so a failure never leaves a stale, already-closed client
    // sitting in `_client` for the next _ensureClient() call to hand back.
    // Fail-closed: the next op always re-opens cleanly rather than reusing a
    // dead handle.
    _client = null;
    _dim = null;

    final storeDir = _storeDirFor(databasePath);
    final dir = Directory(storeDir);
    if (!dir.existsSync()) {
      // Nothing was ever written under the owned subdir — nothing to clear.
      return;
    }

    _assertStoreDirWithinDatabasePath(databasePath, storeDir);

    try {
      final override = debugDeleteDirOverride;
      if (override != null) {
        override(dir);
      } else {
        dir.deleteSync(recursive: true);
      }
    } on FileSystemException catch (e) {
      // Delete failed partway — the on-disk subdir may be left in a mixed
      // state. Fail-closed: mark the whole store uninitialized (rather than
      // just clearing the client/dim above) so nothing reuses a possibly
      // half-deleted shard; the caller must call initialize() again before
      // any further operation succeeds.
      _databasePath = null;
      throw VectorStoreException(
        'Failed to delete qdrant shard directory at $storeDir: $e',
      );
    }
  }

  /// Refuses to delete anything unless the *canonicalized* [storeDir]
  /// resolves to a non-root descendant of the *canonicalized* [databasePath]
  /// — i.e. actually inside it, not equal to it. Canonicalizing (resolving
  /// symlinks) before comparing is what makes this a real guard rather than a
  /// string-prefix check: [storeDir] is always literally
  /// `p.join(databasePath, 'qdrant_edge_v1')` by construction, so the only way
  /// this can fail is a symlink (or similar) that makes the on-disk path
  /// resolve outside [databasePath]. On any failure to resolve, or an escape,
  /// this throws [VectorStoreException] and deletes nothing.
  void _assertStoreDirWithinDatabasePath(String databasePath, String storeDir) {
    final String canonicalDatabasePath;
    final String canonicalStoreDir;
    try {
      canonicalDatabasePath = Directory(databasePath).resolveSymbolicLinksSync();
      canonicalStoreDir = Directory(storeDir).resolveSymbolicLinksSync();
    } on FileSystemException catch (e) {
      throw VectorStoreException(
        'Failed to resolve the qdrant shard path for the clear() safety '
        'check: $e',
      );
    }
    if (!p.isWithin(canonicalDatabasePath, canonicalStoreDir)) {
      throw VectorStoreException(
        'Refusing to delete "$storeDir": it does not resolve to a path '
        'inside the initialized database directory "$databasePath" '
        '(possible symlink escape). No data was deleted.',
      );
    }
  }

  @override
  Future<void> close() async {
    final c = _client;
    _client = null;
    _dim = null;
    _databasePath = null;
    if (c != null) {
      try {
        await c.close();
      } on QdrantException catch (e) {
        gemmaLog('[QdrantVectorStore] close() failed (best-effort): $e');
      }
    }
  }
}
