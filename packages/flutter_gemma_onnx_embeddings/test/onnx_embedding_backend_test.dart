import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';

void main() {
  test('OnnxEmbeddingBackend has stable identity', () {
    const b = OnnxEmbeddingBackend();
    expect(b.name, 'ONNX Embedding');
    expect(b.priority, 0);
  });
}
