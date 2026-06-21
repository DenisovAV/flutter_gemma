// Compile-only contract test: verifies the package's public API is importable
// on the Dart VM. This does NOT substitute for `flutter build web` — running on
// the VM will NOT catch dart:ffi / dart:io imports that compile here but fail
// dart2js. The true web gate is the `flutter build web` step on the example app.
// This test also does NOT run ONNX inference (no model file in CI).
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OnnxEmbeddingBackend is importable', () {
    // Just instantiating a reference to the type is sufficient — if this
    // compiles, the conditional-import + web platform wiring is correct.
    expect(OnnxEmbeddingBackend.new, isNotNull);
  });
}
