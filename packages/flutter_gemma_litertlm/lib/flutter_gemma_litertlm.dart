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

export 'src/litert_lm_engine_web.dart'
    if (dart.library.ffi) 'src/litert_lm_engine.dart';

// LiteRt interpreter FFI (arbitrary `.tflite` models) — used by
// flutter_gemma_embeddings and flutter_gemma_speech. `dart.library.ffi`-only;
// the web stub exports no symbols (web leaves use their own JS arm).
export 'src/ffi/litert_bindings_stub.dart'
    if (dart.library.ffi) 'src/ffi/litert_bindings.dart';
