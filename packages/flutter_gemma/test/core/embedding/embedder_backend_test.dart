import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_gemma/core/embedding/embedder_backend_notice.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/core/embedding/common_embedding_model.dart';
import 'package:flutter_gemma/core/embedding/forward_pass.dart';
import 'package:flutter_gemma/core/embedding/tokenizer_adapter.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nothing but the defaults, to pin what an implementation gets for free.
class _BareEmbedder extends EmbeddingModel {
  @override
  void addCloseListener(void Function() listener) {}
  @override
  Future<void> close() async {}
  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async => const [];
  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async => const [];
  @override
  Future<int> getDimension() async => 0;
}

void main() {
  ActiveEmbedderParams params({
    String model = '/m.tflite',
    String? tokenizer = '/t.json',
    PreferredBackend? backend,
  }) => ActiveEmbedderParams(
    modelPath: model,
    tokenizerPath: tokenizer,
    preferredBackend: backend,
  );

  group('ActiveEmbedderParams', () {
    test(
      'a different backend is NOT a difference — it builds the same model',
      () {
        // The whole point of normalizing to CPU: asking for GPU must not unload
        // and reload a bit-identical embedder. If this goes red, the
        // normalization line was dropped and every backend change costs a
        // 570-780 ms recompile for nothing.
        expect(
          params(
            backend: PreferredBackend.gpu,
          ).firstDifference(params(backend: PreferredBackend.cpu)),
          isNull,
        );
        expect(
          params().firstDifference(params(backend: PreferredBackend.npu)),
          isNull,
        );
      },
    );

    test('paths are differences, and the changed one is named', () {
      expect(
        params().firstDifference(params(model: '/other.tflite')),
        'modelPath',
      );
      expect(
        params().firstDifference(params(tokenizer: '/other.json')),
        'tokenizerPath',
      );
      expect(
        params().firstDifference(params(tokenizer: null)),
        'tokenizerPath',
        reason:
            'losing the tokenizer is a different embedder, not a null-safe no-op',
      );
    });

    test('identical requests compare equal', () {
      expect(params().firstDifference(params()), isNull);
    });

    test('isIgnoredBackend is true only for something CPU is not', () {
      expect(ActiveEmbedderParams.isIgnoredBackend(null), isFalse);
      expect(
        ActiveEmbedderParams.isIgnoredBackend(PreferredBackend.cpu),
        isFalse,
      );
      expect(
        ActiveEmbedderParams.isIgnoredBackend(PreferredBackend.gpu),
        isTrue,
      );
      expect(
        ActiveEmbedderParams.isIgnoredBackend(PreferredBackend.npu),
        isTrue,
      );
    });
  });

  group('noticeEmbedderBackendIgnored', () {
    late List<String> printed;
    late DebugPrintCallback original;

    setUp(() {
      resetEmbedderBackendNotice();
      printed = <String>[];
      original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
    });

    tearDown(() {
      debugPrint = original;
      gemmaLogLevel = GemmaLogLevel.info;
    });

    test('says nothing for the backend embeddings actually use', () {
      noticeEmbedderBackendIgnored(null);
      noticeEmbedderBackendIgnored(PreferredBackend.cpu);
      expect(printed, isEmpty);
    });

    test('names the requested backend, and points at the release channel', () {
      noticeEmbedderBackendIgnored(PreferredBackend.gpu);
      expect(printed, hasLength(1));
      expect(printed.single, contains('gpu'));
      expect(
        printed.single,
        contains('activeBackend'),
        reason: 'a debug line must hand over to something a release build has',
      );
    });

    test('a muted log does not spend the one shot', () {
      // The level is public API, and an app that starts silent and raises it
      // to debug this is the whole reason the flag must not burn early.
      gemmaLogLevel = GemmaLogLevel.none;
      noticeEmbedderBackendIgnored(PreferredBackend.gpu);
      expect(printed, isEmpty);

      gemmaLogLevel = GemmaLogLevel.info;
      noticeEmbedderBackendIgnored(PreferredBackend.gpu);
      expect(printed, hasLength(1), reason: 'the shot was still unspent');
    });

    test('says it once, and a reset lets it speak again', () {
      noticeEmbedderBackendIgnored(PreferredBackend.gpu);
      noticeEmbedderBackendIgnored(PreferredBackend.npu);
      expect(printed, hasLength(1), reason: 'once per isolate, not per call');

      resetEmbedderBackendNotice();
      noticeEmbedderBackendIgnored(PreferredBackend.npu);
      expect(printed, hasLength(2));
      expect(printed.last, contains('npu'));
    });
  });

  test(
    'the facade carries the engine\'s answer, it does not decide one',
    () async {
      // A descriptor claiming GPU must come back as GPU. If this goes red because
      // it answers `cpu`, the fact was moved back into the shared facade — and
      // then the next engine that really does use an accelerator is reported as
      // CPU with nothing to catch it.
      final model = await CommonEmbeddingModel.create(
        descriptor: ForwardPassDescriptor(
          engineTag: 'fake',
          modelPath: 'fake',
          factory: buildFakePass,
          tokenizerFactory: buildFakeTokenizer,
          outputContract: EmbeddingOutputContract.pooledFinal,
          activeBackend: PreferredBackend.gpu,
        ),
        tokenizerPath: 'fake',
      );
      addTearDown(model.close);
      expect(model.activeBackend, PreferredBackend.gpu);
    },
  );

  test('EmbeddingModel.activeBackend defaults to null, not to a guess', () {
    // Defaulted rather than abstract so an existing implementation of this
    // public interface keeps compiling. Null means "not known here".
    expect(_BareEmbedder().activeBackend, isNull);
  });
}

/// Minimal pass: the facade must carry whatever the descriptor declares, so the
/// pass itself only has to be loadable.
class _FakePass implements EmbeddingForwardPass {
  @override
  Future<void> load() async {}
  @override
  Future<void> close() async {}
  @override
  int get outputDimension => 2;
  @override
  int? get inputSequenceLength => null;
  @override
  EmbeddingOutputContract? get outputContract => null;
  @override
  Future<ForwardResult> run({
    required List<int> tokenIds,
    List<int>? attentionMask,
    List<int>? tokenTypeIds,
  }) async => const ForwardResult(values: [1.0, 0.0], shape: [1, 2]);
}

EmbeddingForwardPass buildFakePass(String modelPath) => _FakePass();

class _FakeTokenizer implements EmbeddingTokenizer {
  const _FakeTokenizer();
  @override
  TokenizedInput encode(String prefix, String text) =>
      const TokenizedInput(ids: [1, 2]);
}

Future<EmbeddingTokenizer> buildFakeTokenizer(String path) async =>
    const _FakeTokenizer();
