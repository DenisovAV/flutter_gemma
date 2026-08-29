import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart'
    show HuggingFaceResolver;
import 'package:flutter_gemma/core/registry/hugging_face_resolver_source.dart'
    show HuggingFaceResolverSource;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;

import '../availability_types.dart'
    show BuiltInAiAvailability, BuiltInAiUnavailableException;
import '../builtin_ai_hugging_face_resolver.dart'
    show BuiltInAiHuggingFaceResolver;
import 'availability_web.dart';
import 'builtin_ai_model_web.dart';

/// Built-in OS AI engine, web arm (Chrome Prompt API / Gemini Nano). Pure
/// factory: probes availability, then returns a bare [BuiltInAiModelWeb];
/// core owns the singleton lifecycle via `InferenceModel.addCloseListener`.
///
/// Identical shell to the native `BuiltInAiEngine` — same `name`,
/// `priority`, and `canHandle` (routes on `fileType == ModelFileType.builtIn`
/// regardless of platform; [BuiltInAiModels.geminiNano] just works on both
/// Android and Web because it carries that fileType).
class BuiltInAiEngine
    implements InferenceEngineProvider, HuggingFaceResolverSource {
  const BuiltInAiEngine();

  @override
  String get name => 'BuiltInAI';

  @override
  int get priority => 0;

  /// The engine's own Hugging Face resolver (same stub as the native arm):
  /// reserves the `.builtIn` slot so `resolveHuggingFace(fileType: builtIn)`
  /// throws a clear `UnsupportedError` — the OS owns the weights.
  @override
  HuggingFaceResolver get huggingFaceResolver =>
      const BuiltInAiHuggingFaceResolver();

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.builtIn;

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    final status = await BuiltInAi.availability();
    if (status != BuiltInAiAvailability.available) {
      throw BuiltInAiUnavailableException(
        status,
        'Built-in AI model "${spec.name}" is not available ($status). '
        'Call BuiltInAi.ensureReady() before creating the model.',
      );
    }

    return BuiltInAiModelWeb(
      modelType: spec.modelType,
      fileType: spec.fileType,
      maxTokens: config.maxTokens,
      supportImage: config.supportImage,
      onClose: () {}, // no-op: core resets its own state via addCloseListener
    );
  }
}
