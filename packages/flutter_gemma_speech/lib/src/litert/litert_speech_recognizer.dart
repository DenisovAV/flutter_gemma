// `SpeechRecognizer` facade over a background isolate, mirroring
// `litert_embedding_model.dart` (#299). The blocking LiteRT encode+decode
// forward passes run on a dedicated [SttWorker] isolate — spawned once,
// reused for every call — so the UI isolate stays free.
//
// The native code lives in `stt_core.dart` (driven inside the worker
// isolate); this file is the public, async, main-isolate API generic over
// [SttModelProfile] — moonshine/whisper/parakeet select a profile, not a
// recognizer subclass.

import 'dart:typed_data';

import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show SpeechRecognizer;

import '../model/stt_model_profile.dart';
import 'stt_worker.dart';

/// Signature for the `onClose` callback. Same name Flutter uses.
typedef VoidCallback = void Function();

/// Convert little-endian 16-bit PCM bytes to normalized `[-1, 1]` float32
/// samples (`/32768.0`), per the verified recipe's WAV→float32 step
/// (`docs/superpowers/notes/stt-transcript-recipe.md`).
Float32List pcm16LEToFloat32(Uint8List pcm) {
  final byteData = ByteData.sublistView(pcm);
  final sampleCount = pcm.lengthInBytes ~/ 2;
  final samples = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// Generic LiteRT-backed [SpeechRecognizer]. Runs whichever model
/// [SttModelProfile] describes — it is NOT hardcoded to moonshine; adding a
/// new profile (+ a mel frontend for log-mel models) is enough to support a
/// new STT family without a new recognizer class.
class LiteRtSpeechRecognizer extends SpeechRecognizer with CloseNotifier {
  LiteRtSpeechRecognizer._(this._worker, this.onClose);

  final SttWorker _worker;
  final VoidCallback onClose;
  bool _isClosed = false;

  /// Load [profile]'s model + tokenizer and prepare it for transcription on
  /// a background isolate.
  ///
  /// [modelPath] points at a `.tflite` STT model; [tokenizerPath] at its HF
  /// `tokenizer.json`. [preferredBackend] selects the LiteRT hardware
  /// accelerator (defaults to CPU).
  ///
  /// Caller owns the returned instance and must call [close] when done.
  static Future<LiteRtSpeechRecognizer> create({
    required SttModelProfile profile,
    required String modelPath,
    required String tokenizerPath,
    PreferredBackend? preferredBackend,
    VoidCallback? onClose,
  }) async {
    final worker = await SttWorker.spawn(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      profile: profile,
      backend: preferredBackend,
    );
    return LiteRtSpeechRecognizer._(worker, onClose ?? () {});
  }

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
        'LiteRtSpeechRecognizer is closed; create a new instance to use it',
      );
    }
  }

  @override
  Future<String> transcribe(Uint8List pcm16kMono) {
    _assertNotClosed();
    final samples = pcm16LEToFloat32(pcm16kMono);
    return _worker.transcribe(samples);
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      await _worker.close();
    } finally {
      onClose();
      fireCloseListeners();
    }
  }
}
