/// On-device speech-to-text and text-to-speech for flutter_gemma, via the
/// LiteRT C API + `dart:ffi`.
///
/// Opt-in. Add to pubspec.yaml and pass instances to
/// `FlutterGemma.initialize(sttBackends: [LiteRtSttBackend()], ttsBackends:
/// [LiteRtTtsBackend()])`.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
///
/// await FlutterGemma.initialize(
///   sttBackends: [LiteRtSttBackend()],
///   ttsBackends: [LiteRtTtsBackend()],
/// );
/// ```
library;

export 'src/litert_stt_backend_stub.dart'
    if (dart.library.ffi) 'src/litert_stt_backend.dart';
export 'src/litert_tts_backend_stub.dart'
    if (dart.library.ffi) 'src/litert_tts_backend.dart';

// Voice loop — pure-Dart orchestration (no ffi), exported unconditionally.
export 'src/voice/voice_event.dart';
export 'src/voice/voice_responder.dart';
export 'src/voice/voice_session.dart';
