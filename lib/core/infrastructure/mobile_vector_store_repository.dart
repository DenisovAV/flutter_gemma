import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/infrastructure/hnsw_vector_index.dart';
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Mobile implementation of VectorStoreRepository using Pigeon + HNSW
///
/// **Architecture**:
/// ```
/// MobileVectorStoreRepository (Dart)
///         ↓ (HNSW for fast search)
/// HnswVectorIndex (in-memory, O(log n))
///         ↓ (Pigeon Platform Channel for persistence)
/// PlatformService (generated)
///         ↓
/// iOS: VectorStore.swift (SQLite3 C API)
/// Android: VectorStore.kt (SQLiteOpenHelper)
/// ```
///
/// **Design Principles**:
/// - SQLite = source of truth (persistence)
/// - HNSW = cache (fast search, rebuilt on initialize)
/// - Hybrid search: HNSW candidates → exact similarity recalculation
///
/// **State Management**:
/// - [_isInitialized]: Tracks whether initialize() was called
/// - [_hnswIndex]: In-memory HNSW index for O(log n) search
class MobileVectorStoreRepository implements VectorStoreRepository {
  final PlatformService _platformService;
  final HnswVectorIndex _hnswIndex = HnswVectorIndex();
  bool _isInitialized = false;

  /// Minimum document count to use HNSW
  /// Below this threshold, brute-force is fast enough
  static const int _hnswThreshold = 100;

  /// Creates repository with optional custom PlatformService (for testing)
  MobileVectorStoreRepository({
    PlatformService? platformService,
  }) : _platformService = platformService ?? PlatformService();

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(String databasePath) async {
    try {
      // 1. Initialize native SQLite
      await _platformService.initializeVectorStore(databasePath);
      _isInitialized = true;

      // 2. Rebuild HNSW index from SQLite data
      await _rebuildHnswIndex();
    } catch (e) {
      throw VectorStoreException('Failed to initialize vector store', e);
    }
  }

  /// Rebuild HNSW index from SQLite data
  ///
  /// Called during initialize() to restore index after app restart
  Future<void> _rebuildHnswIndex() async {
    try {
      final documents = await _platformService.getAllDocumentsWithEmbeddings();

      if (documents.isEmpty) {
        _hnswIndex.clear();
        return;
      }

      // Convert Pigeon types to HNSW types
      final hnswDocs = documents.map((doc) => DocumentEmbedding(
        id: doc.id,
        embedding: doc.embedding,
      )).toList();

      _hnswIndex.rebuild(hnswDocs);

      debugPrint('[MobileVectorStore] HNSW index rebuilt with ${documents.length} documents');
    } catch (e) {
      // Log but don't fail - fallback to brute-force search
      debugPrint('[MobileVectorStore] Warning: Failed to rebuild HNSW index: $e');
      _hnswIndex.clear();
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

    try {
      // 1. Persist to SQLite (source of truth)
      await _platformService.addDocument(
        id: id,
        content: content,
        embedding: embedding,
        metadata: metadata,
      );

      // 2. Add to HNSW index (cache)
      try {
        _hnswIndex.add(id, embedding);
      } catch (e) {
        // Log but don't fail - HNSW is optional optimization
        debugPrint('[MobileVectorStore] Warning: Failed to add to HNSW: $e');
      }
    } catch (e) {
      // Native code already validates dimension and throws appropriate errors
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

    try {
      // Use HNSW if index has enough documents
      if (_hnswIndex.count >= _hnswThreshold) {
        return await _searchWithHnsw(queryEmbedding, topK, threshold);
      }

      // Fallback to brute-force for small datasets
      return await _platformService.searchSimilar(
        queryEmbedding: queryEmbedding,
        topK: topK,
        threshold: threshold,
      );
    } catch (e) {
      throw VectorStoreException('Search failed', e);
    }
  }

  /// Search using HNSW index with exact similarity recalculation
  ///
  /// Strategy:
  /// 1. HNSW returns candidate IDs (approximate, fast)
  /// 2. Fetch full documents from SQLite by IDs
  /// 3. Recalculate exact cosine similarity
  /// 4. Filter by threshold and sort
  Future<List<RetrievalResult>> _searchWithHnsw(
    List<double> queryEmbedding,
    int topK,
    double threshold,
  ) async {
    // 1. Get candidates from HNSW (already has exact similarity calculated)
    final hnswResults = _hnswIndex.search(
      queryEmbedding,
      topK,
      threshold: threshold,
    );

    if (hnswResults.isEmpty) {
      return [];
    }

    // 2. Fetch full documents from SQLite
    final ids = hnswResults.map((r) => r.id).toList();
    final documents = await _platformService.getDocumentsByIds(ids);

    // 3. Build result map for fast lookup
    final docMap = {for (var doc in documents) doc.id: doc};

    // 4. Combine HNSW similarity with document content
    // HNSW already calculated exact similarity, so we use it directly
    return hnswResults
        .where((r) => docMap.containsKey(r.id))
        .map((r) => RetrievalResult(
              id: r.id,
              content: docMap[r.id]!.content,
              similarity: r.similarity,
              metadata: docMap[r.id]!.metadata,
            ))
        .toList();
  }

  @override
  Future<VectorStoreStats> getStats() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      return await _platformService.getVectorStoreStats();
    } catch (e) {
      throw VectorStoreException('Failed to get stats', e);
    }
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      // 1. Clear SQLite
      await _platformService.clearVectorStore();

      // 2. Clear HNSW index
      _hnswIndex.clear();
    } catch (e) {
      throw VectorStoreException('Failed to clear vector store', e);
    }
  }

  @override
  Future<void> close() async {
    if (!_isInitialized) {
      return; // Idempotent: Safe to call when not initialized
    }

    try {
      await _platformService.closeVectorStore();
      _hnswIndex.clear();
      _isInitialized = false;
    } catch (e) {
      // Best-effort cleanup: Even if native close() fails,
      // mark as uninitialized to prevent further operations
      _hnswIndex.clear();
      _isInitialized = false;
      throw VectorStoreException('Failed to close vector store', e);
    }
  }
}
