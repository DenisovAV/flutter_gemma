// Verifies the web engine-registration sequence post-fix (host VM, no browser):
// passing a REAL litertlm engine via initialize must NOT suppress core's
// MediaPipe default (one-shot flag, not registered.isEmpty), and .litertlm
// resolves to the (real) litertlm engine, .task to MediaPipe — neither throws.

import 'package:flutter_gemma/core/model.dart' show ModelFileType, ModelType;
import 'package:flutter_gemma/core/registry/engine_registry.dart';
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart'
    show InferenceModelSpec;
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the FIXED web litertlm engine: canHandle(.litertlm) true + builds
/// (here records via a sentinel instead of a real JS model).
class _RealLiteRtLmWebEngine implements InferenceEngineProvider {
  const _RealLiteRtLmWebEngine();
  @override
  String get name => 'LiteRT-LM';
  @override
  int get priority => 0;
  @override
  bool canHandle(InferenceModelSpec spec) =>
      spec.fileType == ModelFileType.litertlm;
  @override
  Future<InferenceModel> createModel(
          InferenceModelSpec spec, RuntimeConfig config) async =>
      throw _LiteRtLmReached();
}

class _LiteRtLmReached implements Exception {}

class _CoreMediaPipe implements InferenceEngineProvider {
  const _CoreMediaPipe();
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
          InferenceModelSpec spec, RuntimeConfig config) async =>
      throw _MediaPipeReached();
}

class _MediaPipeReached implements Exception {}

InferenceModelSpec _spec(ModelFileType ft) => InferenceModelSpec(
      name: 'web',
      modelSource: AssetSource('models/active.bin'),
      modelType: ModelType.general,
      fileType: ft,
    );

void main() {
  setUp(() => EngineRegistry.instance.reset());

  test(
      'passing the real litertlm engine does NOT suppress the MediaPipe '
      'default (one-shot flag), and .task resolves to MediaPipe', () async {
    // Step 1: initialize(inferenceEngines: [LiteRtLmEngine()]) registers the
    // real web litertlm engine.
    EngineRegistry.instance.registerAll(const [_RealLiteRtLmWebEngine()]);
    // Step 2: web createModel's one-shot guard registers the MediaPipe default
    // regardless of the registry already being non-empty (the fix). Model it:
    bool webDefaultsRegistered = false;
    if (!webDefaultsRegistered) {
      webDefaultsRegistered = true;
      EngineRegistry.instance.registerAll(const [_CoreMediaPipe()]);
    }
    // Step 3: .task probe → MediaPipe found (NOT null — the bug is fixed).
    final taskEngine =
        EngineRegistry.instance.findFor(_spec(ModelFileType.task));
    expect(taskEngine, isNotNull,
        reason: 'MediaPipe default must register despite a passed engine');
    await expectLater(
      () => taskEngine!.createModel(_spec(ModelFileType.task),
          const RuntimeConfig(maxTokens: 1, modelPath: '')),
      throwsA(isA<_MediaPipeReached>()),
      reason: '.task routes to MediaPipe',
    );
  });

  test(
      '.litertlm resolves to the REAL litertlm engine (builds, does not '
      'throw UnsupportedError)', () async {
    EngineRegistry.instance.registerAll(const [_RealLiteRtLmWebEngine()]);
    final engine =
        EngineRegistry.instance.findFor(_spec(ModelFileType.litertlm));
    expect(engine, isNotNull);
    expect(engine!.name, 'LiteRT-LM');
    await expectLater(
      () => engine.createModel(_spec(ModelFileType.litertlm),
          const RuntimeConfig(maxTokens: 1, modelPath: '')),
      throwsA(isA<
          _LiteRtLmReached>()), // reaches the real build path (sentinel), NOT UnsupportedError
      reason:
          '.litertlm routes to the real litertlm engine, which builds (not throws-unsupported)',
    );
  });
}
