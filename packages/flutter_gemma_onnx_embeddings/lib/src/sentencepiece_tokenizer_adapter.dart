import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';

import 'tokenizer.dart';

/// [Tokenizer] adapter backed by [SentencePieceTokenizer].
///
/// Gemma embedding models use the Gemma BOS/EOS convention, so this adapter
/// adds the BOS token (id 2) at the start and EOS token (id 1) at the end —
/// matching the pattern used by the LiteRT embedding backend.
class SentencePieceTokenizerAdapter implements Tokenizer {
  /// Gemma special-token IDs. The library defaults differ (bosId=1, eosId=2),
  /// so we add them manually with [addBosToken]/[addEosToken] disabled and
  /// prepend/append ourselves.
  static const int _bosId = 2;
  static const int _eosId = 1;

  SentencePieceTokenizerAdapter._(this._inner);

  final SentencePieceTokenizer _inner;

  /// Load a SentencePiece tokenizer from [path] (`.model` or `.json`).
  static Future<SentencePieceTokenizerAdapter> fromPath(String path) async {
    final SentencePieceTokenizer inner;
    if (path.endsWith('.json')) {
      inner = await TokenizerJsonLoader.fromJsonFile(
        path,
        config: const SentencePieceConfig(),
      );
    } else {
      inner = await SentencePieceTokenizer.fromModelFile(
        path,
        config: const SentencePieceConfig(),
      );
    }
    return SentencePieceTokenizerAdapter._(inner);
  }

  @override
  List<int> encode(String text) {
    final encoding = _inner.encode(text);
    return [_bosId, ...encoding.ids, _eosId];
  }
}
