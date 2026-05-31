import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart'
    show InferenceModelSpec;

/// Platform per-engine build step. `modelPath`/`cacheDir` are resolved by the
/// platform `createModel` preamble and threaded through so the existing
/// construction arms stay byte-identical. Internal to Phase A; Phase B engine
/// packages implement [InferenceEngineProvider.createModel] directly.
typedef DefaultEngineBuild = Future<InferenceModel> Function(
  InferenceModelSpec spec,
  RuntimeConfig config,
  String modelPath,
  String? cacheDir,
);

/// Default MediaPipe engine adapter for `.task`/`.bin` models. Wraps the
/// platform's existing MediaPipe construction arm via [callBuild]; the 2-arg
/// [createModel] is unused in Phase A (the platform calls [callBuild] after the
/// registry selects this engine).
class DefaultMediaPipeEngine implements InferenceEngineProvider {
  DefaultMediaPipeEngine(this._build);
  final DefaultEngineBuild _build;
  @override
  String get name => 'MediaPipe';
  @override
  int get priority => 0;
  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.task ||
      spec.fileType == ModelFileType.binary;
  @override
  Future<InferenceModel> createModel(
          InferenceModelSpec spec, RuntimeConfig config) =>
      throw UnsupportedError(
          'DefaultMediaPipeEngine is built via the platform; use callBuild.');
  Future<InferenceModel> callBuild(InferenceModelSpec spec,
          RuntimeConfig config, String modelPath, String? cacheDir) =>
      _build(spec, config, modelPath, cacheDir);
}

/// Default LiteRT-LM engine adapter for `.litertlm` models. Wraps the
/// platform's existing FFI construction arm via [callBuild]; the 2-arg
/// [createModel] is unused in Phase A (the platform calls [callBuild] after the
/// registry selects this engine).
class DefaultLiteRtLmEngine implements InferenceEngineProvider {
  DefaultLiteRtLmEngine(this._build);
  final DefaultEngineBuild _build;
  @override
  String get name => 'LiteRT-LM';
  @override
  int get priority => 0;
  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.litertlm;
  @override
  Future<InferenceModel> createModel(
          InferenceModelSpec spec, RuntimeConfig config) =>
      throw UnsupportedError(
          'DefaultLiteRtLmEngine is built via the platform; use callBuild.');
  Future<InferenceModel> callBuild(InferenceModelSpec spec,
          RuntimeConfig config, String modelPath, String? cacheDir) =>
      _build(spec, config, modelPath, cacheDir);
}
