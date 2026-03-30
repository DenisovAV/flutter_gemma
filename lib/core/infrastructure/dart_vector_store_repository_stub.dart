import '../services/vector_store_repository.dart';

class DartVectorStoreRepository implements VectorStoreRepository {
  DartVectorStoreRepository([dynamic db]) {
    throw UnsupportedError('DartVectorStoreRepository is not available on web.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('DartVectorStoreRepository is not available on web.');
}
