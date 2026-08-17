/// ONNX Runtime GenAI on-device inference engine for flutter_gemma.
///
/// Opt-in. Add to pubspec.yaml and pass an instance to
/// `FlutterGemma.initialize(inferenceEngines: [OnnxEngine()])`.
///
/// **Scaffold only (v1 slice)** — see [OnnxEngine]'s doc comment: identity +
/// `canHandle` work, `createModel` throws `UnimplementedError` pending the
/// device generation-throughput go/no-go gate.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';
///
/// await FlutterGemma.initialize(
///   inferenceEngines: [OnnxEngine()],
/// );
/// ```
library;

export 'src/onnx_engine.dart';
