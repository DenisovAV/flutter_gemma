/// On-device speech for flutter_gemma (STT now; TTS/voice later), via the
/// LiteRT C API + `dart:ffi`.
///
/// Opt-in. Add to pubspec.yaml and pass an instance to
/// `FlutterGemma.initialize(sttBackends: [LiteRtSttBackend()])`.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
///
/// await FlutterGemma.initialize(
///   sttBackends: [LiteRtSttBackend()],
/// );
/// ```
library;

export 'src/litert_stt_backend_stub.dart'
    if (dart.library.ffi) 'src/litert_stt_backend.dart';
