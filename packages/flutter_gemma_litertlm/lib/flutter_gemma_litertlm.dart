/// LiteRT-LM (.litertlm) on-device inference engine for flutter_gemma.
///
/// Opt-in. Add to pubspec.yaml and pass an instance to
/// `FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()])`.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
///
/// await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);
/// ```
library flutter_gemma_litertlm;

export 'src/litert_lm_engine_stub.dart'
    if (dart.library.ffi) 'src/litert_lm_engine.dart';
