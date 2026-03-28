import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_gemma/core/infrastructure/hnsw_vector_index.dart';
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Unified VectorStore using sqlite3 dart:ffi + HNSW
///
/// Replaces platform-specific implementations:
/// - Android: VectorStore.kt (SQLiteOpenHelper)
/// - iOS: VectorStore.swift (SQLite3 C API)
///
/// Used on: Android, iOS, macOS, Windows, Linux
/// Web: uses WebVectorStoreRepository (wa-sqlite WASM)
class DartVectorStoreRepository implements VectorStoreRepository {
  Database? _db;
  int? _detectedDimension;
  final HnswVectorIndex _hnswIndex = HnswVectorIndex();
  bool _isInitialized = false;

  static const int _hnswThreshold = 100;
  static const String _tableName = 'documents';

  @override
  bool enableHnsw = true;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(String databasePath) async {
    try {
      _db?.close();
      _db = sqlite3.open(databasePath);
      _createTable();
      _isInitialized = true;
      _detectDimension();
      await _rebuildHnswIndex();
    } catch (e) {
      throw VectorStoreException('Failed to initialize vector store', e);
    }
  }

  void _createTable() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        embedding BLOB NOT NULL,
        metadata TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_created_at ON $_tableName(created_at)',
    );
  }

  void _detectDimension() {
    final result = _db!.select(
      'SELECT embedding FROM $_tableName LIMIT 1',
    );
    if (result.isNotEmpty) {
      final blob = result.first['embedding'] as Uint8List;
      _detectedDimension = blob.length ~/ 4; // float32 = 4 bytes
    }
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    // Dimension validation
    if (_detectedDimension == null) {
      _detectedDimension = embedding.length;
    } else if (embedding.length != _detectedDimension) {
      throw ArgumentError(
        'Embedding dimension mismatch: expected $_detectedDimension, '
        'got ${embedding.length}',
      );
    }

    final blob = _embeddingToBlob(embedding);

    _db!.execute(
      'INSERT OR REPLACE INTO $_tableName (id, content, embedding, metadata) '
      'VALUES (?, ?, ?, ?)',
      [id, content, blob, metadata],
    );

    try {
      _hnswIndex.add(id, embedding);
    } catch (e) {
      // Keep SQLite and HNSW in sync — remove from SQLite if HNSW add fails
      _db!.execute('DELETE FROM $_tableName WHERE id = ?', [id]);
      rethrow;
    }
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    if (_detectedDimension != null &&
        queryEmbedding.length != _detectedDimension) {
      throw ArgumentError(
        'Query dimension mismatch: expected $_detectedDimension, '
        'got ${queryEmbedding.length}',
      );
    }

    // Use HNSW for large datasets
    if (enableHnsw && _hnswIndex.count >= _hnswThreshold) {
      return _searchWithHnsw(queryEmbedding, topK, threshold);
    }

    // Brute-force for small datasets
    return _searchBruteForce(queryEmbedding, topK, threshold);
  }

  List<RetrievalResult> _searchBruteForce(
    List<double> queryEmbedding,
    int topK,
    double threshold,
  ) {
    final rows = _db!.select(
      'SELECT id, content, embedding, metadata FROM $_tableName',
    );

    final results = <(RetrievalResult, double)>[];
    for (final row in rows) {
      final embedding = _blobToEmbedding(row['embedding'] as Uint8List);
      final similarity = _cosineSimilarity(queryEmbedding, embedding);
      if (similarity >= threshold) {
        results.add((
          RetrievalResult(
            id: row['id'] as String,
            content: row['content'] as String,
            similarity: similarity,
            metadata: row['metadata'] as String?,
          ),
          similarity,
        ));
      }
    }

    results.sort((a, b) => b.$2.compareTo(a.$2));
    return results.take(topK).map((r) => r.$1).toList();
  }

  Future<List<RetrievalResult>> _searchWithHnsw(
    List<double> queryEmbedding,
    int topK,
    double threshold,
  ) async {
    final hnswResults = _hnswIndex.search(
      queryEmbedding,
      topK,
      threshold: threshold,
    );
    if (hnswResults.isEmpty) return [];

    final ids = hnswResults.map((r) => r.id).toList();
    final placeholders = ids.map((_) => '?').join(',');
    final rows = _db!.select(
      'SELECT id, content, metadata FROM $_tableName '
      'WHERE id IN ($placeholders)',
      ids,
    );

    final docMap = {for (var row in rows) row['id'] as String: row};

    return hnswResults
        .where((r) => docMap.containsKey(r.id))
        .map(
          (r) => RetrievalResult(
            id: r.id,
            content: docMap[r.id]!['content'] as String,
            similarity: r.similarity,
            metadata: docMap[r.id]!['metadata'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<VectorStoreStats> getStats() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    final result = _db!.select('SELECT COUNT(*) as count FROM $_tableName');
    final count = result.first['count'] as int;

    return VectorStoreStats(
      documentCount: count,
      vectorDimension: (_detectedDimension ?? 0).toInt(),
    );
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    _db!.execute('DELETE FROM $_tableName');
    _detectedDimension = null;
    _hnswIndex.clear();
  }

  @override
  Future<void> close() async {
    if (!_isInitialized) return;

    _db?.close();
    _db = null;
    _hnswIndex.clear();
    _isInitialized = false;
    _detectedDimension = null;
  }

  // === HNSW Rebuild ===

  Future<void> _rebuildHnswIndex() async {
    try {
      final rows = _db!.select(
        'SELECT id, embedding FROM $_tableName',
      );

      if (rows.isEmpty) {
        _hnswIndex.clear();
        return;
      }

      final docs = rows
          .map(
            (row) => DocumentEmbedding(
              id: row['id'] as String,
              embedding: _blobToEmbedding(row['embedding'] as Uint8List),
            ),
          )
          .toList();

      _hnswIndex.rebuild(docs);
      debugPrint(
        '[DartVectorStore] HNSW index rebuilt with ${docs.length} documents',
      );
    } catch (e) {
      debugPrint(
        '[DartVectorStore] Warning: Failed to rebuild HNSW index: $e',
      );
      _hnswIndex.clear();
    }
  }

  // === BLOB Encoding (float32 little-endian, same as Kotlin/Swift) ===

  static Uint8List _embeddingToBlob(List<double> embedding) {
    final buffer = ByteData(embedding.length * 4);
    for (int i = 0; i < embedding.length; i++) {
      buffer.setFloat32(i * 4, embedding[i].toDouble(), Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  static List<double> _blobToEmbedding(Uint8List blob) {
    final buffer = ByteData.sublistView(blob);
    return List.generate(
      blob.length ~/ 4,
      (i) => buffer.getFloat32(i * 4, Endian.little).toDouble(),
    );
  }

  // === Cosine Similarity (identical to all platforms) ===

  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}
