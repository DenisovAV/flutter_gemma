/// Web integration test for the LiteRT-LM `.litertlm` inference path
/// (added in 0.16.2 via `@litert-lm/core`).
///
/// Run with:
///   chromedriver --port=4444 &
///   cd example
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/litertlm_web_test.dart \
///     -d chrome
///
/// For headless CI: use `-d web-server` instead of `-d chrome`.
///
/// Prerequisites:
///   * Chrome with WebGPU enabled (`chrome://flags/#enable-unsafe-webgpu`)
///   * ~600 MB free disk + network bandwidth for `gemma-4-E2B-it-web.litertlm`
///     (first run only — cached afterwards by `WebStorageMode.cacheApi`)
///   * Optional `HUGGINGFACE_TOKEN` if the upstream model becomes gated
///     (`--dart-define=HUGGINGFACE_TOKEN=hf_...`)
///
/// Why these tests and not the full 18 from `litertlm_ffi_test.dart`:
///   * The upstream `@litert-lm/core` is "early preview, text-in/text-out only".
///   * Vision / audio / thinking are warn-and-ignore (no Engine path to test).
///   * CPU/GPU/NPU is a single WebGPU/WASM backend (no choice to assert).
///   * LoRA throws UnsupportedError, exercised in the unit smoke
///     (`test/web/litert_lm_web_test.dart`).
///   * `getTargetPath` is filesystem-only (no path_provider on web).
@TestOn('chrome')
library;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'inference_test_helpers.dart' show registerTestEngines;

const _webModelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm';

const _hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

InferenceModel? _model;

Future<InferenceModel> _ensureModel() async {
  if (_model != null) return _model!;

  // Install via the network path — `WebStorageMode.cacheApi` (default) puts
  // the blob into IndexedDB, so subsequent runs are instant.
  final installer = FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  );
  await installer
      .fromNetwork(_webModelUrl, token: _hfToken.isEmpty ? null : _hfToken)
      .install();

  final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
  _model = model;
  return model;
}

Future<void> _disposeModel() async {
  await _model?.close();
  _model = null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRT-LM web (.litertlm via @litert-lm/core)', () {
    setUpAll(() async {
      await registerTestEngines();
    });
    tearDownAll(_disposeModel);

    testWidgets('text generation produces a non-empty response', (
      tester,
    ) async {
      final model = await _ensureModel();
      final session = await model.createSession();
      try {
        await session.addQueryChunk(
          const Message(text: 'Say hello in one word.', isUser: true),
        );
        final response = await session.getResponse();
        expect(response, isNotEmpty);
      } finally {
        await session.close();
      }
    });

    testWidgets('streaming yields at least one chunk', (tester) async {
      final model = await _ensureModel();
      final session = await model.createSession();
      try {
        await session.addQueryChunk(
          const Message(text: 'Count from one to three.', isUser: true),
        );
        var chunkCount = 0;
        final buf = StringBuffer();
        await for (final chunk in session.getResponseAsync()) {
          chunkCount++;
          buf.write(chunk);
        }
        expect(chunkCount, greaterThan(0));
        expect(buf.toString(), isNotEmpty);
      } finally {
        await session.close();
      }
    });

    testWidgets('chat: multi-turn conversation retains history', (
      tester,
    ) async {
      final model = await _ensureModel();
      final chat = await model.createChat(modelType: ModelType.gemma4);

      await chat.addQueryChunk(
        const Message(text: 'My favourite color is blue.', isUser: true),
      );
      await chat.generateChatResponse();

      await chat.addQueryChunk(
        const Message(text: 'What is my favourite color?', isUser: true),
      );
      final response = await chat.generateChatResponse();
      expect(response.toString().toLowerCase(), contains('blue'));
    });

    testWidgets('chat: clearHistory wipes context', (tester) async {
      final model = await _ensureModel();
      final chat = await model.createChat(modelType: ModelType.gemma4);

      await chat.addQueryChunk(
        const Message(text: 'Remember the number 42.', isUser: true),
      );
      await chat.generateChatResponse();

      await chat.clearHistory();

      await chat.addQueryChunk(
        const Message(
          text: 'What number did I ask you to remember?',
          isUser: true,
        ),
      );
      final response = (await chat.generateChatResponse())
          .toString()
          .toLowerCase();
      // After clearHistory the assistant should NOT recall "42" verbatim.
      expect(
        response.contains('42'),
        isFalse,
        reason: 'clearHistory should drop the prior context.',
      );
    });

    testWidgets('session: sizeInTokens returns a non-negative integer', (
      tester,
    ) async {
      final model = await _ensureModel();
      final session = await model.createSession();
      try {
        final n = await session.sizeInTokens('Hello world');
        expect(n, greaterThan(0));
      } finally {
        await session.close();
      }
    });

    testWidgets('multiple createSession on the same model', (tester) async {
      final model = await _ensureModel();
      final s1 = await model.createSession();
      await s1.close();
      final s2 = await model.createSession();
      await s2.addQueryChunk(const Message(text: 'Hi.', isUser: true));
      final r = await s2.getResponse();
      expect(r, isNotEmpty);
      await s2.close();
    });

    // PROBE (#226): does @litert-lm/core (the same LiteRT-LM C++ core compiled
    // to WASM) enforce the "one conversation at a time" limit that the native
    // FFI engine does? Two openSession() dialogues should keep isolated
    // history. If the engine rejects the second conversation (or histories
    // bleed), web needs the same virtual-session multiplexer the FFI path uses
    // — and this test will fail loudly, telling us so.
    testWidgets('PROBE: two openSession dialogues keep isolated history', (
      tester,
    ) async {
      final model = await _ensureModel();
      final a = await model.openSession(temperature: 0.0, topK: 1);
      final b = await model.openSession(temperature: 0.0, topK: 1);
      try {
        expect(
          model.sessions.length,
          greaterThanOrEqualTo(2),
          reason: 'both sessions should be live concurrently',
        );

        await a.addQueryChunk(
          const Message(text: 'My name is Alice. Remember it.', isUser: true),
        );
        await a.getResponse();
        await b.addQueryChunk(
          const Message(text: 'My name is Bob. Remember it.', isUser: true),
        );
        await b.getResponse();

        await a.addQueryChunk(
          const Message(text: 'What is my name? One word.', isUser: true),
        );
        final ra = (await a.getResponse()).toLowerCase();
        await b.addQueryChunk(
          const Message(text: 'What is my name? One word.', isUser: true),
        );
        final rb = (await b.getResponse()).toLowerCase();
        // ignore: avoid_print
        print('[web-probe] A="$ra"  B="$rb"');

        expect(ra, contains('alice'), reason: 'A should recall Alice');
        expect(ra, isNot(contains('bob')), reason: 'A must not see B history');
        expect(rb, contains('bob'), reason: 'B should recall Bob');
        expect(
          rb,
          isNot(contains('alice')),
          reason: 'B must not see A history',
        );
      } finally {
        await a.close();
        await b.close();
      }
    });
  });
}
