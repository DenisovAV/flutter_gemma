import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _activeModelParamsTests();

  test('carries the resolved modelPath and optional tokenizerPath', () {
    const c = RuntimeConfig(
      maxTokens: 512,
      modelPath: '/tmp/m.litertlm',
      tokenizerPath: '/tmp/tok.json',
    );
    expect(c.modelPath, '/tmp/m.litertlm');
    expect(c.tokenizerPath, '/tmp/tok.json');
  });

  test('tokenizerPath defaults to null for inference', () {
    const c = RuntimeConfig(maxTokens: 256, modelPath: '/m');
    expect(c.tokenizerPath, isNull);
  });
}

void _activeModelParamsTests() {
  group('ActiveModelParams.firstDifference', () {
    const base = ActiveModelParams(maxTokens: 1024);

    test('identical params reuse the cached model', () {
      expect(
        base.firstDifference(const ActiveModelParams(maxTokens: 1024)),
        isNull,
      );
    });

    test('names the differing parameter, not just "changed"', () {
      // The whole point: a caller who asks for CPU after a GPU build used to
      // get the GPU model in silence. The name is what makes the log
      // actionable — "paramsChanged=true" tells nobody what to change.
      expect(
        base.firstDifference(
          const ActiveModelParams(
            maxTokens: 1024,
            preferredBackend: PreferredBackend.cpu,
          ),
        ),
        'preferredBackend',
      );
    });

    test('covers every parameter getActiveModel accepts', () {
      // Nine knobs. Desktop compared three and mobile compared none, so the
      // rest were silently ignored on reuse. Each must force a rebuild.
      final cases = <String, ActiveModelParams>{
        'maxTokens': const ActiveModelParams(maxTokens: 4096),
        'preferredBackend': const ActiveModelParams(
          maxTokens: 1024,
          preferredBackend: PreferredBackend.gpu,
        ),
        'preferredVisionBackend': const ActiveModelParams(
          maxTokens: 1024,
          preferredVisionBackend: PreferredBackend.gpu,
        ),
        'preferredAudioBackend': const ActiveModelParams(
          maxTokens: 1024,
          preferredAudioBackend: PreferredBackend.gpu,
        ),
        'supportImage': const ActiveModelParams(
          maxTokens: 1024,
          supportImage: true,
        ),
        'supportAudio': const ActiveModelParams(
          maxTokens: 1024,
          supportAudio: true,
        ),
        'maxNumImages': const ActiveModelParams(
          maxTokens: 1024,
          maxNumImages: 4,
        ),
        'enableSpeculativeDecoding': const ActiveModelParams(
          maxTokens: 1024,
          enableSpeculativeDecoding: true,
        ),
        'maxConcurrentSessions': const ActiveModelParams(
          maxTokens: 1024,
          maxConcurrentSessions: 2,
        ),
      };
      for (final entry in cases.entries) {
        expect(
          base.firstDifference(entry.value),
          entry.key,
          reason: '${entry.key} must force a rebuild',
        );
      }
      expect(cases.length, 9, reason: 'getActiveModel takes nine knobs');
    });
  });
}
