import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';
import 'package:flutter_test/flutter_test.dart';

InferenceModelSpec _spec(ModelFileType fileType) => InferenceModelSpec(
  name: 'test-$fileType',
  modelSource: FileSource('/tmp/model-${fileType.name}'),
  modelType: ModelType.gemmaIt,
  fileType: fileType,
);

void main() {
  group('OnnxEngine identity', () {
    test('name is ONNX, priority is 0', () {
      const engine = OnnxEngine();
      expect(engine.name, 'ONNX');
      expect(engine.priority, 0);
    });

    test('canHandle is true only for ModelFileType.onnx', () {
      const engine = OnnxEngine();

      expect(engine.canHandle(_spec(ModelFileType.onnx)), isTrue);
      expect(engine.canHandle(_spec(ModelFileType.litertlm)), isFalse);
      expect(engine.canHandle(_spec(ModelFileType.task)), isFalse);
      expect(engine.canHandle(_spec(ModelFileType.binary)), isFalse);
      expect(engine.canHandle(_spec(ModelFileType.builtIn)), isFalse);
    });

    test(
      'createModel throws UnimplementedError (inference pending throughput gate)',
      () async {
        const engine = OnnxEngine();
        const config = RuntimeConfig(
          maxTokens: 1024,
          modelPath: '/tmp/model-dir',
        );

        await expectLater(
          engine.createModel(_spec(ModelFileType.onnx), config),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );
  });
}
