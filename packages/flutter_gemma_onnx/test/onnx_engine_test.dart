import 'dart:io';

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_gen_ai_client.dart';

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
  });

  group('OnnxEngine.createModel', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('onnx_engine_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'throws a clear StateError when genai_config.json is missing',
      () async {
        final client = FakeGenAiClient();
        final engine = OnnxEngine(clientFactory: () => client);
        final modelFile = File('${tempDir.path}/model.onnx')
          ..writeAsStringSync('not a real model');
        final config = RuntimeConfig(
          maxTokens: 1024,
          modelPath: modelFile.path,
        );

        await expectLater(
          engine.createModel(_spec(ModelFileType.onnx), config),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('genai_config.json'),
            ),
          ),
        );
        // The precheck fails before ever touching the client.
        expect(client.loadCalls, 0);
      },
    );

    test('loads the client from the model file\'s parent directory and returns '
        'a bare OnnxInferenceModel', () async {
      final client = FakeGenAiClient();
      final engine = OnnxEngine(clientFactory: () => client);
      File(
        '${tempDir.path}/genai_config.json',
      ).writeAsStringSync('{"model": {}}');
      final modelFile = File('${tempDir.path}/model.onnx')
        ..writeAsStringSync('not a real model');
      final config = RuntimeConfig(maxTokens: 1024, modelPath: modelFile.path);

      final model = await engine.createModel(_spec(ModelFileType.onnx), config);

      expect(client.loadCalls, 1);
      expect(client.loadedModelDir, tempDir.path);
      expect(client.loadedContextWindow, 1024);
      expect(model, isA<OnnxInferenceModel>());
      expect(model.fileType, ModelFileType.onnx);
      expect(model.maxTokens, 1024);
    });
  });
}
