import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;

/// ONNX Runtime GenAI on-device inference engine.
///
/// **Scaffold only (v1 slice).** Claims `ModelFileType.onnx` specs so the
/// registry probe (core's `EngineRegistry`) selects it correctly once
/// registered, but [createModel] is not yet implemented — productionizing
/// the ORT-GenAI FFI path (`OgaCreateModel` → ... → `getResponseAsync()`) is
/// gated on a device generation-throughput go/no-go measurement (design doc
/// §8/§11 D2; hardened plan Task 0a). Building the full native stack before
/// that number exists is explicitly out of scope.
///
/// Mirrors [LiteRtLmEngine] from `flutter_gemma_litertlm`: a pure factory
/// that core probes via [canHandle] and calls to build a bare
/// [InferenceModel]; core owns the singleton lifecycle.
class OnnxEngine implements InferenceEngineProvider {
  const OnnxEngine();

  @override
  String get name => 'ONNX';

  @override
  int get priority => 0;

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.onnx;

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    throw UnimplementedError('inference — pending throughput gate');
  }
}
