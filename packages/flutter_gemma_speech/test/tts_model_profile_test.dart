import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show TtsModelType;
import 'package:flutter_gemma_speech/src/model/tts_model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forType(matcha) gives the matcha CFM pipeline + file roles', () {
    final p = TtsModelProfile.forType(TtsModelType.matcha);
    expect(p.pipeline, TtsPipelineKind.matchaCfm);
    expect(p, isA<MatchaProfile>());
    final m = p as MatchaProfile;
    expect(m.textEncoderFile, 'matcha_textenc_fp16.tflite');
    expect(m.decoderFile, 'matcha_decoder_fp16.tflite');
    expect(m.vocoderFile, 'matcha_vocoder_fp16.tflite');
    expect(m.g2pFile, 'dp_g2p_matcha_fp16.tflite');
    expect(m.configFile, 'config.json');
    expect(m.dictFile, 'g2p_dict.txt.gz');
    expect(m.embeddingFile, 'emb.bin');
  });

  test('forType throws UnimplementedError for unwired families', () {
    for (final t in TtsModelType.values.where(
      (t) =>
          t != TtsModelType.matcha &&
          t != TtsModelType.qwen3 &&
          t != TtsModelType.inflect,
    )) {
      expect(
        () => TtsModelProfile.forType(t),
        throwsA(isA<UnimplementedError>()),
      );
    }
  });

  test(
    'matcha profile declares phonemeSymbols + dictionaryPlusNeural + en_us',
    () {
      const p = TtsModelProfile.matcha();
      expect(p.representation, TextRepresentation.phonemeSymbols);
      expect(p.g2p, G2pStrategy.dictionaryPlusNeural);
      expect(p.locale, 'en_us');
    },
  );
}
