import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LiteRtEmbeddingBackend identity', () {
    const b = LiteRtEmbeddingBackend();
    expect(b.name, 'LiteRT Embedding');
    expect(b.priority, 0);
  });
}
