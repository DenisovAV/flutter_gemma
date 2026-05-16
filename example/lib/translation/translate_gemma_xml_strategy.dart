import 'prompt_strategy.dart';

/// XML-tag prompt format used by the `barakplasma/...-android-task-quantized`
/// community conversion of TranslateGemma 4B IT (the `.litertlm` bundle this
/// example ships).
///
/// The Jinja `chat_template` baked into that `.litertlm` expects:
///
///     <src>en</src><dst>fr</dst><text>hello world</text>
///
/// Plain text without tags also works (the model attempts language auto-detect),
/// but explicit tags are more reliable, so the UI always emits them.
class TranslateGemmaXmlPromptStrategy extends TranslationPromptStrategy {
  const TranslateGemmaXmlPromptStrategy();

  @override
  String formatPrompt({
    required String src,
    required String dst,
    required String text,
  }) =>
      '<src>$src</src><dst>$dst</dst><text>$text</text>';

  /// Curated subset of the ~55 ISO 639-1 codes Google's source
  /// `google/translategemma-4b-it` model card claims to support. Neither the
  /// model card nor the community fork README enumerates the full list, so
  /// this is the high-confidence subset covering the languages explicitly
  /// shown in examples plus the top global languages by speaker count.
  /// Users who need a code that isn't in this map can type it as a custom
  /// override in the UI.
  @override
  Map<String, String> get supportedLanguages => const {
        'ar': 'Arabic',
        'bg': 'Bulgarian',
        'bn': 'Bengali',
        'cs': 'Czech',
        'da': 'Danish',
        'de': 'German',
        'el': 'Greek',
        'en': 'English',
        'es': 'Spanish',
        'et': 'Estonian',
        'fa': 'Persian',
        'fi': 'Finnish',
        'fr': 'French',
        'he': 'Hebrew',
        'hi': 'Hindi',
        'hr': 'Croatian',
        'hu': 'Hungarian',
        'id': 'Indonesian',
        'it': 'Italian',
        'ja': 'Japanese',
        'ko': 'Korean',
        'lt': 'Lithuanian',
        'lv': 'Latvian',
        'ms': 'Malay',
        'nl': 'Dutch',
        'no': 'Norwegian',
        'pl': 'Polish',
        'pt': 'Portuguese',
        'ro': 'Romanian',
        'ru': 'Russian',
        'sk': 'Slovak',
        'sl': 'Slovenian',
        'sr': 'Serbian',
        'sv': 'Swedish',
        'sw': 'Swahili',
        'ta': 'Tamil',
        'te': 'Telugu',
        'th': 'Thai',
        'tr': 'Turkish',
        'uk': 'Ukrainian',
        'ur': 'Urdu',
        'vi': 'Vietnamese',
        'zh': 'Chinese',
      };
}
