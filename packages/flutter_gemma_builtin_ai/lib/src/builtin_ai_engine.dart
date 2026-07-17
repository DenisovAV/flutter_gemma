import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;

import 'availability.dart';
import 'builtin_ai_model.dart';

/// Built-in OS AI engine (Gemini Nano via ML Kit GenAI on Android; Apple
/// Foundation Models on iOS/macOS). Pure factory: probes availability, tells
/// the native host to create the model, then returns a bare [BuiltInAiModel];
/// core owns the singleton lifecycle via [InferenceModel.addCloseListener].
class BuiltInAiEngine implements InferenceEngineProvider {
  const BuiltInAiEngine();

  @override
  String get name => 'BuiltInAI';

  @override
  int get priority => 0;

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.builtIn;

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    // The OS model must be ready before we ask the host to create it. A
    // non-`available` status is a hard failure here (call
    // [BuiltInAi.ensureReady] first to download/prepare it).
    final status = mapAvailability(await builtInAiService.checkAvailability());
    if (status != BuiltInAiAvailability.available) {
      throw BuiltInAiUnavailableException(
        status,
        'Built-in AI model "${spec.name}" is not available ($status). '
        'Call BuiltInAi.ensureReady() before creating the model.',
      );
    }

    await builtInAiService.createModel(supportImage: config.supportImage);

    return BuiltInAiModel(
      service: builtInAiService,
      modelType: spec.modelType,
      fileType: spec.fileType,
      maxTokens: config.maxTokens,
      supportImage: config.supportImage,
      onClose: () {}, // no-op: core resets its own state via addCloseListener
    );
  }
}
