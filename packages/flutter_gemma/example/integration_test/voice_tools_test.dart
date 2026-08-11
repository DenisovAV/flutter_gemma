// On-device: voice loop WITH function calling. Fixed transcript -> Gemma 3 1B
// (tools) -> onToolCall -> Matcha TTS. Asserts the tool ran and a spoken reply
// was produced.
// Run: flutter test integration_test/voice_tools_test.dart -d <device> \
//   --dart-define=HUGGINGFACE_TOKEN=$HF_TOKEN
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'voice_test_helpers.dart';

const _llmFile =
    '/data/local/tmp/flutter_gemma_test/gemma3-1b-it-int4.litertlm';
const _ttsUrl =
    'https://huggingface.co/litert-community/Matcha-TTS/resolve/main/';
const _tools = [
  Tool(
    name: 'show_alert',
    description: 'Shows an alert dialog to the user',
    parameters: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string', 'description': 'The title'},
        'message': {'type': 'string', 'description': 'The message'},
      },
      'required': ['title', 'message'],
    },
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'voice + tools: fixed transcript -> tool runs -> spoken reply',
    (tester) async {
      await FlutterGemma.initialize(
        ttsBackends: const [LiteRtTtsBackend()],
        inferenceEngines: const [LiteRtLmEngine()],
      );
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_llmFile).install();
      await FlutterGemma.installTts()
          .fromNetwork(_ttsUrl)
          .ofType(TtsModelType.matcha)
          .install();

      final synth = await FlutterGemma.getActiveTts();
      final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
      final chat = await model.createChat(
        tools: _tools,
        supportsFunctionCalls: true,
        modelType: ModelType.gemmaIt,
        tokenBuffer: 256,
        maxOutputTokens: 128,
      );

      var called = false;
      final session = VoiceSession.fromChat(
        recognizer: FixedTranscriptRecognizer(
          'Show an alert with title "Test" and message "Hello"',
        ),
        chat: chat,
        synthesizer: synth,
        onToolCall: (c) {
          called = true;
          return {'status': 'success', 'message': 'shown'};
        },
      );

      final events = await session.runTurn(Uint8List(0)).toList();

      expect(
        events.whereType<VoiceTranscriptEvent>().single.text,
        contains('alert'),
      );
      expect(called, isTrue, reason: 'the tool was never executed');
      final audio = events.whereType<VoiceReplyAudioEvent>().toList();
      expect(audio, isNotEmpty);
      expect(
        audio.single.pcm.any((b) => b != 0),
        isTrue,
        reason: 'silent reply',
      );

      await chat.session.close();
      await model.close();
      await synth.close();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
