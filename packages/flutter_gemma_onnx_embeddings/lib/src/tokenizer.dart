/// Minimal injectable text tokenizer interface.
///
/// Production callers are expected to provide a concrete implementation backed
/// by a real tokenizer (e.g. `dart_sentencepiece_tokenizer`). The interface is
/// kept deliberately thin so that tests can inject a [Tokenizer] stub without
/// pulling in any native libraries.
abstract class Tokenizer {
  /// Encodes [text] into a sequence of token IDs.
  List<int> encode(String text);
}
