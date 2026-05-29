/// Real FFI multi-session integration test (#226) — native .litertlm path.
///
/// Proves on a live LiteRT-LM engine that two concurrent sessions opened
/// via openSession() are isolated: each keeps its own history. The LiteRT-LM
/// engine allows only ONE live conversation at a time, so the FFI path
/// multiplexes — each virtual session replays its history into the single
/// shared conversation on switch (see _VirtualConversationHandle). Logically
/// concurrent contexts, serialized inference. Unit tests cover the
/// orchestration with fakes; this covers the native path.
///
/// Run: cd example && flutter test integration_test/multi_session_litertlm_test.dart -d macos
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';

const _containerDir =
    '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents';
const _gemma3_1bPath = '$_containerDir/gemma3-1b-it-int4.litertlm';

Future<String> _collect(InferenceModelSession s, String prompt) async {
  await s.addQueryChunk(Message(text: prompt, isUser: true));
  return s.getResponse();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();
    if (!File(_gemma3_1bPath).existsSync()) {
      fail(
          'Model not found at $_gemma3_1bPath — copy gemma3-1b-it-int4.litertlm '
          'into the app sandbox Documents dir first.');
    }
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(_gemma3_1bPath).install();
  });

  group('FFI multi-session (real engine)', () {
    testWidgets('S1: two openSession dialogues keep isolated history',
        (t) async {
      final model = await FlutterGemma.getActiveModel(
          maxTokens: 512, preferredBackend: PreferredBackend.cpu);
      try {
        final a = await model.openSession(temperature: 0.0, topK: 1);
        final b = await model.openSession(temperature: 0.0, topK: 1);

        // Two open sessions live concurrently.
        expect(model.sessions.length, greaterThanOrEqualTo(2));

        // Prime each with a distinct fact.
        await _collect(a, 'My name is Alice. Remember it.');
        await _collect(b, 'My name is Bob. Remember it.');

        // Each must recall only its own fact.
        final ra = await _collect(a, 'What is my name? One word.');
        final rb = await _collect(b, 'What is my name? One word.');
        print('[multi-session] A="$ra"  B="$rb"');

        expect(ra.toLowerCase(), contains('alice'),
            reason: 'session A should recall Alice');
        expect(ra.toLowerCase(), isNot(contains('bob')),
            reason: 'session A must NOT see B history');
        expect(rb.toLowerCase(), contains('bob'),
            reason: 'session B should recall Bob');
        expect(rb.toLowerCase(), isNot(contains('alice')),
            reason: 'session B must NOT see A history');

        await a.close();
        await b.close();
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('S2: closing one session leaves the other usable', (t) async {
      final model = await FlutterGemma.getActiveModel(
          maxTokens: 512, preferredBackend: PreferredBackend.cpu);
      try {
        final a = await model.openSession(temperature: 0.0, topK: 1);
        final b = await model.openSession(temperature: 0.0, topK: 1);

        await a.close();

        // B still generates after A is closed.
        final rb = await _collect(b, 'Say hi in one word.');
        print('[multi-session S2] B after A.close = "$rb"');
        expect(rb.trim(), isNotEmpty);

        await b.close();
      } finally {
        await model.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
