/// Per-model runtime descriptor for the generic LiteRT STT pipeline.
///
/// This is what makes the STT model SELECTABLE without per-model classes:
/// `LiteRtSpeechRecognizer`/`SttCore` are generic over [SttModelProfile] —
/// moonshine/whisper/parakeet are data (a profile + a catalog entry), not
/// separate recognizer classes. Mirrors how `InferenceModelSpec.modelType`
/// drives engine behavior via data rather than subclassing.
library;

import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show SttModelType;

/// How audio is fed to the model's encoder.
enum SttInputType {
  /// Raw PCM samples, normalized to `[-1, 1]` — no mel frontend (moonshine).
  rawPcm,

  /// Log-mel spectrogram frames — needs a Dart mel/DSP frontend (whisper,
  /// parakeet). Not implemented yet.
  logMel,
}

/// How the model turns encoder output into token ids.
enum SttDecodeType {
  /// Autoregressive encoder→decoder loop (moonshine, whisper).
  seq2seq,

  /// Single-pass greedy CTC over encoder output (parakeet). Not implemented
  /// yet.
  ctc,
}

/// Runtime descriptor for one STT model family — everything `SttCore` needs
/// to run a model that it does not auto-detect from the compiled model's
/// tensor layouts at load time.
class SttModelProfile {
  /// moonshine-tiny: raw PCM in, 5 s fixed window @ 16 kHz, seq2seq decode
  /// capped at 64 tokens. Values verified end-to-end in
  /// `docs/superpowers/notes/stt-transcript-recipe.md`.
  const SttModelProfile.moonshine()
    : inputType = SttInputType.rawPcm,
      sampleRate = 16000,
      windowSamples = 80000,
      decodeType = SttDecodeType.seq2seq,
      maxDecodeTokens = 64;

  /// How audio is fed to the encoder.
  final SttInputType inputType;

  /// Expected input sample rate, Hz.
  final int sampleRate;

  /// Fixed input window, in samples (moonshine: 80000 = 5 s @ 16 kHz).
  final int windowSamples;

  /// How token ids are produced from encoder output.
  final SttDecodeType decodeType;

  /// Max autoregressive decode steps before forcing a stop (moonshine: 64).
  final int maxDecodeTokens;

  /// Resolve the runtime profile for [t]. Only [SttModelType.moonshine] is
  /// implemented; whisper/parakeet need a log-mel frontend and are
  /// documented follow-ons (see the design spec's "Out of scope").
  factory SttModelProfile.forType(SttModelType t) => switch (t) {
    SttModelType.moonshine => const SttModelProfile.moonshine(),
    _ => throw UnimplementedError(
      'STT profile for $t is a follow-on (needs a log-mel frontend)',
    ),
  };
}
