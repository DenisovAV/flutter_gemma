import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;

/// Ready-made [InferenceModelSpec]s for the OS built-in models.
///
/// These specs carry an *inert* bundled source: the built-in engine never
/// downloads or reads a file — the OS owns the weights — so the source is only
/// an identity token. Both are `fileType: ModelFileType.builtIn`, which is what
/// [BuiltInAiEngine.canHandle] matches on and what makes core's install
/// pipeline skip the (nonexistent) file.
abstract final class BuiltInAiModels {
  /// Gemini Nano via Android ML Kit GenAI (AICore). `name: 'gemini-nano'`.
  static InferenceModelSpec get geminiNano => InferenceModelSpec(
    name: 'gemini-nano',
    modelSource: ModelSource.bundled('gemini-nano'),
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  );

  /// Apple Foundation Models (iOS/macOS). `name: 'apple-foundation-models'`.
  static InferenceModelSpec get appleFoundationModels => InferenceModelSpec(
    name: 'apple-foundation-models',
    modelSource: ModelSource.bundled('apple-foundation-models'),
    modelType: ModelType.general,
    fileType: ModelFileType.builtIn,
  );
}
