import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
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

  // Windows/Linux have no native arm; createModel must fail with the package's
  // own exception, not the pigeon channel-error a host-less call would throw.
  test('createModel on Windows throws BuiltInAiUnavailableException', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await expectLater(
      const BuiltInAiEngine().createModel(
        BuiltInAiModels.geminiNano,
        const RuntimeConfig(maxTokens: 1024, modelPath: ''),
      ),
      throwsA(
        isA<BuiltInAiUnavailableException>().having(
          (e) => e.status,
          'status',
          BuiltInAiAvailability.unavailableDeviceUnsupported,
        ),
      ),
    );
  });
}
