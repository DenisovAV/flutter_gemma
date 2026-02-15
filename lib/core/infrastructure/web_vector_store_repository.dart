import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/infrastructure/hnsw_vector_index.dart';
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma/web/vector_store_web.dart';
import 'dart:js_interop';

/// Web implementation of VectorStoreRepository using SQLite WASM + HNSW
///
/// **Architecture**:
/// ```
/// WebVectorStoreRepository (Dart)
///         ↓ (HNSW for fast search)
/// HnswVectorIndex (in-memory, O(log n))
///         ↓ (JS Interop for persistence)
/// vector_store_web.dart
///         ↓ (wa-sqlite)
/// sqlite_vector_store.js
///         ↓ (WASM + OPFS)
/// SQLite Database
/// ```
///
/// **Design Principles**:
/// - SQLite WASM = source of truth (persistence via OPFS)
/// - HNSW = cache (fast search, rebuilt on initialize)
/// - Hybrid search: HNSW candidates → exact similarity recalculation
///
/// **State Management**:
/// - [_isInitialized]: Tracks whether initialize() was called
/// - [_store]: SQLiteVectorStore JS instance
/// - [_hnswIndex]: In-memory HNSW index for O(log n) search
///
/// **Performance**:
/// - OPFS storage: ~3-4x faster than IndexedDB
/// - BLOB format: ~70% smaller than JSON
/// - HNSW search: O(log n) vs O(n) brute-force
class WebVectorStoreRepository implements VectorStoreRepository {
  SQLiteVectorStore? _store;
  final HnswVectorIndex _hnswIndex = HnswVectorIndex();
  bool _isInitialized = false;

  /// Minimum document count to use HNSW
  /// Below this threshold, brute-force is fast enough
  static const int _hnswThreshold = 100;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(String databasePath) async {
    try {
      // Wait for ES module to load (may take time due to top-level await)
      await _waitForSQLiteModule();

      // Create JS instance with auto-dimension detection (null = auto-detect)
      // Pass null as JSNumber? to constructor
      const JSNumber? dimension = null;
      _store = SQLiteVectorStore(dimension);

      // Initialize wa-sqlite WASM + OPFS
      await _store!.initialize(databasePath).toDart;

      _isInitialized = true;

      // Rebuild HNSW index from SQLite data
      await _rebuildHnswIndex();
    } catch (e) {
      throw VectorStoreException('Failed to initialize SQLite WASM', e);
    }
  }

  /// Rebuild HNSW index from SQLite data
  ///
  /// Called during initialize() to restore index after page reload
  Future<void> _rebuildHnswIndex() async {
    try {
      final documents = await _store!.getAllDocumentsWithEmbeddingsDart();

      if (documents.isEmpty) {
        _hnswIndex.clear();
        return;
      }

      // Convert web types to HNSW types
      final hnswDocs = documents.map((doc) => DocumentEmbedding(
        id: doc.id,
        embedding: doc.embedding,
      )).toList();

      _hnswIndex.rebuild(hnswDocs);

      debugPrint('[WebVectorStore] HNSW index rebuilt with ${documents.length} documents');
    } catch (e) {
      // Log but don't fail - fallback to brute-force search
      debugPrint('[WebVectorStore] Warning: Failed to rebuild HNSW index: $e');
      _hnswIndex.clear();
    }
  }

  /// Wait for SQLiteVectorStore ES module to finish loading
  ///
  /// ES modules with top-level await load asynchronously.
  /// This polls until window.SQLiteVectorStore is available.
  Future<void> _waitForSQLiteModule() async {
    const maxAttempts = 50;  // 5 seconds max
    const delay = Duration(milliseconds: 100);

    for (int i = 0; i < maxAttempts; i++) {
      try {
        _ensureSQLiteLoaded();
        // If we get here without exception, module is loaded
        return;
      } catch (_) {
        // Module not ready yet, wait and retry
        await Future.delayed(delay);
      }
    }

    throw StateError(
      'SQLiteVectorStore module failed to load after ${maxAttempts * delay.inMilliseconds}ms. '
      'Add <script type="module" src="sqlite_vector_store.js"></script> to index.html'
    );
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    if (!_isInitialized || _store == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      // 1. Persist to SQLite WASM (source of truth)
      await _store!.addDocumentDart(id, content, embedding, metadata);

      // 2. Add to HNSW index (cache)
      try {
        _hnswIndex.add(id, embedding);
      } catch (e) {
        // Log but don't fail - HNSW is optional optimization
        debugPrint('[WebVectorStore] Warning: Failed to add to HNSW: $e');
      }
    } catch (e) {
      // Dimension mismatch errors from JS are rethrown as-is
      // Other errors wrapped in VectorStoreException
      if (e.toString().contains('dimension mismatch')) {
        rethrow;
      }
      throw VectorStoreException('Failed to add document', e);
    }
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async {
    if (!_isInitialized || _store == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      // Use HNSW if index has enough documents
      if (_hnswIndex.count >= _hnswThreshold) {
        return await _searchWithHnsw(queryEmbedding, topK, threshold);
      }

      // Fallback to brute-force for small datasets
      return await _store!.searchSimilarDart(queryEmbedding, topK, threshold);
    } catch (e) {
      throw VectorStoreException('Search failed', e);
    }
  }

  /// Search using HNSW index with exact similarity recalculation
  ///
  /// Strategy:
  /// 1. HNSW returns candidate IDs (approximate, fast)
  /// 2. Fetch full documents from SQLite WASM by IDs
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

    // 2. Fetch full documents from SQLite WASM
    final ids = hnswResults.map((r) => r.id).toList();
    final documents = await _store!.getDocumentsByIdsDart(ids);

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
    if (!_isInitialized || _store == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      return await _store!.getStatsDart();
    } catch (e) {
      throw VectorStoreException('Failed to get stats', e);
    }
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized || _store == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      // 1. Clear SQLite WASM
      await _store!.clear().toDart;

      // 2. Clear HNSW index
      _hnswIndex.clear();
    } catch (e) {
      throw VectorStoreException('Failed to clear vector store', e);
    }
  }

  @override
  Future<void> close() async {
    if (!_isInitialized || _store == null) {
      return; // Idempotent: Safe to call when not initialized
    }

    try {
      await _store!.close().toDart;
      _store = null;
      _hnswIndex.clear();
      _isInitialized = false;
    } catch (e) {
      // Best-effort cleanup: Even if close() fails,
      // mark as uninitialized to prevent further operations
      _store = null;
      _hnswIndex.clear();
      _isInitialized = false;
      throw VectorStoreException('Failed to close vector store', e);
    }
  }

  // ========================================================================
  // Private Helpers
  // ========================================================================

  /// Verify SQLiteVectorStore JS class is loaded
  ///
  /// Throws [StateError] if sqlite_vector_store.js not loaded
  void _ensureSQLiteLoaded() {
    // Try to create a test instance - will throw if JS not loaded
    // This is the simplest way to check without unsafe JS interop
    try {
      const JSNumber? dimension = null;
      final testInstance = SQLiteVectorStore(dimension);
      // If we got here, module is loaded
      // Ignore the test instance
      testInstance; // suppress unused variable warning
    } catch (e) {
      throw StateError('SQLiteVectorStore not available: $e');
    }
  }
}
