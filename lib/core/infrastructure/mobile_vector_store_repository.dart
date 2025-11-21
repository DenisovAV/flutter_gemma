import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Mobile implementation of VectorStoreRepository using Pigeon
///
/// **Architecture**:
/// ```
/// MobileVectorStoreRepository (Dart)
///         ↓ (Pigeon Platform Channel)
/// PlatformService (generated)
///         ↓
/// iOS: VectorStore.swift (SQLite3 C API)
/// Android: VectorStore.kt (SQLiteOpenHelper)
/// ```
///
/// **Design Principles**:
/// - Thin wrapper: Delegates all logic to native implementations
/// - No business logic: Just state management and error translation
/// - Testable: PlatformService can be mocked
///
/// **State Management**:
/// - [_isInitialized]: Tracks whether initialize() was called
/// - Prevents operations before initialization
class MobileVectorStoreRepository implements VectorStoreRepository {
  final PlatformService _platformService;
  bool _isInitialized = false;

  /// Creates repository with optional custom PlatformService (for testing)
  MobileVectorStoreRepository({
    PlatformService? platformService,
  }) : _platformService = platformService ?? PlatformService();

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(String databasePath) async {
    try {
      await _platformService.initializeVectorStore(databasePath);
      _isInitialized = true;
    } catch (e) {
      throw VectorStoreException('Failed to initialize vector store', e);
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
      await _platformService.addDocument(
        id: id,
        content: content,
        embedding: embedding,
        metadata: metadata,
      );
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
      return await _platformService.searchSimilar(
        queryEmbedding: queryEmbedding,
        topK: topK,
        threshold: threshold,
      );
    } catch (e) {
      throw VectorStoreException('Search failed', e);
    }
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
      await _platformService.clearVectorStore();
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
      _isInitialized = false;
    } catch (e) {
      // Best-effort cleanup: Even if native close() fails,
      // mark as uninitialized to prevent further operations
      _isInitialized = false;
      throw VectorStoreException('Failed to close vector store', e);
    }
  }
}
