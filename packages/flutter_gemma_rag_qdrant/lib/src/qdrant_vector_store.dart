import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/src/filter_codec.dart';
import 'package:flutter_gemma_rag_qdrant/src/point_id_hasher.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';

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
class QdrantVectorStore implements VectorStoreRepository {
  QdrantEdgeClient? _client;

  /// Dimension is captured on the first `addDocument` call (matches the
  /// existing auto-detection contract). Subsequent inserts must agree.
  int? _dim;

  /// Cached for [getStats] — the shim never exposes the configured dim,
  /// only the count. We keep it in Dart-land instead.
  Distance _distance = Distance.cosine;

  /// Where the shard lives on disk. Captured so `addDocument` can lazily
  /// open the shard with the correct dimension on first write.
  String? _shardPath;

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

  @override
  bool get isInitialized => _shardPath != null;

  @override
  bool get enableHnsw => _enableHnsw;

  @override
  set enableHnsw(bool value) => _enableHnsw = value;

  @override
  FilterSchema get filterSchema => _filterSchema;

  @override
  void configure(FilterSchema schema) => _filterSchema = schema;

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
    _shardPath = databasePath;
  }

  Future<QdrantEdgeClient> _ensureClient({required int dim}) async {
    final shardPath = _shardPath;
    if (shardPath == null) {
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
    // First open. Ensure the parent directory exists; qdrant-edge creates
    // its own subdir but the immediate parent must already be there.
    final parent = Directory(shardPath).parent;
    if (!parent.existsSync()) {
      try {
        parent.createSync(recursive: true);
      } on FileSystemException catch (e) {
        throw VectorStoreException(
          'Failed to create parent directory for qdrant shard at ${parent.path}: $e',
        );
      }
    }
    try {
      final c = await QdrantEdgeClient.open(
        path: shardPath,
        dim: dim,
        distance: _distance,
      );
      _client = c;
      _dim = dim;
      return c;
    } on QdrantException catch (e) {
      throw VectorStoreException('Failed to open qdrant shard', e);
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
      if (metadata != null) _metadataKey: metadata,
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
    final filterJson = FilterCodec.encode(filter);
    final hits = await c.search(
      queryVector: queryEmbedding,
      topK: topK,
      filterJson: filterJson,
    );
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
    final n = await c.count();
    return VectorStoreStats(documentCount: n, vectorDimension: _dim ?? 0);
  }

  @override
  Future<void> clear() async {
    final c = _client;
    final path = _shardPath;
    if (c == null || path == null) return;
    // qdrant-edge has no truncate primitive — close the client, delete the
    // shard directory, and let the next addDocument reopen fresh. Order
    // matters: only commit the in-memory "cleared" state AFTER the on-disk
    // shard is actually gone, so a close/delete failure can't leave the store
    // reporting empty while stale vectors persist on disk.
    try {
      await c.close();
    } catch (e) {
      throw VectorStoreException(
        'Failed to close qdrant client during clear: $e',
      );
    }
    final dir = Directory(path);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException catch (e) {
        throw VectorStoreException(
          'Failed to delete qdrant shard directory at ${dir.path}: $e',
        );
      }
    }
    // Only now that close + delete succeeded do we drop the in-memory handles.
    _client = null;
    _dim = null;
  }

  @override
  Future<void> close() async {
    final c = _client;
    _client = null;
    _dim = null;
    _shardPath = null;
    if (c != null) {
      try {
        await c.close();
      } on QdrantException catch (e) {
        gemmaLog('[QdrantVectorStore] close() failed (best-effort): $e');
      }
    }
  }
}
