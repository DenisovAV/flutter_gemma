library;

import 'tts_text_normalizer.dart';
export 'tts_text_normalizer.dart';

/// English impl of [TtsTextNormalizer], PRESERVING punctuation as model
/// symbols. [symbols] is the model's symbol set (config.json `symbols`) — only
/// marks the model knows survive as SymbolToken; the rest are dropped as
/// non-speech (logged). Numbers/acronyms/markdown handled in Task 5.
class EnglishTextNormalizer implements TtsTextNormalizer {
  const EnglishTextNormalizer(this.symbols);
  final Set<String> symbols;

  @override
  List<NormToken> normalize(String text) {
    final out = <NormToken>[];
    final buf = StringBuffer();
    void flushWord() {
      if (buf.isNotEmpty) {
        out.add(WordToken(buf.toString().toLowerCase()));
        buf.clear();
      }
    }

    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
        buf.write(ch);
      } else if (ch == ' ' || RegExp(r'\s').hasMatch(ch)) {
        flushWord();
        if (out.isNotEmpty && out.last is! SymbolToken) {
          out.add(const SymbolToken(' '));
        }
      } else {
        flushWord();
        if (symbols.contains(ch)) out.add(SymbolToken(ch));
        // else: non-speech char (Task 5 handles numbers/markdown); drop here.
      }
    }
    flushWord();
    return out;
  }

  @override
  List<String> splitClauses(String text) {
    final parts = <String>[];
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(ch);
      if ('.!?,;:'.contains(ch)) {
        final s = buf.toString().trim();
        if (s.isNotEmpty) parts.add(s);
        buf.clear();
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }
}
