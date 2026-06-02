import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart'
    show InferenceModelSpec;

/// Web/no-FFI fallback. The package's LiteRT-LM engine is native-only in this
/// version; web LiteRT-LM is still provided by core (the web inference model is
/// part of the core web library). The web target never instantiates this.
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
  ) async =>
      throw UnsupportedError(
        'LiteRtLmEngine is native-only in this version; web LiteRT-LM is '
        'provided by core until the MediaPipe web extract.',
      );
}
