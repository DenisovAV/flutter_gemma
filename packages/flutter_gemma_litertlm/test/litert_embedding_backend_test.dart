// Moved from flutter_gemma_embeddings/test/litert_embedding_backend_test.dart
// (embedder decoupling plan Task 4/5 — LiteRtEmbeddingBackend now lives in
// this package).

import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LiteRtEmbeddingBackend identity', () {
    const b = LiteRtEmbeddingBackend();
    expect(b.name, 'LiteRT Embedding');
    expect(b.priority, 0);
  });
}
