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

import '../litert/log_mel_frontend.dart' show SttMelNormalization;
export '../litert/log_mel_frontend.dart' show SttMelNormalization;
import '../tokenizer/stt_special_tokens.dart';
import '../tokenizer/stt_tokenizer.dart' show SttTokenizerKind;

/// How audio is fed to the model's encoder.
enum SttInputType {
  /// Raw PCM samples, normalized to `[-1, 1]` — no mel frontend (moonshine).
  rawPcm,

  /// Log-mel spectrogram frames, computed by `log_mel_frontend.dart`
  /// (whisper, future parakeet).
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

/// Batch (whole-utterance) vs streaming (incremental) transcription.
///
/// A property of the exported artifact, NOT the algorithm family: parakeet's
/// `_stateful` CTC export streams, its stateless export does not — same
/// [SttDecodeType], different [SttModelProfile.modes]. (Design spec §5.)
enum SttMode { batch, streaming }

/// Row-major layout of a log-mel frontend's output. `melFirst` = `[nMels,
/// melFrames]` (whisper); a future `frameFirst` = `[melFrames, nMels]`
/// (parakeet's contract, per stt-model-contract.md) is not implemented yet.
enum SttMelAxisOrder { melFirst, frameFirst }

/// Which convention `decode_args_2`'s `[1,1,maxDecodeTokens,maxDecodeTokens]`
/// mask follows. `paddingOnly` is moonshine's verified convention C
/// (docs/superpowers/notes/stt-transcript-recipe.md): `0.0 if j<len else
/// -1e9` for every query row, no causal restriction. `causal` additionally
/// restricts `j<=r`. Whisper's value is set from
/// docs/superpowers/notes/whisper-stt-spike-findings.md (Phase 0) — do not
/// change without re-running that spike.
enum SttDecoderMaskConvention { paddingOnly, causal }

/// Logit suppression applied before argmax at every decode step (whisper).
/// `null` on a profile means no suppression (moonshine, unchanged).
class SttSuppressionSpec {
  const SttSuppressionSpec({
    required this.suppressAbove,
    this.suppressAtStepZero = const [],
  });

  /// Every token id strictly greater than this resolves-to id is forced to
  /// `-inf` at EVERY decode step (whisper: `<|endoftext|>` — the timestamp
  /// block and all non-text specials sit contiguously above it).
  final SttTokenRef suppressAbove;

  /// Additionally forced to `-inf`, but ONLY at decode step 0 (OpenAI
  /// whisper's "suppress_blank": a lone leading space/EOS can't be the
  /// very first generated token).
  final List<SttTokenRef> suppressAtStepZero;

  ResolvedSuppression resolve(SttSpecialTokenResolver resolver) =>
      ResolvedSuppression(
        suppressAboveId: suppressAbove.resolve(resolver),
        suppressAtStepZeroIds: {
          for (final ref in suppressAtStepZero) ref.resolve(resolver),
        },
      );
}

/// Runtime descriptor for one STT model family — everything `SttCore` needs
/// to run a model that it does not auto-detect from the compiled model's
/// tensor layouts at load time.
class SttModelProfile {
  /// moonshine-tiny: raw PCM in, 5 s fixed window @ 16 kHz, seq2seq decode
  /// capped at 64 tokens. Values verified end-to-end in
  /// `docs/superpowers/notes/stt-transcript-recipe.md`. BOS=1/EOS=2 are
  /// given as fixed ids (not names) — moonshine needs no tokenizer.json
  /// resolution, matching the original verified recipe exactly.
  const SttModelProfile.moonshine()
    : inputType = SttInputType.rawPcm,
      sampleRate = 16000,
      windowSamples = 80000,
      nMels = null,
      nFft = null,
      hopLength = null,
      melFrames = null,
      melAxisOrder = null,
      melNormalization = SttMelNormalization.none,
      melFilterAsset = null,
      winLength = null,
      preemphasis = null,
      decodeType = SttDecodeType.seq2seq,
      maxDecodeTokens = 64,
      modes = const {SttMode.batch},
      decoderPromptTokens = const [SttTokenRef.id(1)],
      eosToken = const SttTokenRef.id(2),
      suppressTokens = null,
      tokenizerKind = SttTokenizerKind.sentencePiece,
      decoderMaskConvention = SttDecoderMaskConvention.paddingOnly;

  /// whisper-tiny: log-mel in (30 s window), seq2seq decode capped at 128
  /// tokens, GPT-2 byte-level BPE vocab. Forced English-only prompt +
  /// suppression per docs/superpowers/specs/2026-07-31-whisper-stt-design.md.
  /// `decoderMaskConvention` is set from the Phase 0 spike finding
  /// (docs/superpowers/notes/whisper-stt-spike-findings.md) — `causal` is
  /// the verified winner (whisper's decoder is genuinely causal, unlike
  /// moonshine's export).
  const SttModelProfile.whisper()
    : inputType = SttInputType.logMel,
      sampleRate = 16000,
      windowSamples = 480000,
      nMels = 80,
      nFft = 400,
      hopLength = 160,
      melFrames = 3000,
      melAxisOrder = SttMelAxisOrder.melFirst,
      melNormalization = SttMelNormalization.whisper,
      melFilterAsset = 'whisper_mel_80',
      winLength = null,
      preemphasis = null,
      decodeType = SttDecodeType.seq2seq,
      maxDecodeTokens = 128,
      modes = const {SttMode.batch},
      decoderPromptTokens = const [
        SttTokenRef.name('<|startoftranscript|>'),
        SttTokenRef.name('<|en|>'),
        SttTokenRef.name('<|transcribe|>'),
        SttTokenRef.name('<|notimestamps|>'),
      ],
      eosToken = const SttTokenRef.name('<|endoftext|>'),
      suppressTokens = const SttSuppressionSpec(
        suppressAbove: SttTokenRef.name('<|endoftext|>'),
        suppressAtStepZero: [
          SttTokenRef.name('Ġ'),
          SttTokenRef.name('<|endoftext|>'),
        ],
      ),
      tokenizerKind = SttTokenizerKind.gpt2ByteLevelBpe,
      decoderMaskConvention = SttDecoderMaskConvention.causal;

  /// How audio is fed to the encoder.
  final SttInputType inputType;

  /// Expected input sample rate, Hz.
  final int sampleRate;

  /// Fixed input window, in samples (moonshine: 80000 = 5 s @ 16 kHz;
  /// whisper: 480000 = 30 s @ 16 kHz).
  final int windowSamples;

  /// Mel filterbank bin count (whisper: 80). `null` for `rawPcm` profiles.
  final int? nMels;

  /// STFT window size (whisper: 400). `null` for `rawPcm` profiles.
  final int? nFft;

  /// STFT hop length (whisper: 160). `null` for `rawPcm` profiles.
  final int? hopLength;

  /// Expected STFT frame count (whisper: 3000). `null` for `rawPcm` profiles.
  final int? melFrames;

  /// Log-mel output layout (whisper: melFirst). `null` for `rawPcm` profiles.
  final SttMelAxisOrder? melAxisOrder;

  /// Log-mel normalization scheme (whisper: whisper; moonshine: none/n-a).
  final SttMelNormalization melNormalization;

  /// Name of the bundled mel filterbank matrix to load (whisper:
  /// 'whisper_mel_80', see `mel_filter_assets.dart`). `null` for `rawPcm`.
  final String? melFilterAsset;

  /// STFT window length, when narrower than [nFft] (parakeet: 400, `nFft`
  /// 512 -- the Hann window is centered/zero-padded into the larger FFT
  /// buffer). `null` when `winLength == nFft` (whisper) or for `rawPcm`.
  final int? winLength;

  /// Pre-emphasis coefficient applied to raw PCM before framing (parakeet:
  /// 0.97, NeMo's default). `null` when the family applies none
  /// (moonshine, whisper).
  final double? preemphasis;

  /// How token ids are produced from encoder output.
  final SttDecodeType decodeType;

  /// Max autoregressive decode steps before forcing a stop (moonshine: 64;
  /// whisper: 128).
  final int maxDecodeTokens;

  /// Which transcription modes this model's exported artifact supports.
  /// moonshine/whisper: {batch}. Future parakeet stateful export: {batch,
  /// streaming}. Declarative capability data (design spec §5) — v1 has no
  /// consumer yet; the streaming gate lands with the streaming phase.
  final Set<SttMode> modes;

  /// Ordered decoder seed tokens (moonshine: single BOS id; whisper: the
  /// 4 forced-English-transcription tokens, resolved by name at load time).
  final List<SttTokenRef> decoderPromptTokens;

  /// Stop-decoding token (moonshine: fixed EOS id 2; whisper: resolved
  /// `<|endoftext|>`).
  final SttTokenRef eosToken;

  /// Logit suppression applied every decode step before argmax. `null` =
  /// none (moonshine, unchanged).
  final SttSuppressionSpec? suppressTokens;

  /// Which `SttTokenizer` implementation decodes this family's output ids.
  final SttTokenizerKind tokenizerKind;

  /// Which `decode_args_2` mask formula `SttCore._decodeLoop` uses.
  final SttDecoderMaskConvention decoderMaskConvention;

  /// True if this model can drive a streaming (incremental) transcription.
  bool get supportsStreaming => modes.contains(SttMode.streaming);

  /// Resolve the runtime profile for [t]. `parakeet` needs CTC decode and
  /// is a documented follow-on (see the design spec's "Out of scope").
  factory SttModelProfile.forType(SttModelType t) => switch (t) {
    SttModelType.moonshine => const SttModelProfile.moonshine(),
    SttModelType.whisper => const SttModelProfile.whisper(),
    SttModelType.parakeet => throw UnimplementedError(
      'STT profile for $t is a follow-on (needs CTC decode; see the design spec)',
    ),
  };
}
