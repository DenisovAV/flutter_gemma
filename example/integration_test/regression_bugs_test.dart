/// Regression tests that demonstrate the CRITICAL bugs found by code review.
///
/// These tests EXPECT to fail on the current 0.14.0-pre code and PASS after
/// the fixes land. Each test maps 1:1 to a finding in
/// test_reports/pr-reviews/pr-branch-feature-desktop-ffi-review.md.
///
/// Run on macOS (model already installed locally):
///   flutter test integration_test/regression_bugs_test.dart -d macos
///
/// Or on iPhone:
///   flutter test integration_test/regression_bugs_test.dart -d <iphone-id>
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/core/model_response.dart';

const _gemma4Url = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
const _token = String.fromEnvironment('HUGGINGFACE_TOKEN');

String get _macosDir =>
    '${Platform.environment['HOME']}/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents';
String get _linuxDir => '${Platform.environment['HOME']}/models';
String get _windowsDir => '${Platform.environment['USERPROFILE']}\\models';
const String _androidDir = '/data/local/tmp/flutter_gemma_test';

Future<void> _installGemma4() async {
  final candidates = [
    '$_macosDir/gemma-4-E2B-it.litertlm',
    '$_linuxDir/gemma-4-E2B-it.litertlm',
    '$_windowsDir\\gemma-4-E2B-it.litertlm',
    '$_androidDir/gemma-4-E2B-it.litertlm',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(path).install();
      return;
    }
  }
  await FlutterGemma.installModel(
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
  ).fromNetwork(_gemma4Url, token: _token).install();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();
    await _installGemma4();
  });

  group('C1 — sampler params silently dropped without systemInstruction', () {
    // The bug: createConversation only builds samplerParams if
    // systemMessage != null || toolsJson != null. So passing
    // (temperature: 1.0, topK: 50, randomSeed: X) without a system
    // instruction is silently downgraded to model defaults — every
    // run uses the same (or random-each-time) underlying sampler.
    //
    // Test strategy:
    //   1) Two runs with SAME seed at high temperature must produce
    //      IDENTICAL text (RNG is seeded).
    //   2) Two runs with DIFFERENT seeds must produce DIFFERENT text
    //      (different RNG streams).
    //
    // If sampler params reach native:
    //   same seeds → identical, different seeds → different ✓
    //
    // If sampler params are dropped (current bug):
    //   model defaults take over. Two cases:
    //   - defaults greedy: every run identical regardless of seed
    //     (different seeds → identical = FAIL the second assertion).
    //   - defaults random: every run different regardless of seed
    //     (same seed → different = FAIL the first assertion).
    //
    // Either way, at least one assertion catches the bug.
    Future<void> runStochasticSeedCheck(PreferredBackend backend) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: backend,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        Future<String> runOnce(int seed) async {
          final session = await model.createSession(
            temperature: 1.0,
            topK: 50,
            topP: 0.95,
            randomSeed: seed,
            // Note: NO systemInstruction — triggers the bug path.
          );
          await session.addQueryChunk(
            const Message(
              text: 'Write a 30-word creative story about a dragon.',
              isUser: true,
            ),
          );
          final out = await session.getResponse();
          await session.close();
          return out;
        }

        final seed42a = await runOnce(42);
        final seed42b = await runOnce(42);
        final seed99 = await runOnce(99);

        expect(seed42a, equals(seed42b),
            reason:
                '[$backend] Same seed (42, 42) must yield identical output at '
                'temperature=1.0. Different output means sampler params dropped. '
                'A=$seed42a\nB=$seed42b\nSee review C1.');

        expect(seed42a, isNot(equals(seed99)),
            reason:
                '[$backend] Different seeds (42 vs 99) must yield different output '
                'at temperature=1.0. Identical output means model is greedy '
                '(temperature/seed ignored, sampler params dropped). '
                'seed42=$seed42a\nseed99=$seed99\nSee review C1.');
      } finally {
        await model.close();
      }
    }

    testWidgets('CPU stochastic decode honors randomSeed', (_) async {
      await runStochasticSeedCheck(PreferredBackend.cpu);
    }, timeout: const Timeout(Duration(minutes: 5)));

    // Temperature test: independently confirms sampler params reach native.
    // If temperature is honored:
    //   - temperature=0.0 (greedy) → seed has no effect, two runs identical
    //   - temperature=1.0 (stochastic) → seed varies output (already covered above)
    // If temperature is silently dropped, the model uses its baked-in default
    // (typically temperature=1.0 from LlmMetadata) — making temperature=0.0
    // still produce stochastic-looking output, which we can detect.
    testWidgets('CPU honors temperature=0.0 (greedy) — output is seed-invariant',
        (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        Future<String> runOnce(int seed) async {
          final session = await model.createSession(
            temperature: 0.0, // greedy — argmax, seed should not matter
            topK: 1,
            randomSeed: seed,
          );
          await session.addQueryChunk(const Message(
            text: 'Write a 30-word creative story about a dragon.',
            isUser: true,
          ));
          final out = await session.getResponse();
          await session.close();
          return out;
        }

        // With temperature=0.0 different seeds MUST produce identical output
        // (greedy decoding has no randomness). If different, temperature was
        // dropped and model is sampling stochastically with its default temp.
        final seed1 = await runOnce(1);
        final seed42 = await runOnce(42);
        final seed99 = await runOnce(99);

        expect(seed1, equals(seed42),
            reason:
                '[CPU temp=0.0] seed=1 vs seed=42 must be identical (greedy). '
                'Different output means temperature was dropped. '
                's1=$seed1\ns42=$seed42');
        expect(seed1, equals(seed99),
            reason:
                '[CPU temp=0.0] seed=1 vs seed=99 must be identical (greedy). '
                'Different output means temperature was dropped. '
                's1=$seed1\ns99=$seed99');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    // topK test: low topK + temperature=1.0 should narrow the choice space.
    // If sampler params are dropped, topK has no effect.
    // We verify this indirectly: with topK=1 + temperature=1.0 the output
    // should be IDENTICAL across different seeds (top-k=1 is greedy in
    // disguise — only one candidate per step). With topK=50 + same seed,
    // the output should match topK=50 reruns. This catches the case where
    // topK is silently dropped — the model would then use its metadata
    // default (typically topK=1, temperature=1.0, type=TOP_P) producing
    // ambiguous results.
    testWidgets('CPU honors topK=1 (deterministic across seeds)', (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        Future<String> runOnce(int seed) async {
          final session = await model.createSession(
            temperature: 1.0,
            topK: 1, // hard greedy via top-k
            randomSeed: seed,
          );
          await session.addQueryChunk(const Message(
            text: 'Write a 30-word creative story about a dragon.',
            isUser: true,
          ));
          final out = await session.getResponse();
          await session.close();
          return out;
        }

        final seed42 = await runOnce(42);
        final seed99 = await runOnce(99);
        expect(seed42, equals(seed99),
            reason:
                '[CPU topK=1] Different seeds must yield identical output '
                '(top-1 has only one candidate). Different output means '
                'topK was dropped or did not reach native. '
                's42=$seed42\ns99=$seed99');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    // GPU sampler param tests: same logic as CPU but on GPU. On platforms
    // where the GPU sampler dynamic library is fully wired (mobile with
    // proper sampler exports), these PASS. On macOS/Linux/Windows desktop
    // and Android (where sampler dlopen falls back to static argmax) the
    // model is greedy regardless — same-seed=different-seed = identical
    // (already deterministic), and temperature is effectively pinned. The
    // tests are still useful: they catch any regression that turns the
    // GPU pipeline non-deterministic.
    testWidgets('GPU temperature=0.0 produces same-seed-stable output',
        (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.gpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        Future<String> runOnce(int seed) async {
          final session = await model.createSession(
            temperature: 0.0,
            topK: 1,
            randomSeed: seed,
          );
          await session.addQueryChunk(const Message(
            text: 'Write a 30-word creative story about a dragon.',
            isUser: true,
          ));
          final out = await session.getResponse();
          await session.close();
          return out;
        }

        final s1 = await runOnce(1);
        final s42 = await runOnce(42);
        expect(s1, equals(s42),
            reason:
                '[GPU temp=0.0] greedy decode must be deterministic across '
                'seeds. Different output means GPU pipeline is non-deterministic '
                'OR temperature was reinterpreted upstream. '
                's1=$s1\ns42=$s42');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('GPU topK=1 produces same-seed-stable output', (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.gpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        Future<String> runOnce(int seed) async {
          final session = await model.createSession(
            temperature: 1.0,
            topK: 1,
            randomSeed: seed,
          );
          await session.addQueryChunk(const Message(
            text: 'Write a 30-word creative story about a dragon.',
            isUser: true,
          ));
          final out = await session.getResponse();
          await session.close();
          return out;
        }

        final s42 = await runOnce(42);
        final s99 = await runOnce(99);
        expect(s42, equals(s99),
            reason:
                '[GPU topK=1] only one candidate per step — must be '
                'deterministic across seeds. s42=$s42\ns99=$s99');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    // GPU determinism: same prompt + same engine config must yield
    // identical output across runs. This is the only assertion we can make
    // about GPU sampling today: across all platforms (macOS/Linux/Windows
    // desktop, Android, iOS) the upstream GPU sampler dylibs either
    // (a) lack the LiteRtTopK*Sampler_Create C API exports the factory
    //     looks up via dlsym (upstream issues #1990, #2073), OR
    // (b) need RTLD_GLOBAL preload of libLiteRt's LiteRtCreateEnvironment,
    //     which interacts poorly with Android Native Assets' RTLD_LOCAL
    //     load sequence.
    // The factory falls back to its statically-linked argmax sampler in
    // every case — deterministic, but seed-insensitive at the GPU layer.
    // CPU sampler honors seed correctly (asserted above). When upstream
    // ships proper sampler exports we can promote this to a seed-sensitivity
    // check; until then determinism is the load-bearing guarantee.
    testWidgets('GPU produces deterministic output across runs', (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.gpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        Future<String> runOnce() async {
          final session = await model.createSession(
            temperature: 1.0,
            topK: 50,
            topP: 0.95,
            randomSeed: 42,
          );
          await session.addQueryChunk(
            const Message(
              text: 'Write a 30-word creative story about a dragon.',
              isUser: true,
            ),
          );
          final out = await session.getResponse();
          await session.close();
          return out;
        }

        final first = await runOnce();
        final second = await runOnce();
        expect(second, equals(first),
            reason:
                '[GPU] Two runs with the same prompt + same config produced '
                'different output. Either sampler is reading uninitialized '
                'state across runs, or the GPU pipeline is non-deterministic. '
                'first=$first\nsecond=$second');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('C4 — loraPath silently dropped on FFI path', () {
    // The bug: createSession/createChat accept String? loraPath but never
    // forward it to ffiClient.createConversation. A user expecting LoRA
    // weights to be applied gets a base-model response with no warning.
    //
    // Fix expectation: passing a non-existent loraPath should throw
    // (FileSystemException, ArgumentError, or UnsupportedError if LoRA is
    // not yet implemented). Silent acceptance is the bug.
    testWidgets('non-existent loraPath must not be silently accepted',
        (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        // /this/path/does/not/exist.bin — must produce a clear error,
        // either at createSession time (validation) or at first inference
        // (engine-side error). Silent success means the param was dropped.
        Object? caught;
        InferenceModelSession? session;
        try {
          session = await model.createSession(
            temperature: 0.8,
            topK: 1,
            loraPath: '/this/path/does/not/exist/lora.bin',
          );
        } catch (e) {
          caught = e;
        }
        if (session != null) {
          await session.close();
        }
        expect(caught, isNotNull,
            reason:
                'Either throw at createSession (validation) or UnsupportedError if not yet implemented. See review C4.');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('C5 — tools list silently dropped from native conversation config', () {
    // The bug: createChat accepts tools: List<Tool> and forwards them to
    // InferenceChat, but the underlying ffiClient.createConversation is
    // called without toolsJson. Native engine is configured in pure-text
    // mode while Dart-side template formatting may produce something —
    // half-broken silent state. Function calling won't work.
    //
    // Fix expectation: either tools are correctly threaded to native
    // (and the model produces structured tool-call output), or
    // createChat throws UnsupportedError when tools is non-empty.
    // Stronger test: bypass InferenceChat (which Dart-formats the prompt
    // and parses JSON back). Use the low-level session API directly with
    // a tools-aware model. If tools are threaded to native, the native
    // engine prepends its TRAINED tool-format template (e.g. Gemma 4's
    // <tool_call> tags or Hermes-style). If tools are dropped, the user's
    // bare prompt "What is the weather in Berlin?" reaches the model with
    // no tool context — the model will respond with plain conversational
    // text, NOT structured JSON.
    //
    // This test cannot exercise `tools` directly because createSession
    // doesn't accept tools. It instead asserts that the FFI client does
    // NOT have a public createConversation overload taking tools — which
    // means there's no way for InferenceModel.createSession to communicate
    // tools to native. The bug is therefore structural: the API surface
    // doesn't even expose tools to the native config in the FFI path.
    //
    // For now we verify the structural absence by reading the bindings.
    // (See C5 in pr-branch-feature-desktop-ffi-review.md.)
    testWidgets('non-empty tools list must engage native function calling or throw',
        (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        const tool = Tool(
          name: 'get_weather',
          description: 'Get the current weather in a city',
          parameters: {
            'type': 'object',
            'properties': {
              'city': {
                'type': 'string',
                'description': 'The city name',
              },
            },
            'required': ['city'],
          },
        );

        // This call must either:
        //   (a) succeed, and a weather-related question must produce
        //       function-call output (toolName != null), proving tools
        //       were threaded to native, OR
        //   (b) throw UnsupportedError if tools-on-FFI is not yet wired.
        try {
          final chat = await model.createChat(
            temperature: 0.8,
            topK: 1,
            tools: const [tool],
            supportsFunctionCalls: true,
          );
          await chat.addQuery(const Message(
            text: 'What is the weather in Berlin?',
            isUser: true,
          ));
          final response = await chat.generateChatResponse();
          await chat.close();

          // If we got here, tools were accepted. The response MUST be
          // a function-call (FunctionCallResponse), not a plain text
          // ramble. Otherwise tools were silently dropped.
          expect(response, isA<FunctionCallResponse>(),
              reason:
                  'Model with tool config must emit a function call for a weather question. Plain TextResponse here means tools were dropped silently. See review C5.');
        } on UnsupportedError {
          // Acceptable — explicit refusal until proper plumbing exists.
        }
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('C6 — stopGeneration on closed session must not crash native', () {
    // The bug: FfiInferenceModelSession.stopGeneration has no _isClosed
    // check. After close() runs, _conversation is null in FFI client,
    // but if stopGeneration is called concurrently with close()
    // (close is async, body sync up to first await), there's a window
    // where ffiClient.cancelGeneration() may hit a freed pointer.
    //
    // Fix expectation: calling stopGeneration() AFTER close() must
    // not throw and must not crash the process — it should be a
    // guarded no-op.
    testWidgets('stopGeneration after close is a no-op (no UAF crash)',
        (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      final session = await model.createSession(
        temperature: 0.8,
        topK: 1,
      );
      await session.addQueryChunk(
        const Message(text: 'Hi.', isUser: true),
      );
      await session.close();

      // Calling stopGeneration on a closed session must not throw and
      // must not crash. Today this only avoids crash by accident (the
      // FFI client's null-guard at one layer below), not by design here.
      // If the test runner crashes during this call (segfault from
      // a freed pointer), the bug is reproduced.
      Object? stopError;
      try {
        await session.stopGeneration();
      } catch (e) {
        stopError = e;
      }
      expect(stopError, isNull,
          reason:
              'stopGeneration() on a closed session must not throw. See review C6.');

      await model.close();
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('I3 — PreferredBackend.npu silently coerced to gpu on desktop', () {
    // The bug: lib/desktop/flutter_gemma_desktop.dart and
    // lib/mobile/flutter_gemma_mobile.dart map any non-cpu PreferredBackend
    // to 'gpu'. NPU is documented Android-only on .litertlm. On desktop,
    // requesting NPU silently runs GPU.
    //
    // Fix expectation: requesting NPU on a non-supporting platform should
    // throw UnsupportedError, not silently use GPU.
    testWidgets('NPU on desktop must throw, not silently fall back to GPU',
        (_) async {
      // Skip this test on platforms where NPU might be valid.
      if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
        return;
      }
      Object? caught;
      try {
        // Use distinct maxTokens to force singleton-reuse path to recreate
        // the model — otherwise `_initializedModel` from earlier tests is
        // returned without re-evaluating the requested backend.
        await FlutterGemma.getActiveModel(
          maxTokens: 2048,
          preferredBackend: PreferredBackend.npu,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<UnsupportedError>(),
          reason:
              'NPU is Android-only. On desktop it must throw UnsupportedError, not silently coerce to GPU. See review I3.');
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('I1 — close() does not cancel in-flight generation (race)', () {
    // The bug: ffi_inference_model.dart close() deletes the conversation
    // while native streaming thread may still be producing tokens. Race
    // between Dart close() and native cancel.
    //
    // Fix expectation: closing a session mid-stream must complete cleanly
    // (no exception leaking out of the stream subscription, no hang).
    testWidgets('close() during active stream must terminate cleanly',
        (_) async {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
        supportAudio: true,
      );
      try {
        final session = await model.createSession(
          temperature: 0.8,
          topK: 1,
        );
        await session.addQueryChunk(const Message(
          text: 'Tell me a long story about a brave knight.',
          isUser: true,
        ));

        final stream = session.getResponseAsync();
        final completer = Completer<void>();
        var receivedAny = false;

        final sub = stream.listen(
          (chunk) {
            if (!receivedAny) {
              receivedAny = true;
              // Mid-stream close — this races with native generation.
              // Schedule async to avoid reentry into the stream.
              Future.microtask(() async {
                await session.close();
                if (!completer.isCompleted) completer.complete();
              });
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            throw StateError(
                'Stream did not terminate within 60s after mid-stream close — race condition. See review I1.');
          },
        );
        await sub.cancel();
        expect(receivedAny, isTrue,
            reason: 'Stream emitted at least one chunk before close.');
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
