/// Per-model runtime descriptor for the generic Matcha-CFM TTS pipeline.
///
/// This is what makes the TTS pipeline SELECTABLE without per-model classes:
/// `TtsCore` (Task 2.3) is generic over [TtsModelProfile] — matcha/kokoro/
/// supertonic are data (a profile + a catalog entry), not separate synthesizer
/// classes. Mirrors `SttModelProfile`. Unlike STT, the numeric synthesis
/// params (mel dims, CFM steps, sample rate, …) are NOT baked in here — Matcha
/// ships a `config.json` in its bundle and `TtsCore` reads them from there at
/// load time. This profile only carries the pipeline kind and the ROLE of
/// each bundle file (which `.tflite` is the encoder/decoder/vocoder/G2P, plus
/// the config/dict/embedding filenames).
library;

import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show TtsModelType;

/// Which end-to-end synthesis pipeline a TTS model family uses.
enum TtsPipelineKind {
  /// Matcha-TTS: text-encoder (mu + logw duration predictor) → host-side
  /// Glow-TTS length regulator (256→512 frames) → N-step Euler CFM decoder →
  /// HiFi-GAN vocoder. Numeric params come from the bundle's config.json.
  matchaCfm,
}

/// Runtime descriptor for one TTS model family — the pipeline kind plus the
/// role of each file in the model bundle. `TtsCore` needs this to know which
/// `.tflite` to load for which stage; it does not auto-detect roles from the
/// compiled models' tensor layouts.
class TtsModelProfile {
  /// Matcha-TTS bundle: filenames match `TtsModelType.matcha.manifest`
  /// (Task 1.3), here they get roles.
  const TtsModelProfile.matcha()
    : pipeline = TtsPipelineKind.matchaCfm,
      textEncoderFile = 'matcha_textenc_fp16.tflite',
      decoderFile = 'matcha_decoder_fp16.tflite',
      vocoderFile = 'matcha_vocoder_fp16.tflite',
      g2pFile = 'dp_g2p_matcha_fp16.tflite',
      configFile = 'config.json',
      dictFile = 'g2p_dict.txt.gz',
      embeddingFile = 'emb.bin';

  /// Which end-to-end synthesis pipeline this profile drives.
  final TtsPipelineKind pipeline;

  /// Text-encoder model file (mu + logw duration predictor).
  final String textEncoderFile;

  /// CFM decoder model file (N-step Euler ODE solver over mel frames).
  final String decoderFile;

  /// HiFi-GAN vocoder model file (mel → waveform).
  final String vocoderFile;

  /// Grapheme-to-phoneme model file.
  final String g2pFile;

  /// Bundle config file carrying the numeric synthesis params (read by
  /// `TtsCore`, not this profile).
  final String configFile;

  /// G2P dictionary file (gzipped).
  final String dictFile;

  /// Speaker/style embedding file.
  final String embeddingFile;

  /// Resolve the runtime profile for [t]. Only [TtsModelType.matcha] is
  /// wired; kokoro/supertonic are follow-ons and throw (fail-loud — never
  /// run text through the wrong pipeline).
  factory TtsModelProfile.forType(TtsModelType t) => switch (t) {
    TtsModelType.matcha => const TtsModelProfile.matcha(),
    _ => throw UnimplementedError(
      'TTS profile for $t is a follow-on (only matcha is wired)',
    ),
  };
}
