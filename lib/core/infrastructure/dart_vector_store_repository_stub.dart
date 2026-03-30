import '../services/vector_store_repository.dart';

VectorStoreRepository createDartVectorStoreRepository() {
  throw UnsupportedError(
    'DartVectorStoreRepository is not supported on web. '
    'Use WebVectorStoreRepository instead.',
  );
}
