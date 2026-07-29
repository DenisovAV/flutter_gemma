import 'package:flutter_gemma/flutter_gemma.dart' show TtsModelType;

/// Catalog of on-device TTS models. SELECTABLE like STT — each entry carries
/// the [TtsModelType] that tells the generic `LiteRtTtsBackend` which
/// `TtsModelProfile` to run. Install uses one base URL + `.ofType`.
/// Only [matcha] is wired; kokoro/supertonic are follow-ons (isSupported false).
enum TtsModel {
  matcha(
    baseUrl: 'https://huggingface.co/litert-community/Matcha-TTS/resolve/main/',
    displayName: 'Matcha-TTS',
    size: '~94MB',
    ttsModelType: TtsModelType.matcha,
    isSupported: true,
  ),
  kokoro(
    baseUrl: 'https://huggingface.co/litert-community/Kokoro-82M/resolve/main/',
    displayName: 'Kokoro 82M',
    size: '~415MB',
    ttsModelType: TtsModelType.kokoro,
    isSupported: false,
    unsupportedReason:
        'Needs its own TtsModelProfile (follow-on, not shipped yet)',
  ),
  supertonic(
    baseUrl: 'https://huggingface.co/soniqo/Supertonic-3-LiteRT/resolve/main/',
    displayName: 'Supertonic-3',
    size: '~378MB',
    ttsModelType: TtsModelType.supertonic,
    isSupported: false,
    unsupportedReason:
        'Needs its own TtsModelProfile (follow-on, not shipped yet)',
  );

  const TtsModel({
    required this.baseUrl,
    required this.displayName,
    required this.size,
    required this.ttsModelType,
    this.isSupported = true,
    this.unsupportedReason,
  });

  /// HuggingFace repo base URL each manifest filename is resolved against.
  final String baseUrl;

  /// Display name shown in the selection UI.
  final String displayName;

  /// Model bundle size (e.g. "~94MB"), for display only.
  final String size;

  /// Model family carried on the installed `TtsModelSpec` — selects the
  /// runtime `TtsModelProfile` in the generic `LiteRtTtsBackend`.
  final TtsModelType ttsModelType;

  /// Whether this catalog entry has a shipped `TtsModelProfile`. Entries
  /// with `isSupported: false` are listed for completeness but not wired.
  final bool isSupported;

  /// Why [isSupported] is false; null when supported.
  final String? unsupportedReason;
}
