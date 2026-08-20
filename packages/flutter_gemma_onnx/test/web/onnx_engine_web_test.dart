// Unit tests for the web arm of `OnnxEngine` — pure Dart (no
// `dart:js_interop`), runs under plain `flutter test` (VM). Proves the
// fast-follow seam: same public shape as native, always declines for now.

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_onnx/src/web/onnx_engine_web.dart';
import 'package:flutter_test/flutter_test.dart';

InferenceModelSpec _spec(ModelFileType fileType) => InferenceModelSpec(
  name: 'test-$fileType',
  modelSource: FileSource('/tmp/model-${fileType.name}'),
  modelType: ModelType.gemmaIt,
  fileType: fileType,
);

void main() {
  group('OnnxEngine (web arm)', () {
    test("name/priority match the native arm's identity", () {
      const engine = OnnxEngine();
      expect(engine.name, 'ONNX');
      expect(engine.priority, 0);
    });

    test('canHandle always declines, even for a matching fileType', () {
      const engine = OnnxEngine();
      expect(engine.canHandle(_spec(ModelFileType.onnx)), isFalse);
    });

    test('canHandle declines a non-onnx fileType too', () {
      const engine = OnnxEngine();
      expect(engine.canHandle(_spec(ModelFileType.task)), isFalse);
    });

    test('createModel throws UnsupportedError (not yet implemented)', () async {
      const engine = OnnxEngine();
      final config = RuntimeConfig(maxTokens: 1024, modelPath: '/tmp/m.onnx');
      await expectLater(
        engine.createModel(_spec(ModelFileType.onnx), config),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
