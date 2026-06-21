// Compile-only contract test: verifies OrtClient interface is importable
// and that no web-incompatible symbols are pulled in at the type level.
// This test does NOT run ONNX inference (no model file available in CI).
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OnnxEmbeddingBackend is importable', () {
    // Just instantiating a reference to the type is sufficient — if this
    // compiles, the conditional-import + web platform wiring is correct.
    expect(OnnxEmbeddingBackend.new, isNotNull);
  });
}
