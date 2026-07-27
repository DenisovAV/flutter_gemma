import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matcha manifest lists its 8 runtime files', () {
    final m = TtsModelType.matcha.manifest;
    expect(m, contains('matcha_textenc_fp16.tflite'));
    expect(m, contains('matcha_decoder_fp16.tflite'));
    expect(m, contains('matcha_vocoder_fp16.tflite'));
    expect(m, contains('dp_g2p_matcha_fp16.tflite'));
    expect(m, contains('g2p_dict.txt.gz'));
    expect(m, contains('emb.bin'));
    expect(m, contains('config.json'));
    expect(m, contains('g2p_meta.json'));
    expect(m.length, 8);
  });

  test('unwired families throw UnimplementedError from manifest', () {
    expect(
      () => TtsModelType.kokoro.manifest,
      throwsA(isA<UnimplementedError>()),
    );
    expect(
      () => TtsModelType.supertonic.manifest,
      throwsA(isA<UnimplementedError>()),
    );
  });

  test(
    'fromManifest builds one source+file per manifest entry; type is tts',
    () {
      final spec = TtsModelSpec.fromManifest(
        name: 'matcha',
        ttsModelType: TtsModelType.matcha,
        sourceFor: (fn) => ModelSource.network('https://x/$fn'),
      );
      expect(spec.type, ModelManagementType.tts);
      expect(spec.sources.length, 8);
      expect(spec.files.length, 8);
      expect(spec.files.every((f) => f.isRequired), isTrue);
      expect(spec.ttsModelType, TtsModelType.matcha);
    },
  );

  test('minimumSizeBytes: small aux files get a 1 KB floor, .tflite graphs '
      'keep the validator default (null)', () {
    final spec = TtsModelSpec.fromManifest(
      name: 'matcha',
      ttsModelType: TtsModelType.matcha,
      sourceFor: (fn) => ModelSource.network('https://x/$fn'),
    );
    final byName = {for (final f in spec.files) f.filename: f};

    expect(byName['emb.bin']!.minimumSizeBytes, 1024);
    expect(byName['g2p_dict.txt.gz']!.minimumSizeBytes, 1024);
    expect(byName['config.json']!.minimumSizeBytes, 1024);
    expect(byName['g2p_meta.json']!.minimumSizeBytes, 1024);

    expect(byName['matcha_textenc_fp16.tflite']!.minimumSizeBytes, isNull);
    expect(byName['matcha_decoder_fp16.tflite']!.minimumSizeBytes, isNull);
    expect(byName['matcha_vocoder_fp16.tflite']!.minimumSizeBytes, isNull);
    expect(byName['dp_g2p_matcha_fp16.tflite']!.minimumSizeBytes, isNull);
  });

  test('value equality', () {
    ModelSource src(String fn) => ModelSource.network('https://x/$fn');
    final a = TtsModelSpec.fromManifest(
      name: 'm',
      ttsModelType: TtsModelType.matcha,
      sourceFor: src,
    );
    final b = TtsModelSpec.fromManifest(
      name: 'm',
      ttsModelType: TtsModelType.matcha,
      sourceFor: src,
    );
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });
}
