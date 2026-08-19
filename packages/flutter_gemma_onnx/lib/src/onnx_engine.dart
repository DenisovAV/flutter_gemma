import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart' show gemmaLog;
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;

import 'ffi/gen_ai_client.dart';
import 'onnx_inference_model.dart';

/// ONNX Runtime GenAI on-device inference engine.
///
/// **macOS/Linux/Windows host arm (hardened plan Phase 3, design §11 D2).**
/// [createModel] productionizes the ORT-GenAI FFI path (`GenAiFfiClient` →
/// `OnnxInferenceModel`/`OnnxSession`) — text-only, greedy decoding, one
/// session at a time. Android/iOS device work stays behind the D2
/// throughput/RAM go/no-go gate — Android's archives are now bundled by
/// `hook/build.dart` (so `onnx_inference_smoke_test.dart` can run on FTL),
/// but this engine deliberately does NOT select itself there yet: the gate
/// widens only after that test's numbers pass go/no-go, same as the
/// mac/linux/windows sequence. iOS archives/shas aren't published yet at
/// all; see `hook/build.dart`'s platform table.
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

  /// Deliberately narrower than `hook/build.dart`'s `_archivesFor`: the hook
  /// also bundles the Android arm64 archives (so the FFI layer can be
  /// device-tested via `onnx_inference_smoke_test.dart` for the
  /// throughput/RAM go/no-go), but this engine only SELECTS ITSELF on
  /// macOS/Linux/Windows until that measurement passes — without this gate,
  /// `GenAiFfiClient`'s worker-side dlopen would fail at first use with a
  /// confusing native error on a platform whose archive exists but hasn't
  /// been validated, instead of routing to another engine (there is none
  /// for `.onnx` yet) or failing with a clear "not supported on this
  /// platform" message. Widen deliberately once the gate passes for a given
  /// platform — never let it drift ahead of validation.
  static bool get _isSupportedHost {
    if (debugForceUnsupportedHost == true) return false;
    final abi = Abi.current();
    // Keep in lockstep with hook/build.dart's `_archivesFor` table — MINUS
    // Android, which is bundled but not yet device-verified (see doc above).
    return (Platform.isMacOS && abi == Abi.macosArm64) ||
        (Platform.isLinux && abi == Abi.linuxX64) ||
        (Platform.isWindows && abi == Abi.windowsX64);
  }

  /// Test-only override: when `true`, [_isSupportedHost] reports false
  /// regardless of the real host — the cheapest seam to exercise the
  /// unsupported-host branches of [canHandle]/[createModel] on a macOS-arm64
  /// CI/dev host without an actual non-macOS-arm64 machine. Never read or
  /// set outside `test/`. Reset to `null` in `tearDown`.
  @visibleForTesting
  static bool? debugForceUnsupportedHost;

  @override
  bool canHandle(InferenceModelSpec spec) {
    if (spec.fileType != ModelFileType.onnx) return false;
    if (!_isSupportedHost) {
      gemmaLog(
        'OnnxEngine declined ${Platform.operatingSystem}/${Abi.current()}: '
        'native ORT archives are macOS-arm64/linux-x64/windows-x64-only in '
        'v1 (Android arm64 is bundled but not yet device-verified; see '
        'hook/build.dart `_archivesFor`).',
      );
      return false;
    }
    return true;
  }

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    // Belt-and-suspenders: canHandle already gates this in the normal
    // registry-dispatch path, but createModel is reachable directly (manual
    // construction / a registry bypass) — fail loud instead of dlopen-ing a
    // native archive that was never shipped for this host.
    if (!_isSupportedHost) {
      throw StateError(
        'OnnxEngine.createModel called on unsupported host '
        '${Platform.operatingSystem}/${Abi.current()} — ONNX native archives '
        'are macOS-arm64/linux-x64/windows-x64-only in v1 (Android arm64 is '
        'bundled but not yet device-verified; see hook/build.dart '
        '`_archivesFor`).',
      );
    }

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
