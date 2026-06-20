import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'ffi/backend_preference.dart';
import 'ffi/ffi_inference_model.dart';
import 'ffi/litert_lm_client.dart';

/// Minimum context window (`max_num_tokens`) for `.litertlm` models.
///
/// `.litertlm` models bake a fixed `kv_cache_max_len` (1024 for every
/// supported model — e.g. Gemma 4 E2B, FunctionGemma). The native engine sizes
/// its KV-cache from `max_num_tokens`; a value below the baked length
/// underflows the magic-number tensor resize and `DYNAMIC_UPDATE_SLICE` then
/// fails to allocate tensors at generation time (#318 — verified on a Pixel
/// 8a: 512 crashes, 1024 works). No native API reports the model's minimum, so
/// we clamp up to the largest known minimum. Clamping up only over-allocates a
/// few MB of KV-cache and never under-allocates.
const int kMinLitertlmContextTokens = 1024;

/// Raises [maxTokens] to [kMinLitertlmContextTokens] when a caller passes a
/// value below it. Such values were almost certainly meant to cap *output*
/// length — `maxTokens` is the whole CONTEXT WINDOW (input + output, the
/// KV-cache), not the generation length. To limit generation, pass
/// `maxOutputTokens` to `createSession`.
@visibleForTesting
int clampLitertlmContextTokens(int maxTokens) {
  if (maxTokens >= kMinLitertlmContextTokens) return maxTokens;
  gemmaLog(
    '[LiteRtLmEngine] maxTokens ($maxTokens) is below the minimum context '
    'size for .litertlm models; clamping to $kMinLitertlmContextTokens. '
    'maxTokens is the CONTEXT WINDOW (KV-cache, input + output) — not the '
    'generation length. Use maxOutputTokens on createSession to cap how many '
    'tokens are generated.',
  );
  return kMinLitertlmContextTokens;
}

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
    final maxTokens = clampLitertlmContextTokens(config.maxTokens);
    final ffiRuntime = await initializeFfiRuntime<LiteRtLmFfiClient>(
      preferredBackend: config.preferredBackend,
      logTag: '[LiteRtLmEngine]',
      createClient: LiteRtLmFfiClient.new,
      initializeClient: (client, backend) async {
        await client.initialize(
          modelPath: config.modelPath,
          backend: ffiBackendWireName(backend),
          maxTokens: maxTokens,
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
      maxTokens: maxTokens,
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
