import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// Stub for DartVectorStoreRepository on web/WASM platforms.
/// Web uses WebVectorStoreRepository (wa-sqlite) instead.
class DartVectorStoreRepository implements VectorStoreRepository {
  @override
  bool get isInitialized => false;

  @override
  bool enableHnsw = true;

  @override
  Future<void> initialize(String databasePath) async =>
      throw UnimplementedError(
          'DartVectorStoreRepository is not available on web');

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async =>
      throw UnimplementedError(
          'DartVectorStoreRepository is not available on web');

  @override
  Future<void> removeDocument({required String id}) async =>
      throw UnimplementedError(
          'DartVectorStoreRepository is not available on web');

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async =>
      throw UnimplementedError(
          'DartVectorStoreRepository is not available on web');

  @override
  Future<VectorStoreStats> getStats() async => throw UnimplementedError(
      'DartVectorStoreRepository is not available on web');

  @override
  Future<void> clear() async => throw UnimplementedError(
      'DartVectorStoreRepository is not available on web');

  @override
  Future<void> close() async {}
}
