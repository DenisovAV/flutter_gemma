import Foundation

/// Production-ready SentencePiece tokenizer using native C++ library
/// Provides proper BPE/Unigram tokenization matching the model training
class SentencePieceTokenizer {

    // MARK: - Properties

    /// Native SentencePiece processor wrapper
    private let wrapper = SentencePieceWrapper()

    /// Unknown token ID
    private var unkTokenId: Int = 0

    /// BOS (beginning of sequence) token ID
    private var bosTokenId: Int = 2

    /// EOS (end of sequence) token ID
    private var eosTokenId: Int = 1

    // MARK: - Initialization

    /// Initialize tokenizer from SentencePiece .model file
    /// - Parameter modelPath: Path to sentencepiece.model file
    init(modelPath: String) throws {
        try wrapper.loadModel(modelPath)

        // Get special token IDs from the model
        unkTokenId = wrapper.unkId()
        bosTokenId = wrapper.bosId()
        eosTokenId = wrapper.eosId()
    }

    // MARK: - Public Methods

    /// Encode text to token IDs using native SentencePiece
    /// - Parameter text: Input text to tokenize
    /// - Returns: Array of token IDs
    func encode(_ text: String) -> [Int] {
        if text.isEmpty {
            return []
        }

        let ids = wrapper.encode(text)
        return ids.map { $0.intValue }
    }

    /// Decode token IDs back to text
    /// - Parameter tokens: Array of token IDs
    /// - Returns: Decoded text
    func decode(_ tokens: [Int]) -> String {
        if tokens.isEmpty {
            return ""
        }

        let nsNumbers = tokens.map { NSNumber(value: $0) }
        return wrapper.decode(nsNumbers)
    }

    /// Get unknown token ID
    func getUnkTokenId() -> Int {
        return unkTokenId
    }

    /// Get BOS token ID
    func getBosTokenId() -> Int {
        return bosTokenId
    }

    /// Get EOS token ID
    func getEosTokenId() -> Int {
        return eosTokenId
    }

    /// Convert piece string to token ID
    func pieceToId(_ piece: String) -> Int {
        return wrapper.piece(toId: piece)
    }

    /// Convert token ID to piece string
    func idToPiece(_ id: Int) -> String {
        return wrapper.id(toPiece: id)
    }
}
