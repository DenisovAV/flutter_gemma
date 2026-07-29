import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show TtsModelType;
import 'package:flutter_gemma_speech/src/model/tts_model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forType(matcha) gives the matcha CFM pipeline + file roles', () {
    final p = TtsModelProfile.forType(TtsModelType.matcha);
    expect(p.pipeline, TtsPipelineKind.matchaCfm);
    expect(p.textEncoderFile, 'matcha_textenc_fp16.tflite');
    expect(p.decoderFile, 'matcha_decoder_fp16.tflite');
    expect(p.vocoderFile, 'matcha_vocoder_fp16.tflite');
    expect(p.g2pFile, 'dp_g2p_matcha_fp16.tflite');
    expect(p.configFile, 'config.json');
    expect(p.dictFile, 'g2p_dict.txt.gz');
    expect(p.embeddingFile, 'emb.bin');
  });

  test('forType throws UnimplementedError for unwired families', () {
    for (final t in TtsModelType.values.where(
      (t) => t != TtsModelType.matcha,
    )) {
      expect(
        () => TtsModelProfile.forType(t),
        throwsA(isA<UnimplementedError>()),
      );
    }
  });
}
