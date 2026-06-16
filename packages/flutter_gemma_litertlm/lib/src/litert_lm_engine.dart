import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:path_provider/path_provider.dart';

import 'ffi/backend_preference.dart';
import 'ffi/ffi_inference_model.dart';
import 'ffi/litert_lm_client.dart';

/// LiteRT-LM (.litertlm) inference engine. Pure factory: builds and returns a
/// bare [InferenceModel]; core owns the singleton lifecycle and registers its
/// reset via [InferenceModel.addCloseListener] (added in a later task).
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
    final cacheDir = (await getApplicationSupportDirectory()).path;
    final ffiRuntime = await initializeFfiRuntime<LiteRtLmFfiClient>(
      preferredBackend: config.preferredBackend,
      logTag: '[LiteRtLmEngine]',
      createClient: LiteRtLmFfiClient.new,
      initializeClient: (client, backend) async {
        await client.initialize(
          modelPath: config.modelPath,
          backend: ffiBackendWireName(backend),
          maxTokens: config.maxTokens,
          cacheDir: cacheDir,
          enableVision: config.supportImage,
          maxNumImages: config.supportImage ? (config.maxNumImages ?? 1) : 0,
          enableAudio: config.supportAudio,
          enableSpeculativeDecoding: config.enableSpeculativeDecoding,
        );
      },
      shutdownClient: (client) => client.shutdown(),
    );

    return FfiInferenceModel(
      ffiClient: ffiRuntime.client,
      maxTokens: config.maxTokens,
      modelType: spec.modelType,
      activeBackend: ffiRuntime.activeBackend,
      fileType: spec.fileType,
      supportImage: config.supportImage,
      supportAudio: config.supportAudio,
      maxConcurrentSessions: config.maxConcurrentSessions,
      onClose: () {}, // no-op: core resets its own state via addCloseListener
    );
  }
}
