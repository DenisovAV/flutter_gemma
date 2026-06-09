import 'dart:io';

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileSource directory validation', () {
    test('accepts non-empty local model directories', () async {
      final modelDir = await Directory.systemTemp.createTemp('mlx-model-');
      addTearDown(() => modelDir.delete(recursive: true));
      await File('${modelDir.path}/config.json').writeAsString('{}');
      await File('${modelDir.path}/model.safetensors').writeAsString('weights');

      final spec = InferenceModelSpec(
        name: 'MLX model',
        modelSource: ModelSource.file(modelDir.path),
        modelType: ModelType.qwen3,
      );

      expect(await ModelFileSystemManager.validateModelFiles(spec), isTrue);
    });

    test('rejects empty local model directories', () async {
      final modelDir =
          await Directory.systemTemp.createTemp('mlx-model-empty-');
      addTearDown(() => modelDir.delete(recursive: true));

      final spec = InferenceModelSpec(
        name: 'Empty MLX model',
        modelSource: ModelSource.file(modelDir.path),
        modelType: ModelType.qwen3,
      );

      expect(await ModelFileSystemManager.validateModelFiles(spec), isFalse);
    });
  });
}
