import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/web/web_model_source.dart';

import 'web/litert_lm_web_inference.dart';

/// Web LiteRT-LM (`@litert-lm/core`) inference engine. A REAL engine (not a
/// stub): builds [LiteRtLmWebInferenceModel] from a [WebModelSourceResolver]
/// it constructs itself via `forActiveModel()`. `createModel` is a pure factory
/// — core owns the singleton lifecycle via [InferenceModel.addCloseListener].
class LiteRtLmEngine implements InferenceEngineProvider {
  const LiteRtLmEngine();

  @override
  String get name => 'LiteRT-LM';

  @override
  int get priority => 0;

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.litertlm;

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    return LiteRtLmWebInferenceModel(
      sourceResolver: WebModelSourceResolver.forActiveModel(),
      maxTokens: config.maxTokens,
      modelType: spec.modelType,
      maxConcurrentSessions: config.maxConcurrentSessions,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }
}
