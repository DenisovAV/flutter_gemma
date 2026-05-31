import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/registry/default_engines.dart';
import 'package:flutter_gemma/core/registry/engine_registry.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart'
    show InferenceModelSpec;

InferenceModelSpec _spec(ModelFileType ft,
        {ModelType type = ModelType.general}) =>
    InferenceModelSpec(
      name: 'test',
      modelSource: AssetSource('models/test.bin'),
      modelType: type,
      fileType: ft,
    );

void main() {
  setUp(() => EngineRegistry.instance.reset());

  // Regression guard for the stale-closure bug: a default engine is registered
  // ONCE into the global registry (lazy), then invoked on every createModel
  // call. callBuild MUST forward its own (spec, config, modelPath, cacheDir)
  // args to the injected build fn — NOT values captured at registration time —
  // so the 2nd+ createModel call builds with the CURRENT params. The bug was a
  // build closure that read enclosing-scope locals instead of the params.
  test(
      'callBuild forwards the per-call config/spec/path to the build fn '
      'on every invocation (no stale capture)', () async {
    final seen = <({int maxTokens, ModelFileType fileType, String path})>[];

    // The injected build fn records exactly what it was handed. A correct
    // platform build reads from these params; a buggy one would read stale
    // captured locals and the recorded values would not change between calls.
    final engine = DefaultLiteRtLmEngine(
      (spec, config, modelPath, cacheDir) async {
        seen.add((
          maxTokens: config.maxTokens,
          fileType: spec.fileType,
          path: modelPath,
        ));
        // Return a sentinel; the model itself is irrelevant to this contract.
        throw _Sentinel();
      },
    );

    // Register ONCE — mirrors the platform's lazy `registered.isEmpty` guard.
    EngineRegistry.instance.registerAll([engine]);

    // Call #1: maxTokens 100, .litertlm, path A.
    await expectLater(
      engine.callBuild(_spec(ModelFileType.litertlm),
          const RuntimeConfig(maxTokens: 100), '/models/a.litertlm', null),
      throwsA(isA<_Sentinel>()),
    );

    // Call #2 on the SAME cached engine: maxTokens 999, path B.
    await expectLater(
      engine.callBuild(_spec(ModelFileType.litertlm),
          const RuntimeConfig(maxTokens: 999), '/models/b.litertlm', null),
      throwsA(isA<_Sentinel>()),
    );

    expect(seen, hasLength(2));
    expect(seen[0].maxTokens, 100);
    expect(seen[0].path, '/models/a.litertlm');
    // The critical assertion: the SECOND build saw the SECOND call's params,
    // not the first call's stale values.
    expect(seen[1].maxTokens, 999, reason: 'stale-closure regression');
    expect(seen[1].path, '/models/b.litertlm',
        reason: 'stale-closure regression');
  });

  test(
      'the 2-arg createModel on a default engine throws UnsupportedError '
      '(platform must use callBuild)', () {
    final engine = DefaultMediaPipeEngine(
        (spec, config, modelPath, cacheDir) async => throw _Sentinel());
    expect(
      () => engine.createModel(
          _spec(ModelFileType.task), const RuntimeConfig(maxTokens: 1)),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

class _Sentinel implements Exception {}
