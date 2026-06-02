import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart'
    show InferenceModelSpec;

/// Web placeholder for [MediaPipeEngine]. Selected by the barrel's conditional
/// export on non-`dart.library.io` targets (web). It satisfies the
/// [InferenceEngineProvider] contract so the conditional export's two branches
/// are type-compatible, but throws on [createModel] — the real web (MediaPipe
/// JS) arm lands in a later task.
class MediaPipeEngine implements InferenceEngineProvider {
  const MediaPipeEngine();

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
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    throw UnsupportedError(
      'MediaPipeEngine web support is not yet wired in this build.',
    );
  }
}
