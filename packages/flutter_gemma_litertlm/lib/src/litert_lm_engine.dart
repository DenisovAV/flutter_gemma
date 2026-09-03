import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart'
    show HuggingFaceResolver;
import 'package:flutter_gemma/core/registry/hugging_face_resolver_source.dart'
    show HuggingFaceResolverSource;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'ffi/backend_preference.dart';
import 'ffi/ffi_inference_model.dart';
import 'ffi/litert_lm_client.dart';
import 'manifest/litertlm_manifest_resolver.dart' show LitertlmManifestResolver;

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

/// Pure map from a [RuntimeConfig] + resolved text backend to the encoder /
/// backend args of [LiteRtLmFfiClient.initialize]. Extracted from
/// [LiteRtLmEngine.createModel] so the vision↔audio wiring is unit-testable
/// without path_provider or a real FFI `dlopen` — the swap it guards is silent
/// under the default config (both encoders resolve to `cpu`).
@visibleForTesting
({
  String backend,
  bool enableVision,
  String visionBackend,
  int maxNumImages,
  bool enableAudio,
  String audioBackend,
})
encoderInitArgs(RuntimeConfig config, PreferredBackend activeBackend) => (
  backend: ffiBackendWireName(activeBackend),
  enableVision: config.supportImage,
  visionBackend: encoderBackendWireName(config.preferredVisionBackend),
  maxNumImages: config.supportImage ? (config.maxNumImages ?? 1) : 0,
  enableAudio: config.supportAudio,
  audioBackend: encoderBackendWireName(config.preferredAudioBackend),
);

/// LiteRT-LM (.litertlm) inference engine. Pure factory: builds and returns a
/// bare [InferenceModel]; core owns the singleton lifecycle and registers its
/// reset via [InferenceModel.addCloseListener] (added in a later task).
class LiteRtLmEngine
    implements InferenceEngineProvider, HuggingFaceResolverSource {
  const LiteRtLmEngine();

  @override
  String get name => 'LiteRT-LM';

  @override
  int get priority => 0;

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.litertlm;

  /// The engine's own Hugging Face resolver: reads a repo's
  /// `litertlm_manifest.json`. Auto-registered by
  /// `FlutterGemma.initialize(inferenceEngines: …)`, so `.litertlm` HF manifests
  /// resolve without a separate `huggingFaceResolvers:` list. Pass an explicit
  /// `LitertlmManifestResolver(revision: …)` to `initialize` only to override
  /// (e.g. pin a revision).
  @override
  HuggingFaceResolver get huggingFaceResolver =>
      const LitertlmManifestResolver();

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
        final args = encoderInitArgs(config, backend);
        await client.initialize(
          modelPath: config.modelPath,
          backend: args.backend,
          maxTokens: maxTokens,
          cacheDir: cacheDir,
          enableVision: args.enableVision,
          visionBackend: args.visionBackend,
          maxNumImages: args.maxNumImages,
          enableAudio: args.enableAudio,
          audioBackend: args.audioBackend,
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
