import 'package:flutter_gemma/flutter_gemma.dart';

/// Web stub for [QdrantVectorStore].
///
/// qdrant-edge depends on mmap/parking_lot and cannot compile to
/// WebAssembly, so on the Web target the real implementation is
/// unavailable. ServiceRegistry routes Web traffic to
/// WebVectorStoreRepository (wa-sqlite + HNSW) and never constructs
/// this stub; it exists only so that conditional imports in
/// service_registry.dart link cleanly on Web.
class QdrantVectorStore implements VectorStoreRepository {
  @override
  bool get isInitialized => false;

  @override
  bool enableHnsw = true;

  @override
  Future<void> initialize(String databasePath) async =>
      throw UnimplementedError(
          'QdrantVectorStore is native-only; qdrant-edge cannot run on web');

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async =>
      throw UnimplementedError(
          'QdrantVectorStore is native-only; qdrant-edge cannot run on web');

  @override
  Future<void> removeDocument({required String id}) async =>
      throw UnimplementedError(
          'QdrantVectorStore is native-only; qdrant-edge cannot run on web');

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
    Filter? filter,
  }) async =>
      throw UnimplementedError(
          'QdrantVectorStore is native-only; qdrant-edge cannot run on web');

  @override
  Future<VectorStoreStats> getStats() async => throw UnimplementedError(
      'QdrantVectorStore is native-only; qdrant-edge cannot run on web');

  @override
  Future<void> clear() async => throw UnimplementedError(
      'QdrantVectorStore is native-only; qdrant-edge cannot run on web');

  @override
  Future<void> close() async {}
}
