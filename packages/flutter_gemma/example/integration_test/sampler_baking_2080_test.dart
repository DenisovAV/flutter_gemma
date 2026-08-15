/// Upstream LiteRT-LM #2080 retest — are per-session sampler params still
/// baked at the engine's FIRST generation on v0.15.0?
///
/// Reproduces the signature posted upstream on 2026-07-28 (v0.14.0, macOS
/// arm64, Gemma 4 E2B):
///
///   G = greedy   (topK=1,  temp=0.8, seed=1) on engine A, first generation
///   X = stochastic (topK=64, temp=1.5, seed=7) on the SAME engine A
///   Y = stochastic again on the SAME engine A
///   Z = stochastic on a FRESH engine B          <- control
///
///   bug present : X == Y == G  and  Z != G   (engine locked to what the first
///                                             generation baked)
///   bug fixed   : X != G                     (later sessions honour params)
///
/// The fresh-engine control matters: without Z, an X == G result could just
/// mean the prompt is peaked enough that sampling never diverges. Z != G proves
/// these params *can* produce different text — they are simply not re-read.
///
/// Run: cd example && flutter test integration_test/sampler_baking_2080_test.dart -d macos
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'inference_test_helpers.dart' show registerTestEngines;

String get _macosDir =>
    '${Platform.environment['HOME']}/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents';
String get _model => '$_macosDir/gemma-4-E2B-it.litertlm';

const _prompt =
    'Invent a name for a cosy coffee shop. Answer with the name only.';

/// One generation on [model] with the given sampler params.
Future<String> _gen(
  InferenceModel model, {
  required int topK,
  required double temperature,
  required int randomSeed,
}) async {
  final session = await model.createSession(
    temperature: temperature,
    topK: topK,
    randomSeed: randomSeed,
  );
  await session.addQueryChunk(Message(text: _prompt, isUser: true));
  final out = (await session.getResponse()).trim();
  await session.close();
  return out;
}

Future<InferenceModel> _engine() => FlutterGemma.getActiveModel(
  maxTokens: 1024,
  preferredBackend: PreferredBackend.cpu,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await registerTestEngines();
    expect(
      File(_model).existsSync(),
      isTrue,
      reason: 'model missing at $_model',
    );
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(_model).install();
  });

  testWidgets(
    '#2080 — later sessions must honour their own sampler params',
    (_) async {
      final engineA = await _engine();
      final g = await _gen(engineA, topK: 1, temperature: 0.8, randomSeed: 1);
      final x = await _gen(engineA, topK: 64, temperature: 1.5, randomSeed: 7);
      final y = await _gen(engineA, topK: 64, temperature: 1.5, randomSeed: 7);
      await engineA.close();

      final engineB = await _engine();
      final z = await _gen(engineB, topK: 64, temperature: 1.5, randomSeed: 7);
      await engineB.close();

      // ignore: avoid_print
      print(
        '[#2080] G(greedy)="$g"\n'
        '[#2080] X(stoch, same engine)="$x"\n'
        '[#2080] Y(stoch, same engine)="$y"\n'
        '[#2080] Z(stoch, fresh engine)="$z"',
      );

      // Control first: if the fresh engine also returns G, the prompt is too
      // peaked to distinguish anything and the whole result is inconclusive.
      expect(
        z,
        isNot(equals(g)),
        reason:
            'INCONCLUSIVE: a fresh engine with stochastic params produced '
            'the greedy output too — pick a less deterministic prompt',
      );

      expect(
        x,
        isNot(equals(g)),
        reason:
            'FAIL = #2080 still reproduces on v0.15.0: the engine stayed '
            'locked to what the first (greedy) generation baked',
      );
      expect(y, isNot(equals(g)), reason: 'same, second stochastic session');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
