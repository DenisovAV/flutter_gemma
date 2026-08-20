@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_builtin_ai/src/web/builtin_ai_model_web.dart';
import 'package:flutter_gemma_builtin_ai/src/web/builtin_ai_session_web.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_prompt_api.dart';

Future<BuiltInAiSessionWeb> _createSession(
  BuiltInAiModelWeb model, {
  double temperature = .8,
  int topK = 1,
  double? topP,
  int? maxOutputTokens,
  int randomSeed = 1,
  String? loraPath,
  String? systemInstruction,
}) async {
  final session = await model.createSession(
    temperature: temperature,
    topK: topK,
    topP: topP,
    maxOutputTokens: maxOutputTokens,
    randomSeed: randomSeed,
    loraPath: loraPath,
    systemInstruction: systemInstruction,
  );
  return session as BuiltInAiSessionWeb;
}

void main() {
  setUp(FakeLanguageModel.uninstall);
  tearDown(FakeLanguageModel.uninstall);

  group('streaming delta/cumulative guard', () {
    test(
      'emits chunks as-is when the stream is already delta-shaped',
      () async {
        FakeLanguageModel(
          availability: ([o]) => 'available',
          create: ([o]) => FakeSession(streamChunks: (_) => ['Hel', 'lo']),
        ).install();

        final model = BuiltInAiModelWeb(
          modelType: ModelType.general,
          onClose: () {},
        );
        final session = await _createSession(model);
        await session.addQueryChunk(const Message(text: 'hi', isUser: true));

        final chunks = await session.getResponseAsync().toList();
        expect(chunks, ['Hel', 'lo']);
      },
    );

    test('strips the accumulated prefix when the stream re-sends the whole '
        'response so far (early-build cumulative shape)', () async {
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) => FakeSession(
          streamChunks: (_) => ['Hel', 'lo'],
          cumulativeStream: true, // fake turns this into ['Hel', 'Hello']
        ),
      ).install();

      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      final session = await _createSession(model);
      await session.addQueryChunk(const Message(text: 'hi', isUser: true));

      final chunks = await session.getResponseAsync().toList();
      expect(chunks, ['Hel', 'lo']);
    });
  });

  test(
    'stopGeneration aborts mid-stream and the stream closes without error',
    () async {
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) =>
            FakeSession(streamChunks: (_) => ['a', 'b', 'c', 'd', 'e']),
      ).install();

      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      final session = await _createSession(model);
      await session.addQueryChunk(const Message(text: 'hi', isUser: true));

      final received = <String>[];
      final done = Completer<void>();
      late final StreamSubscription<String> sub;
      sub = session.getResponseAsync().listen(
        (chunk) {
          received.add(chunk);
          if (received.length == 1) {
            unawaited(session.stopGeneration());
          }
        },
        onDone: done.complete,
        onError: (Object e, StackTrace st) => done.completeError(e, st),
      );
      await done.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      expect(received.length, lessThan(5));
    },
  );

  test(
    'consumer-cancelling the stream (barge-in) aborts the in-flight generation',
    () async {
      late final FakeSession fake;
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) =>
            fake = FakeSession(streamChunks: (_) => ['a', 'b', 'c', 'd', 'e']),
      ).install();

      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      final session = await _createSession(model);
      await session.addQueryChunk(const Message(text: 'hi', isUser: true));

      // Cancel the subscription mid-stream WITHOUT calling stopGeneration —
      // the consumer just walks away (barge-in). cleanup() must still abort the
      // AbortSignal so the JS generation doesn't keep running browser-side.
      final sub = session.getResponseAsync().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(
        isSignalAborted(fake.lastStreamingSignal),
        isTrue,
        reason: 'consumer-cancel must abort the promptStreaming AbortSignal',
      );
    },
  );

  group('createSession param mapping', () {
    test(
      'sends temperature+topK together and systemInstruction as initialPrompts',
      () async {
        JSObject? captured;
        FakeLanguageModel(
          availability: ([o]) => 'available',
          create: ([o]) {
            captured = o;
            return FakeSession();
          },
        ).install();

        final model = BuiltInAiModelWeb(
          modelType: ModelType.general,
          onClose: () {},
        );
        await _createSession(
          model,
          temperature: 0.5,
          topK: 4,
          systemInstruction: 'be nice',
        );

        expect(captured, isNotNull);
        final dartified = captured!.dartify() as Map;
        expect(dartified['temperature'], 0.5);
        expect(dartified['topK'], 4);
        final prompts = dartified['initialPrompts'] as List;
        expect(prompts.single, {'role': 'system', 'content': 'be nice'});
      },
    );

    test('clamps temperature/topK to LanguageModel.params() maxima', () async {
      JSObject? captured;
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) {
          captured = o;
          return FakeSession();
        },
        maxTemperature: 1.0,
        maxTopK: 3,
      ).install();

      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      await _createSession(model, temperature: 5.0, topK: 100);

      final dartified = captured!.dartify() as Map;
      expect(dartified['temperature'], 1.0);
      expect(dartified['topK'], 3);
    });

    test('drops topP/maxOutputTokens/randomSeed/loraPath without throwing or '
        'sending them to create()', () async {
      JSObject? captured;
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) {
          captured = o;
          return FakeSession();
        },
      ).install();

      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      await _createSession(
        model,
        topP: 0.9,
        maxOutputTokens: 128,
        randomSeed: 42,
        loraPath: '/some/path',
      );

      final dartified = captured!.dartify() as Map;
      expect(dartified.containsKey('topP'), isFalse);
      expect(dartified.containsKey('maxOutputTokens'), isFalse);
      expect(dartified.containsKey('randomSeed'), isFalse);
      expect(dartified.containsKey('loraPath'), isFalse);
    });

    test('enableAudioModality throws UnsupportedError', () async {
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) => FakeSession(),
      ).install();
      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      await expectLater(
        model.createSession(enableAudioModality: true),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('sizeInTokens', () {
    test('uses measureContextUsage', () async {
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) => FakeSession(),
      ).install();
      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      final session = await _createSession(model);
      final n = await session.sizeInTokens('hello');
      expect(
        n,
        'hello'.length,
      ); // fake measureContextUsage returns input length
    });
  });

  group('close/destroy idempotence', () {
    test(
      'double session.close() calls destroy() exactly once and never throws',
      () async {
        FakeSession? created;
        FakeLanguageModel(
          availability: ([o]) => 'available',
          create: ([o]) {
            created = FakeSession();
            return created!;
          },
        ).install();
        final model = BuiltInAiModelWeb(
          modelType: ModelType.general,
          onClose: () {},
        );
        final session = await _createSession(model);

        await session.close();
        await session.close(); // must not throw / double-destroy

        expect(created!.destroyCount, 1);
        expect(
          () => session.addQueryChunk(const Message(text: 'x', isUser: true)),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('double model.close() never throws', () async {
      FakeLanguageModel(
        availability: ([o]) => 'available',
        create: ([o]) => FakeSession(),
      ).install();
      final model = BuiltInAiModelWeb(
        modelType: ModelType.general,
        onClose: () {},
      );
      await _createSession(model);

      await model.close();
      await model.close();
    });
  });

  group('BuiltInAiEngine (web)', () {
    test('canHandle matches only fileType.builtIn', () {
      const engine = BuiltInAiEngine();
      expect(
        engine.canHandle(
          InferenceModelSpec(
            name: 'gemini-nano',
            modelSource: ModelSource.bundled('gemini-nano'),
            modelType: ModelType.general,
            fileType: ModelFileType.builtIn,
          ),
        ),
        isTrue,
      );
      expect(
        engine.canHandle(
          InferenceModelSpec(
            name: 'x',
            modelSource: ModelSource.network('https://example.com/m.task'),
            modelType: ModelType.general,
            fileType: ModelFileType.task,
          ),
        ),
        isFalse,
      );
    });

    test('createModel throws BuiltInAiUnavailableException when the fake '
        'reports downloadable (not yet available)', () async {
      FakeLanguageModel(availability: ([o]) => 'downloadable').install();
      const engine = BuiltInAiEngine();
      final spec = InferenceModelSpec(
        name: 'gemini-nano',
        modelSource: ModelSource.bundled('gemini-nano'),
        modelType: ModelType.general,
        fileType: ModelFileType.builtIn,
      );
      await expectLater(
        engine.createModel(
          spec,
          const RuntimeConfig(maxTokens: 1024, modelPath: ''),
        ),
        throwsA(isA<BuiltInAiUnavailableException>()),
      );
    });
  });
}
