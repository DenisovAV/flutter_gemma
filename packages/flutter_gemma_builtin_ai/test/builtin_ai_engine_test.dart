import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine identity', () {
    const engine = BuiltInAiEngine();
    expect(engine.name, 'BuiltInAI');
    expect(engine.priority, 0);
  });

  test('canHandle matches only builtIn specs', () {
    const engine = BuiltInAiEngine();
    expect(engine.canHandle(BuiltInAiModels.geminiNano), isTrue);
    expect(engine.canHandle(BuiltInAiModels.appleFoundationModels), isTrue);
    final taskSpec = InferenceModelSpec(
      name: 'x',
      modelSource: ModelSource.network('https://example.com/m.task'),
      modelType: ModelType.general,
      fileType: ModelFileType.task,
    );
    expect(engine.canHandle(taskSpec), isFalse);
  });

  test('specs carry inert bundled source', () {
    expect(
      BuiltInAiModels.geminiNano.modelSource,
      ModelSource.bundled('gemini-nano'),
    );
    expect(BuiltInAiModels.geminiNano.fileType, ModelFileType.builtIn);
    expect(BuiltInAiModels.geminiNano.name, 'gemini-nano');
    expect(BuiltInAiModels.geminiNano.modelType, ModelType.general);
    expect(
      BuiltInAiModels.appleFoundationModels.name,
      'apple-foundation-models',
    );
    expect(
      BuiltInAiModels.appleFoundationModels.modelSource,
      ModelSource.bundled('apple-foundation-models'),
    );
    expect(
      BuiltInAiModels.appleFoundationModels.fileType,
      ModelFileType.builtIn,
    );
  });
}
