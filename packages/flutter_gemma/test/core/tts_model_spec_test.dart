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

  test('every wired TtsModelType manifest (matcha, qwen3 — those whose '
      '.manifest does not throw) contains only plain basenames: a "/" would '
      'make MobileModelManager._restoreActiveTtsModel derive a different '
      'on-disk path than a fresh install did, silently breaking active-model '
      'restore after relaunch', () {
    for (final type in TtsModelType.values) {
      final List<String> manifest;
      try {
        manifest = type.manifest;
      } on UnimplementedError {
        continue; // Unwired family (kokoro/supertonic) — nothing to check.
      }
      for (final fn in manifest) {
        expect(
          fn.contains('/'),
          isFalse,
          reason: '$type manifest entry "$fn" must be a plain basename',
        );
      }
    }
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

  test('qwen3 manifest lists its 9 runtime files (plain basenames — no '
      'config.json, no tables/voices subdirectory in the manifest itself; '
      'see urlSuffixFor for the network-fetch mapping)', () {
    final m = TtsModelType.qwen3.manifest;
    expect(m, contains('talker_int4.tflite'));
    expect(m, contains('mtp_fp32.tflite'));
    expect(m, contains('codec_decoder_fp32.tflite'));
    expect(m, contains('tokenizer.json'));
    expect(m, contains('text_embedding_fp16.npy'));
    expect(m, contains('text_projection_fp32.npz'));
    expect(m, contains('codec_embedding_fp32.npy'));
    expect(m, contains('mtp_embeddings_fp16.npy'));
    expect(m, contains('demo_speaker.npy'));
    expect(m.length, 9);
    expect(m, isNot(contains('config.json')));
    for (final fn in m) {
      expect(fn.contains('/'), isFalse, reason: '$fn must be a plain basename');
    }
  });

  test(
    'qwen3 urlSuffixFor maps the 4 embedding tables + demo voice to their '
    'HF tables/voices subdirectory; the other 4 members map to themselves',
    () {
      expect(
        TtsModelType.qwen3.urlSuffixFor('text_embedding_fp16.npy'),
        'tables/text_embedding_fp16.npy',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('text_projection_fp32.npz'),
        'tables/text_projection_fp32.npz',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('codec_embedding_fp32.npy'),
        'tables/codec_embedding_fp32.npy',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('mtp_embeddings_fp16.npy'),
        'tables/mtp_embeddings_fp16.npy',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('demo_speaker.npy'),
        'voices/demo_speaker.npy',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('talker_int4.tflite'),
        'talker_int4.tflite',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('mtp_fp32.tflite'),
        'mtp_fp32.tflite',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('codec_decoder_fp32.tflite'),
        'codec_decoder_fp32.tflite',
      );
      expect(
        TtsModelType.qwen3.urlSuffixFor('tokenizer.json'),
        'tokenizer.json',
      );
    },
  );

  test('urlSuffixFor is the identity mapping for every other TtsModelType '
      '(matcha has no subdirectories)', () {
    for (final fn in TtsModelType.matcha.manifest) {
      expect(TtsModelType.matcha.urlSuffixFor(fn), fn);
    }
  });

  test('flat<->url round trip (I5): building a qwen3 spec with sourceFor '
      'wired through urlSuffixFor (as TtsInstallationBuilder does) produces '
      'TtsBundleFiles whose prefsKey set is EXACTLY the manifest — the '
      "tables/voices subdirectory in the fetch URL never leaks into the "
      'installed identity / artifactPaths key Qwen3TtsCore.load reads', () {
    final spec = TtsModelSpec.fromManifest(
      name: 'qwen3',
      ttsModelType: TtsModelType.qwen3,
      sourceFor: (fn) => ModelSource.network(
        'https://huggingface.co/litert-community/'
        'Qwen3-TTS-12Hz-0.6B-Base/resolve/main/'
        '${TtsModelType.qwen3.urlSuffixFor(fn)}',
      ),
    );
    final prefsKeys = spec.files.map((f) => f.prefsKey).toSet();
    expect(prefsKeys, TtsModelType.qwen3.manifest.toSet());
    expect(spec.files.length, 9);

    // The 4 table files + demo voice namespace to a flat qwen3__<basename>
    // filename — no embedded subdirectory made it through.
    final tablesFile = spec.files.firstWhere(
      (f) => f.prefsKey == 'text_embedding_fp16.npy',
    );
    expect(tablesFile.filename, 'qwen3__text_embedding_fp16.npy');
    final voiceFile = spec.files.firstWhere(
      (f) => f.prefsKey == 'demo_speaker.npy',
    );
    expect(voiceFile.filename, 'qwen3__demo_speaker.npy');
  });

  test('qwen3 minimumSizeBytes: .npy/.npz bundle members (incl. the small '
      'demo_speaker.npy voice) get the 1 KB floor; .tflite graphs keep the '
      'validator default (null)', () {
    final spec = TtsModelSpec.fromManifest(
      name: 'qwen3',
      ttsModelType: TtsModelType.qwen3,
      sourceFor: (fn) => ModelSource.network(
        'https://x/${TtsModelType.qwen3.urlSuffixFor(fn)}',
      ),
    );
    final byName = {for (final f in spec.files) f.prefsKey: f};

    expect(byName['text_embedding_fp16.npy']!.minimumSizeBytes, 1024);
    expect(byName['text_projection_fp32.npz']!.minimumSizeBytes, 1024);
    expect(byName['codec_embedding_fp32.npy']!.minimumSizeBytes, 1024);
    expect(byName['mtp_embeddings_fp16.npy']!.minimumSizeBytes, 1024);
    expect(byName['demo_speaker.npy']!.minimumSizeBytes, 1024);
    expect(byName['tokenizer.json']!.minimumSizeBytes, 1024);

    expect(byName['talker_int4.tflite']!.minimumSizeBytes, isNull);
    expect(byName['mtp_fp32.tflite']!.minimumSizeBytes, isNull);
    expect(byName['codec_decoder_fp32.tflite']!.minimumSizeBytes, isNull);
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

  test('qwen3 restore-safe: MobileModelManager._restoreActiveTtsModel derives '
      'namespaced paths DIRECTLY from the raw manifest string (no URL '
      'involved) — this must land on the SAME namespaced filename a fresh '
      'network install produces via urlSuffixFor, for every one of the 4 '
      'table + 1 voice member whose fetch URL has a tables/voices '
      'subdirectory the plain manifest entry does not', () {
    final installed = TtsModelSpec.fromManifest(
      name: 'qwen3',
      ttsModelType: TtsModelType.qwen3,
      sourceFor: (fn) => ModelSource.network(
        'https://x/${TtsModelType.qwen3.urlSuffixFor(fn)}',
      ),
    );
    for (final fn in TtsModelType.qwen3.manifest) {
      // Mirrors _restoreActiveTtsModel's `FileNameUtils.namespaced(modelId,
      // fn)` — computed from the raw manifest entry, independent of any URL.
      final restoreDerived = FileNameUtils.namespaced('qwen3', fn);
      final installDerived = installed.files
          .firstWhere((f) => f.prefsKey == fn)
          .filename;
      expect(
        restoreDerived,
        installDerived,
        reason:
            'restore would look for "$restoreDerived" but install wrote '
            '"$installDerived" — active TTS model restore would silently '
            'fail to find "$fn" after relaunch',
      );
    }
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
