/// Per-model runtime descriptor for the generic Matcha-CFM TTS pipeline.
///
/// This is what makes the TTS pipeline SELECTABLE without per-model classes:
/// `TtsCore` is generic over [TtsModelProfile] — matcha/kokoro/
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

  /// Qwen3-TTS: autoregressive codec-token LM (talker, prefill+decode over a
  /// threaded KV cache) → 15-step MTP residual-codebook inner loop →
  /// windowed codec decoder → 24 kHz PCM. Dispatched to `Qwen3TtsCore`
  /// (`flutter_gemma_speech/lib/src/qwen3/qwen3_tts_core.dart`) by the
  /// background worker — this pipeline kind never reaches the Matcha-only
  /// `TtsCore`/`TtsTextFrontend` path, which fail-loud on it instead of
  /// silently running Matcha behavior against a Qwen3 bundle.
  qwen3ArCodec,
}

/// How text becomes the model's encoder input.
enum TextRepresentation { phonemeSymbols, subwordTokens, rawChars }

/// For phonemeSymbols models only: how graphemes become phonemes.
enum G2pStrategy { dictionary, dictionaryPlusNeural, neuralOnly, none }

/// Runtime descriptor for one TTS model family — the pipeline kind plus the
/// role of each file in the model bundle. `TtsCore` needs this to know which
/// `.tflite` to load for which stage; it does not auto-detect roles from the
/// compiled models' tensor layouts.
class TtsModelProfile {
  /// Matcha-TTS bundle: filenames match `TtsModelType.matcha.manifest`;
  /// here they get roles.
  const TtsModelProfile.matcha()
    : pipeline = TtsPipelineKind.matchaCfm,
      textEncoderFile = 'matcha_textenc_fp16.tflite',
      decoderFile = 'matcha_decoder_fp16.tflite',
      vocoderFile = 'matcha_vocoder_fp16.tflite',
      g2pFile = 'dp_g2p_matcha_fp16.tflite',
      g2pMetaFile = 'g2p_meta.json',
      configFile = 'config.json',
      dictFile = 'g2p_dict.txt.gz',
      embeddingFile = 'emb.bin',
      representation = TextRepresentation.phonemeSymbols,
      g2p = G2pStrategy.dictionaryPlusNeural,
      locale = 'en_us';

  /// Qwen3-TTS bundle: unlike [matcha], `Qwen3TtsCore.load` does NOT read
  /// these file-role fields — it hardcodes its own manifest basenames
  /// (`talker_int4.tflite`, `mtp_fp32.tflite`, `codec_decoder_fp32.tflite`,
  /// `tokenizer.json`, plus the 4 `Qwen3Tables` npy/npz basenames; see
  /// `TtsModelTypeManifest.manifest` for `TtsModelType.qwen3` in
  /// `flutter_gemma`'s `model_specs.dart`). So for this profile [pipeline]
  /// is the ONLY load-bearing field; the file-role fields below are left
  /// `''` (non-nullable, so empty stands in for "not used") rather than
  /// mapped onto Qwen3 basenames — none of Matcha's roles (a single
  /// text-encoder/decoder/vocoder trio) has a clean 1:1 equivalent in the
  /// AR-codec pipeline's talker/MTP/codec-decoder split, and inventing one
  /// here would be misleading. Qwen3 does its own byte-level BPE
  /// tokenization (`Qwen2BpeEncoder` over `tokenizer.json`), not G2P.
  const TtsModelProfile.qwen3()
    : pipeline = TtsPipelineKind.qwen3ArCodec,
      textEncoderFile = '',
      decoderFile = '',
      vocoderFile = '',
      g2pFile = '',
      g2pMetaFile = '',
      configFile = '',
      dictFile = '',
      embeddingFile = '',
      representation = TextRepresentation.subwordTokens,
      g2p = G2pStrategy.none,
      locale = 'en_us';

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

  /// Neural G2P side-car: `char2idx`/`idx2ph` vocab + framing params
  /// (`char_repeats`/`start`/`end`/`MAXT`/`n_phonemes`) that `TtsCore` needs
  /// to run [g2pFile] and decode its output into IPA (`TtsCore.neuralG2p`).
  final String g2pMetaFile;

  /// Bundle config file carrying the numeric synthesis params (read by
  /// `TtsCore`, not this profile).
  final String configFile;

  /// G2P dictionary file (gzipped).
  final String dictFile;

  /// Speaker/style embedding file.
  final String embeddingFile;

  /// How text becomes the model's encoder input.
  final TextRepresentation representation;

  /// For phonemeSymbols models only: how graphemes become phonemes. Null for
  /// token models.
  final G2pStrategy? g2p;

  /// Selects the `TtsTextNormalizer`; matcha → `'en_us'`.
  final String locale;

  /// Resolve the runtime profile for [t]. Only [TtsModelType.matcha] and
  /// [TtsModelType.qwen3] are wired; kokoro/supertonic are follow-ons and
  /// throw (fail-loud — never run text through the wrong pipeline).
  factory TtsModelProfile.forType(TtsModelType t) => switch (t) {
    TtsModelType.matcha => const TtsModelProfile.matcha(),
    TtsModelType.qwen3 => const TtsModelProfile.qwen3(),
    _ => throw UnimplementedError(
      'TTS profile for $t is a follow-on (only matcha/qwen3 are wired)',
    ),
  };
}
