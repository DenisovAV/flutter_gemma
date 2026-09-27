/// MediaPipe (.task) on-device inference engine for flutter_gemma.
///
/// Opt-in. Add to pubspec.yaml and pass an instance to
/// `FlutterGemma.initialize(inferenceEngines: [MediaPipeEngine()])`.
///
/// ```dart
/// import 'package:flutter_edge_ai/flutter_edge_ai.dart';
/// import 'package:flutter_edge_ai_mediapipe/flutter_edge_ai_mediapipe.dart';
/// await FlutterGemma.initialize(inferenceEngines: [MediaPipeEngine()]);
/// ```
library flutter_edge_ai_mediapipe;

export 'src/mediapipe_engine_web.dart'
    if (dart.library.io) 'src/mediapipe_engine.dart';
