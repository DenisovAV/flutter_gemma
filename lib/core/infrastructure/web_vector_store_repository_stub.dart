import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Web stub for VectorStoreRepository
///
/// This stub is used on non-web platforms where dart:js_interop is not available.
/// The actual web implementation is in web_vector_store_repository.dart (Phase 2).
class WebVectorStoreRepository implements VectorStoreRepository {
  @override
  bool get isInitialized => false;

  @override
  Future<void> initialize(String databasePath) async {
    throw UnimplementedError('WebVectorStoreRepository not implemented yet (Phase 2)');
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    throw UnimplementedError('WebVectorStoreRepository not implemented yet (Phase 2)');
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async {
    throw UnimplementedError('WebVectorStoreRepository not implemented yet (Phase 2)');
  }

  @override
  Future<VectorStoreStats> getStats() async {
    throw UnimplementedError('WebVectorStoreRepository not implemented yet (Phase 2)');
  }

  @override
  Future<void> clear() async {
    throw UnimplementedError('WebVectorStoreRepository not implemented yet (Phase 2)');
  }

  @override
  Future<void> close() async {
    // No-op for stub
  }
}
