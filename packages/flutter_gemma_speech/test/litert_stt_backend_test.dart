import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LiteRtSttBackend identity', () {
    const b = LiteRtSttBackend();
    expect(b.name, 'LiteRT STT');
    expect(b.priority, 0);
  });

  test(
    'LiteRtSttBackend.canHandle is unconditionally true (sole STT backend)',
    () {
      const b = LiteRtSttBackend();
      for (final type in SttModelType.values) {
        final spec = SttModelSpec(
          name: 'test-$type',
          modelSource: NetworkSource('https://example.com/model.tflite'),
          tokenizerSource: NetworkSource('https://example.com/tokenizer.json'),
          sttModelType: type,
        );
        expect(b.canHandle(spec), isTrue, reason: 'must handle $type');
      }
    },
  );

  test(
    'createModel reads spec.sttModelType (does not hardcode moonshine)',
    () async {
      const b = LiteRtSttBackend();
      for (final type in SttModelType.values) {
        final spec = SttModelSpec(
          name: 'test-$type',
          modelSource: NetworkSource('https://example.com/model.tflite'),
          tokenizerSource: NetworkSource('https://example.com/tokenizer.json'),
          sttModelType: type,
        );
        const config = RuntimeConfig(
          maxTokens: 0,
          modelPath: '/tmp/model.tflite',
          tokenizerPath: '/tmp/tokenizer.json',
        );

        // The pipeline (SttModelProfile/LiteRtSpeechRecognizer) isn't wired
        // until the next task; the skeleton surfaces the selected type in the
        // thrown error, proving the backend reads it off the spec.
        await expectLater(
          () => b.createModel(spec, config),
          throwsA(
            isA<UnimplementedError>().having(
              (e) => e.message,
              'message',
              contains(type.toString()),
            ),
          ),
        );
      }
    },
  );

  test('createModel requires config.tokenizerPath', () async {
    const b = LiteRtSttBackend();
    final spec = SttModelSpec(
      name: 'test',
      modelSource: NetworkSource('https://example.com/model.tflite'),
      tokenizerSource: NetworkSource('https://example.com/tokenizer.json'),
      sttModelType: SttModelType.moonshine,
    );
    const config = RuntimeConfig(maxTokens: 0, modelPath: '/tmp/model.tflite');

    await expectLater(
      () => b.createModel(spec, config),
      throwsA(isA<StateError>()),
    );
  });
}
