import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gemma/core/qdrant/filter_codec.dart';
import 'package:flutter_gemma/core/qdrant/point_id_hasher.dart';
import 'package:flutter_gemma/core/qdrant/qdrant_edge_client.dart';
import 'package:flutter_gemma/core/services/vector_store_filter.dart';
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// [VectorStoreRepository] backed by qdrant-edge (FFI shim →
/// [QdrantEdgeClient] → native cdylib). The default native implementation
/// from flutter_gemma 0.16+; replaces [DartVectorStoreRepository] (SQLite +
/// local_hnsw) which becomes `@Deprecated` in the same release.
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
class QdrantVectorStoreRepository implements VectorStoreRepository {
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
        debugPrint('[QdrantVectorStore] close() failed (best-effort): $e');
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
          'Vector store not initialized — call initialize(path) first.');
    }
    final existing = _client;
    if (existing != null) {
      if (_dim != dim) {
        throw ArgumentError(
            'Embedding dimension mismatch: shard was opened with dim=$_dim, '
            'got vector of length $dim');
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

  @override
  Future<void> removeDocument({required String id}) async {
    final c = _client;
    if (c == null) {
      debugPrint(
          '[QdrantVectorStore] removeDocument($id) called before initialize() — ignored');
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
          'match stored dimension $_dim');
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
    // qdrant-edge has no truncate primitive — close, delete the shard
    // directory, and let the next addDocument reopen fresh.
    await c.close();
    _client = null;
    _dim = null;
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
        debugPrint('[QdrantVectorStore] close() failed (best-effort): $e');
      }
    }
  }
}
