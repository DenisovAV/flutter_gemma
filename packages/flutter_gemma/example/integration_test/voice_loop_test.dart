// On-device integration test: the full voice loop (STT -> LLM -> TTS) driven
// by VoiceSession.fromChat, end-to-end on the bundled clip — no mic/speaker.
//
// Installs moonshine-tiny STT, Gemma 3 1B IT (.litertlm, no tools) and
// Matcha TTS from HuggingFace, activates all three via the public API, then
// runs one VoiceSession turn and asserts transcript -> reply text -> reply
// audio -> turn-complete all landed with real (non-empty, non-silent)
// content.
//
// Run: cd packages/flutter_gemma/example && \
//   flutter test integration_test/voice_loop_test.dart -d <device> \
//     --dart-define=HF_TOKEN=$HF_TOKEN
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/utils/audio_converter.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

// ── STT: moonshine-tiny — same URLs as stt_moonshine_test.dart. Public repos,
// token is optional there but harmless to pass. ──
const _sttModelUrl =
    'https://huggingface.co/litert-community/moonshine-tiny/resolve/main/moonshine_tiny_5s_f32.tflite';
const _sttTokenizerUrl =
    'https://huggingface.co/UsefulSensors/moonshine/resolve/main/ctranslate2/tiny/tokenizer.json';

// ── LLM: Gemma 3 1B IT, .litertlm, gated repo (needsAuth: true in
// example/lib/models/model.dart Model.gemma3_1B). Same desktopUrl used by
// active_model_restore_test.dart / litertlm_ffi_test.dart's fromNetwork
// install pattern, and the exact model VoiceScreen picks for this loop. Small
// (0.5GB) on purpose — this test is a release gate, not a quality bar. ──
const _llmModelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';

// ── TTS: Matcha-TTS — same URL as tts_matcha_test.dart. Public repo, no
// token needed there. ──
const _ttsModelUrl =
    'https://huggingface.co/litert-community/Matcha-TTS/resolve/main/';

const _hfToken = String.fromEnvironment('HF_TOKEN');

/// On desktop, prefer a locally-staged model file (no network, no token) — the
/// convention the other desktop integration tests use. Stage a Gemma 3 1B IT
/// `.litertlm` into the app's documents dir as `gemma3-1b-it-int4.litertlm`.
/// Returns null when no staged file is present (iOS / CI → network install).
Future<String?> _stagedLlmPath() async {
  if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    return null;
  }
  final docs = await getApplicationDocumentsDirectory();
  final path = '${docs.path}/gemma3-1b-it-int4.litertlm';
  return File(path).existsSync() ? path : null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'voice loop: bundled clip -> STT -> LLM -> TTS produces spoken reply',
    (tester) async {
      // 1. Register the STT/TTS/inference backends and install + activate
      //    STT (moonshine), a small no-tools LLM (Gemma 3 1B), and TTS
      //    (Matcha).
      await FlutterGemma.initialize(
        huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
        sttBackends: const [LiteRtSttBackend()],
        ttsBackends: const [LiteRtTtsBackend()],
        inferenceEngines: const [LiteRtLmEngine()],
      );

      await FlutterGemma.installStt()
          .modelFromNetwork(
            _sttModelUrl,
            token: _hfToken.isEmpty ? null : _hfToken,
          )
          .tokenizerFromNetwork(
            _sttTokenizerUrl,
            token: _hfToken.isEmpty ? null : _hfToken,
          )
          .ofType(SttModelType.moonshine)
          .install();

      // Desktop: install the LLM from a locally-staged .litertlm (no network,
      // no token) — the convention used by the other desktop integration tests
      // (litertlm_ffi_test.dart / active_model_restore_test.dart). iOS / CI
      // without a staged file fall back to the network install.
      final llm = FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      );
      final llmLocalPath = await _stagedLlmPath();
      if (llmLocalPath != null) {
        await llm.fromFile(llmLocalPath).install();
      } else {
        await llm
            .fromNetwork(
              _llmModelUrl,
              token: _hfToken.isEmpty ? null : _hfToken,
            )
            .install();
      }

      await FlutterGemma.installTts()
          .fromNetwork(_ttsModelUrl)
          .ofType(TtsModelType.matcha)
          .install();

      final recognizer = await FlutterGemma.getActiveStt();
      final synthesizer = await FlutterGemma.getActiveTts();
      final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
      final chat = await model.createChat(
        tokenBuffer: 256,
        tools: const [],
        maxOutputTokens: 128,
      );

      // 2. Load the bundled clip -> 16 kHz mono PCM.
      final data = await rootBundle.load('assets/test/test_audio.wav');
      final parsed = AudioConverter.parseWav(data.buffer.asUint8List());
      final pcm = AudioConverter.toPCM16kHzMono(
        parsed.pcmData,
        sourceSampleRate: parsed.sampleRate,
        sourceChannels: parsed.channels,
      );

      // 3. Run one voice turn.
      final session = VoiceSession.fromChat(
        recognizer: recognizer,
        chat: chat,
        synthesizer: synthesizer,
      );
      final events = await session.runTurn(pcm).toList();

      // 4. Assert the full pipeline produced output.
      final transcript = events.whereType<VoiceTranscriptEvent>().single.text;
      final replyText = events
          .whereType<VoiceReplyTextEvent>()
          .map((e) => e.chunk)
          .join();
      final audio = events.whereType<VoiceReplyAudioEvent>().toList();
      final complete = events.whereType<VoiceTurnCompleteEvent>().single;

      expect(
        transcript.trim(),
        isNotEmpty,
        reason: 'STT produced no transcript',
      );
      expect(replyText.trim(), isNotEmpty, reason: 'LLM produced no reply');
      expect(audio, isNotEmpty, reason: 'TTS produced no audio event');
      expect(audio.single.pcm.length, greaterThan(0));
      expect(audio.single.sampleRate, 22050);
      expect(
        audio.single.pcm.any((b) => b != 0),
        isTrue,
        reason: 'reply PCM is all-silence',
      );
      expect(complete.replyText, replyText);

      await chat.session.close();
      await model.close();
      await recognizer.close();
      await synthesizer.close();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
