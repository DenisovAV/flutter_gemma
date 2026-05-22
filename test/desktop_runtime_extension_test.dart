import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInferenceModel extends InferenceModel {
  _FakeInferenceModel({this.maxTokensValue = 42});

  final int maxTokensValue;
  bool closed = false;

  @override
  InferenceModelSession? get session => null;

  @override
  InferenceChat? chat;

  @override
  int get maxTokens => maxTokensValue;

  @override
  ModelFileType get fileType => ModelFileType.task;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _FakeEmbeddingModel extends EmbeddingModel {
  bool closed = false;

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    return [text.length.toDouble()];
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    return texts.map((text) => [text.length.toDouble()]).toList();
  }

  @override
  Future<int> getDimension() async => 1;

  @override
  Future<void> close() async {
    closed = true;
  }
}

InferenceModelSpec _inferenceSpec() => InferenceModelSpec(
      name: 'Qwen3 MLX',
      modelSource: ModelSource.file('/tmp/qwen3-router-mlx'),
      modelType: ModelType.qwen3,
      fileType: ModelFileType.task,
    );

void main() {
  group('DesktopRuntimeRegistry', () {
    late DesktopRuntimeRegistry registry;

    setUp(() {
      registry = DesktopRuntimeRegistry();
    });

    test('uses the first extension that returns a model', () async {
      registry.register(
        DesktopRuntimeExtension(
          name: 'skip',
          createInferenceModel: (_) => null,
        ),
      );
      registry.register(
        DesktopRuntimeExtension(
          name: 'mlx',
          createInferenceModel: (_) async => _FakeInferenceModel(),
        ),
      );

      final model = await registry.createInferenceModel(
        DesktopInferenceRequest(
          spec: _inferenceSpec(),
          modelPath: '/tmp/qwen3-router-mlx',
          modelType: ModelType.qwen3,
          fileType: ModelFileType.task,
          maxTokens: 256,
          cacheDir: '/tmp/cache',
        ),
      );

      expect(model, isA<_FakeInferenceModel>());
    });

    test(
      'managed inference model forwards close to lifecycle callback once',
      () async {
        final fakeModel = _FakeInferenceModel();
        var closeCalls = 0;
        registry.register(
          DesktopRuntimeExtension(
            name: 'mlx',
            createInferenceModel: (_) async => fakeModel,
          ),
        );

        final model = await registry.createManagedInferenceModel(
          DesktopInferenceRequest(
            spec: _inferenceSpec(),
            modelPath: '/tmp/qwen3-router-mlx',
            modelType: ModelType.qwen3,
            fileType: ModelFileType.task,
            maxTokens: 256,
            cacheDir: '/tmp/cache',
          ),
          onClose: () => closeCalls++,
        );

        expect(model, isNotNull);
        await model!.close();
        await model.close();

        expect(fakeModel.closed, isTrue);
        expect(closeCalls, 1);
      },
    );

    test(
      'managed embedding model forwards close to lifecycle callback once',
      () async {
        final fakeModel = _FakeEmbeddingModel();
        var closeCalls = 0;
        registry.register(
          DesktopRuntimeExtension(
            name: 'mlx-embedding',
            createEmbeddingModel: (_) async => fakeModel,
          ),
        );

        final model = await registry.createManagedEmbeddingModel(
          const DesktopEmbeddingRequest(
            modelPath: '/tmp/gecko-mlx',
            tokenizerPath: '/tmp/gecko-tokenizer.json',
          ),
          onClose: () => closeCalls++,
        );

        expect(model, isNotNull);
        await model!.close();
        await model.close();

        expect(fakeModel.closed, isTrue);
        expect(closeCalls, 1);
      },
    );

    test('register replaces extension with same name', () async {
      registry.register(
        DesktopRuntimeExtension(
          name: 'mlx',
          createInferenceModel: (_) async => null,
        ),
      );
      registry.register(
        DesktopRuntimeExtension(
          name: 'mlx',
          createInferenceModel: (_) async =>
              _FakeInferenceModel(maxTokensValue: 7),
        ),
      );

      final model = await registry.createInferenceModel(
        DesktopInferenceRequest(
          spec: _inferenceSpec(),
          modelPath: '/tmp/qwen3-router-mlx',
          modelType: ModelType.qwen3,
          fileType: ModelFileType.task,
          maxTokens: 256,
          cacheDir: '/tmp/cache',
        ),
      );

      expect((model as _FakeInferenceModel).maxTokens, 7);
      expect(registry.extensions, hasLength(1));
    });
  });
}
