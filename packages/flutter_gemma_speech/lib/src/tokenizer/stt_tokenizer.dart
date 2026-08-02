// Whisper's decode is GPT-2 byte-level BPE; moonshine's is SentencePiece.
// Different ALGORITHMS, not different parameters -- so this is an
// interface with per-family implementations (SentencePieceTokenizer,
// Gpt2ByteLevelBpeTokenizer), selected once at SttCore.load() time by
// SttModelProfile.tokenizerKind, not branched on in the hot decode loop.
library;

abstract interface class SttTokenizer {
  /// Turn a generated id sequence into text. Implementations stop at their
  /// family's EOS id and skip special/added-vocab ids.
  String decode(List<int> ids);
}
