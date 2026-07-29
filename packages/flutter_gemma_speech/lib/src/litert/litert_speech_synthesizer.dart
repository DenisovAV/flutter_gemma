// `SpeechSynthesizer` facade over a background isolate, mirroring
// `litert_speech_recognizer.dart` (Task 2.5 direct STT→TTS mirror). The
// blocking LiteRT text-frontend + CFM/vocoder forward passes run on a
// dedicated [TtsWorker] isolate — spawned once, reused for every call — so
// the UI isolate stays free.
//
// The native code lives in `tts_core.dart` (driven inside the worker
// isolate, Task 2.3) plus `tts_text_frontend.dart` (Task 2.2); this file is
// the public, async, main-isolate API generic over [TtsModelProfile] —
// matcha/kokoro/supertonic select a profile, not a synthesizer subclass.

import 'dart:typed_data';

import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show SpeechSynthesizer;

import '../model/tts_model_profile.dart';
import 'tts_worker.dart';

/// Signature for the `onClose` callback. Same name Flutter uses.
typedef VoidCallback = void Function();

/// Generic LiteRT-backed [SpeechSynthesizer]. Runs whichever model
/// [TtsModelProfile] describes — it is NOT hardcoded to matcha; adding a new
/// profile is enough to support a new TTS family without a new synthesizer
/// class. Unlike STT, there is no input-conversion step: the worker takes
/// text in and returns 16-bit PCM bytes out.
class LiteRtSpeechSynthesizer extends SpeechSynthesizer with CloseNotifier {
  LiteRtSpeechSynthesizer._(this._worker, this.onClose);

  final TtsWorker _worker;
  final VoidCallback onClose;
  bool _isClosed = false;

  /// Load [profile]'s frontend + native model bundle and prepare it for
  /// synthesis on a background isolate.
  ///
  /// [artifactPaths] maps each of [profile]'s bundle filenames (config,
  /// dict, embedding, and the `.tflite` graphs) to their resolved on-disk
  /// paths. [preferredBackend] selects the LiteRT hardware accelerator
  /// (defaults to CPU).
  ///
  /// Caller owns the returned instance and must call [close] when done.
  static Future<LiteRtSpeechSynthesizer> create({
    required TtsModelProfile profile,
    required Map<String, String> artifactPaths,
    PreferredBackend? preferredBackend,
    VoidCallback? onClose,
  }) async {
    final worker = await TtsWorker.spawn(
      profile: profile,
      artifactPaths: artifactPaths,
      backend: preferredBackend,
    );
    return LiteRtSpeechSynthesizer._(worker, onClose ?? () {});
  }

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
        'LiteRtSpeechSynthesizer is closed; create a new instance to use it',
      );
    }
  }

  @override
  int get sampleRate => _worker.sampleRate;

  @override
  Future<Uint8List> synthesize(String text) {
    _assertNotClosed();
    return _worker.synthesize(text);
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
