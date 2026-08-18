import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;

import 'ffi/gen_ai_client.dart';
import 'onnx_inference_model.dart';

/// ONNX Runtime GenAI on-device inference engine.
///
/// **macOS-first host arm (hardened plan Phase 3, design §11 D2).**
/// [createModel] productionizes the ORT-GenAI FFI path (`GenAiFfiClient` →
/// `OnnxInferenceModel`/`OnnxSession`) — text-only, greedy decoding, one
/// session at a time. Android/iOS device work stays behind the D2
/// throughput/RAM go/no-go gate (native archives + shas for those platforms
/// aren't published yet; see `hook/build.dart`'s platform table).
///
/// Mirrors [LiteRtLmEngine] from `flutter_gemma_litertlm`: a pure factory
/// that core probes via [canHandle] and calls to build a bare
/// [InferenceModel]; core owns the singleton lifecycle.
class OnnxEngine implements InferenceEngineProvider {
  /// [clientFactory] is the injection seam for tests — defaults to the real
  /// `dart:ffi` worker-isolate client. Never override it in production code;
  /// it exists so `test/onnx_engine_test.dart` can inject a fake with zero
  /// dlopen (hardened plan Task 6).
  const OnnxEngine({GenAiClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final GenAiClient Function() _clientFactory;

  static GenAiClient _defaultClientFactory() => GenAiFfiClient();

  @override
  String get name => 'ONNX';

  @override
  int get priority => 0;

  /// `hook/build.dart`'s `_archivesFor` currently ships ORT/ORT-GenAI
  /// prebuilts for macOS arm64 ONLY — every other (os, arch) has no
  /// registered CodeAsset, so `GenAiFfiClient`'s worker-side dlopen would
  /// fail at first use with a confusing native error instead of routing to
  /// another engine (there is none for `.onnx` yet) or failing with a clear
  /// "not supported on this platform" message. Keep this in lockstep with
  /// the hook's platform table as it grows (device go/no-go, hardened plan
  /// D2 tail).
  static bool get _isSupportedHost =>
      Platform.isMacOS && Abi.current() == Abi.macosArm64;

  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.onnx && _isSupportedHost;

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    // The install layer hands inference engines a single resolved FILE path
    // per `InferenceModelSpec` (`RuntimeConfig.modelPath` —
    // `manager.getModelFilePaths(...).values.first`, see
    // `flutter_gemma_mobile.dart`'s createModel preamble). ORT-GenAI models
    // are whole DIRECTORIES (`genai_config.json` + `.onnx`[+`.onnx_data`] +
    // tokenizer files); v1 takes that file's PARENT directory as the model
    // dir. This assumes the whole bundle already lives alongside the one
    // tracked file on disk — true for the macOS host smoke (which points
    // `ONNX_SMOKE_GENAI_MODEL_DIR` straight at a pre-populated directory) but
    // NOT yet true for a real network install, which only downloads that one
    // tracked file. Multi-file bundle install (mirroring the TTS
    // `artifactPaths` pattern) is a known gap, left for the device-gated
    // follow-on — this precheck turns it into a clear, loud error instead of
    // a confusing native failure.
    final modelDir = File(config.modelPath).parent.path;
    final configFile = File('$modelDir/genai_config.json');
    if (!configFile.existsSync()) {
      throw StateError(
        'ONNX GenAI model directory "$modelDir" has no genai_config.json — '
        'expected an ORT-GenAI model directory '
        '(genai_config.json + .onnx[+.onnx_data] + tokenizer files) '
        'installed as a single bundle. Multi-file bundle install is not '
        'yet wired through FlutterGemma.installModel() for ModelFileType.onnx '
        '(hardened plan Phase 3 Task 2 known gap) — point modelPath at a '
        'pre-populated directory for now.',
      );
    }

    final client = _clientFactory();
    await client.load(modelDir, contextWindow: config.maxTokens);

    return OnnxInferenceModel(
      client: client,
      maxTokens: config.maxTokens,
      modelType: spec.modelType,
      activeBackend: config.preferredBackend ?? PreferredBackend.cpu,
      fileType: spec.fileType,
      onClose: () {},
    );
  }
}
