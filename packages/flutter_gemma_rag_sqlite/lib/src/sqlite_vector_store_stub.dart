import 'package:flutter_gemma/flutter_gemma.dart';

/// Stub for SqliteVectorStore on web/WASM platforms.
/// Web uses WebSqliteVectorStore (wa-sqlite) instead.
class SqliteVectorStore implements VectorStoreRepository {
  @override
  bool get isInitialized => false;

  @override
  bool enableHnsw = true;

  @override
  Future<void> initialize(String databasePath) async => throw UnimplementedError(
      'SqliteVectorStore is not available on web; use WebSqliteVectorStore');

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async =>
      throw UnimplementedError(
          'SqliteVectorStore is not available on web; use WebSqliteVectorStore');

  @override
  Future<void> removeDocument({required String id}) async =>
      throw UnimplementedError(
          'SqliteVectorStore is not available on web; use WebSqliteVectorStore');

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
    Filter? filter,
  }) async =>
      throw UnimplementedError(
          'SqliteVectorStore is not available on web; use WebSqliteVectorStore');

  @override
  Future<VectorStoreStats> getStats() async => throw UnimplementedError(
      'SqliteVectorStore is not available on web; use WebSqliteVectorStore');

  @override
  Future<void> clear() async => throw UnimplementedError(
      'SqliteVectorStore is not available on web; use WebSqliteVectorStore');

  @override
  Future<void> close() async {}
}
