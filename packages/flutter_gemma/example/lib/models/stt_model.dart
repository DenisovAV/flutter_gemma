import 'package:flutter_gemma/flutter_gemma.dart' show SttModelType;

/// Catalog of on-device speech-to-text models the example can install.
///
/// Mirrors `models/embedding_model.dart` / `models/model.dart` — the STT
/// model is SELECTABLE, not hardcoded: every entry carries the
/// [SttModelType] that tells the single generic `LiteRtSttBackend`
/// (`flutter_gemma_speech`) which runtime `SttModelProfile` to run. Adding a
/// new family later is a new catalog entry (+ a profile + a mel frontend for
/// the log-mel families), not a new screen or a new backend/recognizer class.
///
/// Only [moonshineTiny] has a shipped `SttModelProfile` (raw PCM, no mel
/// frontend — see `docs/superpowers/notes/stt-transcript-recipe.md`).
/// [whisperTiny] and [parakeetCtc] are listed for completeness but
/// [isSupported] is false: both need a log-mel frontend that hasn't landed
/// yet (a documented follow-on, out of scope for this plan).
enum SttModel {
  moonshineTiny(
    modelUrl:
        'https://huggingface.co/litert-community/moonshine-tiny/resolve/main/moonshine_tiny_5s_f32.tflite',
    tokenizerUrl:
        'https://huggingface.co/UsefulSensors/moonshine/resolve/main/ctranslate2/tiny/tokenizer.json',
    displayName: 'Moonshine Tiny',
    size: '109MB',
    sttModelType: SttModelType.moonshine,
    needsAuth: false,
    isSupported: true,
  ),

  whisperTiny(
    modelUrl:
        'https://huggingface.co/litert-community/whisper-tiny/resolve/main/whisper_tiny_30s_f32.tflite',
    tokenizerUrl:
        'https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json',
    displayName: 'Whisper Tiny',
    size: '151MB',
    sttModelType: SttModelType.whisper,
    needsAuth: false,
    isSupported: false,
    unsupportedReason: 'Needs a log-mel frontend (follow-on, not shipped yet)',
  ),

  parakeetCtc(
    modelUrl:
        'https://huggingface.co/litert-community/parakeet-ctc-0.6b/resolve/main/parakeet_ctc_0.6b_5s_f32.tflite',
    tokenizerUrl:
        'https://huggingface.co/nvidia/parakeet-ctc-0.6b/resolve/main/tokenizer.json',
    displayName: 'Parakeet CTC 0.6B',
    size: '2.35GB',
    sttModelType: SttModelType.parakeet,
    needsAuth: false,
    isSupported: false,
    unsupportedReason: 'Needs a log-mel frontend (follow-on, not shipped yet)',
  );

  /// STT model (`.tflite`) download URL.
  final String modelUrl;

  /// Tokenizer (`tokenizer.json`) download URL.
  final String tokenizerUrl;

  /// Display name shown in the selection UI.
  final String displayName;

  /// Model file size (e.g. "109MB"), for display only.
  final String size;

  /// Model family carried on the installed `SttModelSpec` — selects the
  /// runtime `SttModelProfile` in the generic `LiteRtSpeechRecognizer`.
  final SttModelType sttModelType;

  /// Whether downloading requires a HuggingFace access token.
  final bool needsAuth;

  /// Whether this catalog entry has a shipped `SttModelProfile`. Entries
  /// with `isSupported: false` need a log-mel frontend that hasn't landed
  /// (see [unsupportedReason]) — the selection screen must not let the user
  /// install them yet.
  final bool isSupported;

  /// Why [isSupported] is false; null when supported.
  final String? unsupportedReason;

  const SttModel({
    required this.modelUrl,
    required this.tokenizerUrl,
    required this.displayName,
    required this.size,
    required this.sttModelType,
    required this.needsAuth,
    this.isSupported = true,
    this.unsupportedReason,
  });
}
