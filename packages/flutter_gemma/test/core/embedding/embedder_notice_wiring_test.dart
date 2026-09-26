// Pins the WIRING of noticeEmbedderBackendIgnored, which the unit tests for the
// notice itself cannot see.
//
// Why each shell is driven DIRECTLY instead of through `FlutterGemma
// .getActiveEmbedder`: on a desktop test host `FlutterGemmaPlugin.instance`
// resolves to the desktop shell, and desktop was the one shell that already
// called the notice on its create path. A test that went through the facade
// would have been green while mobile and web stayed silent on the first — and
// usually only — call an app makes.
//
// Each case asks for an embedder with no active identity, so the call throws.
// That is deliberate: the notice must fire BEFORE anything else in
// createEmbeddingModel, so the throw proves nothing about the notice and the
// captured output proves everything.
//
// Run: flutter test test/core/embedding/embedder_notice_wiring_test.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/embedding/embedder_backend_notice.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/embedding_registry.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_gemma/desktop/flutter_gemma_desktop.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> printed;
  late DebugPrintCallback original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetEmbedderBackendNotice();
    printed = <String>[];
    original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
  });

  tearDown(() => debugPrint = original);

  Iterable<String> notices() =>
      printed.where((l) => l.contains('preferredBackend'));

  /// One call, no prior embedder — the shape an app actually uses.
  Future<void> firstCall(FlutterGemmaPlugin plugin) async {
    await expectLater(
      plugin.createEmbeddingModel(preferredBackend: PreferredBackend.gpu),
      throwsA(anything),
    );
  }

  group('the notice reaches the first call, not only a reuse', () {
    test('mobile', () async {
      await firstCall(FlutterGemmaMobile());
      expect(
        notices(),
        hasLength(1),
        reason:
            'a single getActiveEmbedder(preferredBackend:) is the ordinary '
            'shape; if it only speaks on the second call it never speaks',
      );
    });

    test('desktop', () async {
      await firstCall(FlutterGemmaDesktop.instance);
      expect(notices(), hasLength(1));
    });
  });

  group('explicit paths go through the same comparison', () {
    late _CountingBackend backend;

    setUp(() {
      EmbeddingRegistry.instance.reset();
      backend = _CountingBackend();
      EmbeddingRegistry.instance.registerAll([backend]);
    });

    tearDown(() => EmbeddingRegistry.instance.reset());

    test(
      'a different model file rebuilds instead of serving the cache',
      () async {
        final plugin = FlutterGemmaMobile();

        final first = await plugin.createEmbeddingModel(
          modelPath: '/a.tflite',
          tokenizerPath: '/a.json',
        );
        expect(backend.seenModelPaths, ['/a.tflite']);

        // Same file again: reuse, and the SAME instance.
        final again = await plugin.createEmbeddingModel(
          modelPath: '/a.tflite',
          tokenizerPath: '/a.json',
        );
        expect(backend.seenModelPaths, ['/a.tflite']);
        expect(identical(first, again), isTrue);

        // Different file: must rebuild. Returning the cache here is how a caller
        // asking for another model silently got the previous model's vectors.
        final second = await plugin.createEmbeddingModel(
          modelPath: '/b.tflite',
          tokenizerPath: '/b.json',
        );
        expect(backend.seenModelPaths, ['/a.tflite', '/b.tflite']);
        expect(identical(first, second), isFalse);
      },
    );

    test('a different tokenizer alone is also a different embedder', () async {
      final plugin = FlutterGemmaMobile();
      await plugin.createEmbeddingModel(
        modelPath: '/a.tflite',
        tokenizerPath: '/sentencepiece.model',
      );
      await plugin.createEmbeddingModel(
        modelPath: '/a.tflite',
        tokenizerPath: '/wordpiece.json',
      );
      expect(
        backend.seenModelPaths.length,
        2,
        reason:
            'same model, different tokenizer convention — different vectors',
      );
    });
  });

  test('a backend that embeddings DO use stays quiet', () async {
    await expectLater(
      FlutterGemmaMobile().createEmbeddingModel(
        preferredBackend: PreferredBackend.cpu,
      ),
      throwsA(anything),
    );
    expect(notices(), isEmpty);
  });
}

/// Counts how many times the shell actually asked for a model to be built, and
/// with which path — the only way to tell "reused" from "rebuilt" from outside.
class _CountingBackend implements EmbeddingBackendProvider {
  final List<String> seenModelPaths = [];

  @override
  String get name => 'counting';

  @override
  int get priority => 0;

  @override
  bool canHandle(EmbeddingModelSpec spec) => true;

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) async {
    seenModelPaths.add(config.modelPath);
    return _InertEmbeddingModel();
  }
}

class _InertEmbeddingModel extends EmbeddingModel with CloseNotifier {
  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async => const [0.0];

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async => const [
    [0.0],
  ];

  @override
  Future<int> getDimension() async => 1;

  @override
  Future<void> close() async => fireCloseListeners();
}
