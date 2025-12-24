import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma/web/vector_store_web.dart';
import 'dart:js_interop';

/// Web implementation of VectorStoreRepository using SQLite WASM
///
/// **Architecture**:
/// ```
/// WebVectorStoreRepository (Dart)
///         ↓ (JS Interop)
/// vector_store_web.dart
///         ↓ (wa-sqlite)
/// sqlite_vector_store.js
///         ↓ (WASM + OPFS)
/// SQLite Database
/// ```
///
/// **Design Principles**:
/// - Thin wrapper: Delegates all logic to JS implementation
/// - Type-safe: Uses extension types for JS interop
/// - Error translation: JS errors → VectorStoreException
/// - SOLID: Separation of concerns (Dart state + JS business logic)
///
/// **State Management**:
/// - [_isInitialized]: Tracks whether initialize() was called
/// - [_store]: SQLiteVectorStore JS instance
///
/// **Performance**:
/// - OPFS storage: ~3-4x faster than IndexedDB
/// - BLOB format: ~70% smaller than JSON
/// - Search: ~10-20ms for 1k vectors
class WebVectorStoreRepository implements VectorStoreRepository {
  SQLiteVectorStore? _store;
  bool _isInitialized = false;

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
    } catch (e) {
      throw VectorStoreException('Failed to initialize SQLite WASM', e);
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
      await _store!.addDocumentDart(id, content, embedding, metadata);
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
      return await _store!.searchSimilarDart(queryEmbedding, topK, threshold);
    } catch (e) {
      throw VectorStoreException('Search failed', e);
    }
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
      await _store!.clear().toDart;
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
      _isInitialized = false;
    } catch (e) {
      // Best-effort cleanup: Even if close() fails,
      // mark as uninitialized to prevent further operations
      _store = null;
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
