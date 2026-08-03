import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
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
    final byName = {for (final f in spec.files) f.prefsKey: f};

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

  test('filename is namespaced by ttsModelType; prefsKey stays the plain '
      'manifest name (flutter_gemma_speech TtsModelProfile contract)', () {
    final spec = TtsModelSpec.fromManifest(
      name: 'matcha',
      ttsModelType: TtsModelType.matcha,
      sourceFor: (fn) => ModelSource.network('https://x/$fn'),
    );
    final configFile = spec.files.firstWhere(
      (f) => f.prefsKey == 'config.json',
    );
    expect(configFile.filename, 'matcha__config.json');
    expect(configFile.prefsKey, 'config.json');
  });

  test('restore-safe: reconstructing from FileSource paths whose basenames are '
      'ALREADY namespaced (as MobileModelManager._restoreActiveTtsModel does '
      "on relaunch) must not re-namespace .filename, and must denamespace "
      ".prefsKey back to the plain manifest name", () {
    final spec = TtsModelSpec.fromManifest(
      name: 'matcha',
      ttsModelType: TtsModelType.matcha,
      sourceFor: (fn) =>
          FileSource('/docs/${FileNameUtils.namespaced('matcha', fn)}'),
    );
    final configFile = spec.files.firstWhere(
      (f) => f.prefsKey == 'config.json',
    );
    // No double-prefix (matcha__matcha__config.json).
    expect(configFile.filename, 'matcha__config.json');
    // prefsKey stays plain so flutter_gemma_speech's
    // paths[profile.configFile] lookup (keyed by 'config.json') still
    // resolves — this is the regression guard for the restore path.
    expect(configFile.prefsKey, 'config.json');
  });

  test('two different ttsModelTypes namespace the same generic basename '
      'distinctly (the latent config.json/emb.bin collision)', () {
    final matcha = TtsModelSpec.fromManifest(
      name: 'matcha',
      ttsModelType: TtsModelType.matcha,
      sourceFor: (fn) => ModelSource.network('https://x/$fn'),
    );
    final matchaConfig = matcha.files.firstWhere(
      (f) => f.prefsKey == 'config.json',
    );
    expect(matchaConfig.filename, 'matcha__config.json');
    // kokoro/supertonic throw from .manifest today (UnimplementedError) —
    // this asserts the NAMESPACING MECHANISM would disambiguate a
    // matching filename, using the modelId directly rather than
    // requiring a wired kokoro manifest.
    expect(
      FileNameUtils.namespaced(TtsModelType.kokoro.name, 'config.json'),
      isNot(equals(matchaConfig.filename)),
    );
  });
}
