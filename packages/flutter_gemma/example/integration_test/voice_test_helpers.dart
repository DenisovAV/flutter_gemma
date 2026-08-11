// Shared helpers for voice-loop integration tests.
// Not a test file — imported by voice_*_test.dart files.

import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' show SpeechRecognizer;

/// A [SpeechRecognizer] that ignores the PCM and returns a fixed transcript, so
/// voice ITs exercise the LLM/tools/TTS path deterministically (real STT is
/// covered by voice_loop_test.dart / stt_moonshine_test.dart).
class FixedTranscriptRecognizer implements SpeechRecognizer {
  FixedTranscriptRecognizer(this.transcript);

  final String transcript;

  @override
  Future<String> transcribe(Uint8List pcm16kMono) async => transcript;

  @override
  void addCloseListener(void Function() listener) {}

  @override
  Future<void> close() async {}
}
