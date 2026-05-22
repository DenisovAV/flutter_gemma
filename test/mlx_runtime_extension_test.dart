import 'dart:io';

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/desktop/mlx_inference_model.dart';
import 'package:flutter_gemma/desktop/mlx_native_dispatch.dart';
import 'package:flutter_gemma/desktop/mlx_runtime_extension.dart';
import 'package:flutter_test/flutter_test.dart';

InferenceModelSpec _inferenceSpec(String modelPath) => InferenceModelSpec(
      name: 'Qwen3 MLX',
      modelSource: ModelSource.file(modelPath),
      modelType: ModelType.qwen3,
      fileType: ModelFileType.task,
    );

void main() {
  group('built-in MLX runtime extension', () {
    test('selects MLX for directory-backed local models', () async {
      final modelDir = await Directory.systemTemp.createTemp('mlx-model-');
      addTearDown(() => modelDir.delete(recursive: true));

      final extension = createBuiltInMlxRuntimeExtension(
        dispatcher: RecordingMlxDispatcher(),
      );

      final model = await extension.createInferenceModel!(
        DesktopInferenceRequest(
          spec: _inferenceSpec(modelDir.path),
          modelPath: modelDir.path,
          modelType: ModelType.qwen3,
          fileType: ModelFileType.task,
          maxTokens: 256,
          cacheDir: '/tmp/cache',
        ),
      );

      expect(model, isA<MlxInferenceModel>());
    });
  });

  group('MLX inference model', () {
    test('sends structured chat history through the dispatcher', () async {
      final dispatcher = RecordingMlxDispatcher()
        ..onInvoke = (operation, payload) {
          expect(operation, 'lm.generate');
          return <String, Object?>{
            'ok': true,
            'text': '{"command":"create_note"}',
            'swiftLoadMs': 5,
            'swiftFirstTokenMs': 12,
            'swiftGenerateMs': 40,
          };
        };

      final model = MlxInferenceModel(
        dispatcher: dispatcher,
        modelPath: '/tmp/qwen3-router-mlx',
        maxTokens: 256,
        modelType: ModelType.qwen3,
        fileType: ModelFileType.task,
        onClose: () {},
      );

      final session = await model.createSession(
        systemInstruction: 'Route user requests to board commands.',
      );
      await session.addQueryChunk(Message.text(text: 'hello', isUser: true));
      await session.addQueryChunk(Message.text(text: 'hi', isUser: false));
      await session.addQueryChunk(
        Message.text(text: 'create a note called inbox', isUser: true),
      );

      final response = await session.getResponse();

      expect(response, '{"command":"create_note"}');
      expect(dispatcher.calls, hasLength(1));
      expect(
        dispatcher.calls.single.payload['messages'],
        <Map<String, String>>[
          {
            'role': 'system',
            'content': 'Route user requests to board commands.',
          },
          {'role': 'user', 'content': 'hello'},
          {'role': 'assistant', 'content': 'hi'},
          {'role': 'user', 'content': 'create a note called inbox'},
        ],
      );

      final metrics = session.getSessionMetrics();
      expect(metrics.timeToFirstTokenMs, 12);
      expect(metrics.initTimeMs, 5);
      expect(metrics.outputTokens, greaterThan(0));
    });

    test('async response yields the generated text once', () async {
      final dispatcher = RecordingMlxDispatcher()
        ..onInvoke = (_, __) => <String, Object?>{
              'ok': true,
              'text': 'ok',
            };

      final model = MlxInferenceModel(
        dispatcher: dispatcher,
        modelPath: '/tmp/qwen3-router-mlx',
        maxTokens: 64,
        modelType: ModelType.qwen3,
        fileType: ModelFileType.task,
        onClose: () {},
      );

      final session = await model.createSession();
      await session.addQueryChunk(Message.text(text: 'ping', isUser: true));

      expect(await session.getResponseAsync().toList(), ['ok']);
    });
  });
}
