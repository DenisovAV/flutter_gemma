import Foundation

/// Production-ready SentencePiece tokenizer with BPE (Byte-Pair Encoding) algorithm
/// Implements greedy longest-match tokenization as used by Gemma models
class SentencePieceTokenizer {

    // MARK: - Properties

    /// Vocabulary: piece string -> token ID
    private var vocab: [String: Int] = [:]

    /// Reverse vocabulary: token ID -> piece string
    private var reverseVocab: [Int: String] = [:]

    /// Scores (log probabilities) for each piece
    private var scores: [Float] = []

    /// Pieces array (indexed by token ID)
    private var pieces: [String] = []

    /// Unknown token ID
    private var unkTokenId: Int = 0

    /// BOS (beginning of sequence) token ID
    private var bosTokenId: Int?

    /// EOS (end of sequence) token ID
    private var eosTokenId: Int?

    // MARK: - Initialization

    /// Initialize tokenizer from SentencePiece .model file
    /// - Parameter modelPath: Path to sentencepiece.model file
    init(modelPath: String) throws {
        let url = URL(fileURLWithPath: modelPath)
        let data = try Data(contentsOf: url)

        // Parse SentencePiece protobuf format
        try parseSentencePieceModel(data)

        // Build vocabulary mappings
        for (index, piece) in pieces.enumerated() {
            vocab[piece] = index
            reverseVocab[index] = piece
        }

        // Set special tokens
        unkTokenId = 0 // SentencePiece convention: first token is <unk>

        // Find BOS/EOS tokens
        if let bosId = vocab["<bos>"] {
            bosTokenId = bosId
        }
        if let eosId = vocab["<eos>"] {
            eosTokenId = eosId
        }

        print("[TOKENIZER] Loaded \(pieces.count) SentencePiece tokens (BPE)")
    }

    // MARK: - Public Methods

    /// Encode text to token IDs using greedy longest-match (BPE-style)
    /// - Parameter text: Input text to tokenize
    /// - Returns: Array of token IDs
    func encode(_ text: String) -> [Int] {
        if text.isEmpty {
            return []
        }

        // Convert to UTF-8 for proper byte handling
        let normalized = normalizeText(text)

        // Apply greedy longest-match algorithm (BPE-style)
        let tokens = greedyEncode(normalized)

        return tokens
    }

    /// Decode token IDs back to text
    /// - Parameter tokens: Array of token IDs
    /// - Returns: Decoded text
    func decode(_ tokens: [Int]) -> String {
        let pieces = tokens.compactMap { reverseVocab[$0] }
        let text = pieces.joined()

        // Remove SentencePiece space marker (▁) and replace with actual spaces
        return text.replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private Methods - Greedy Longest-Match Algorithm

    /// Greedy longest-match encoding (BPE-style)
    /// Used by Gemma SentencePiece models (not Unigram)
    /// NOTE: Does NOT add BOS/EOS - caller must add them once for entire sequence
    private func greedyEncode(_ text: String) -> [Int] {
        var tokens: [Int] = []
        var remaining = text

        while !remaining.isEmpty {
            var bestMatch = ""
            var bestId = unkTokenId

            // Find longest matching piece from vocabulary
            for (piece, id) in vocab {
                if remaining.hasPrefix(piece) && piece.count > bestMatch.count {
                    bestMatch = piece
                    bestId = id
                }
            }

            if bestMatch.isEmpty {
                // No match found - try single character as unknown
                print("[TOKENIZER WARNING] No match for: '\(remaining.prefix(10))'...")
                tokens.append(unkTokenId)
                remaining = String(remaining.dropFirst())
            } else {
                tokens.append(bestId)
                remaining = String(remaining.dropFirst(bestMatch.count))
            }
        }

        return tokens
    }

    /// Viterbi algorithm (DEPRECATED - not used by Gemma models)
    /// Keeping for reference only
    private func viterbiEncode_DEPRECATED(_ text: String) -> [Int] {
        let textArray = Array(text)
        let n = textArray.count

        guard n > 0 else { return [] }

        // Dynamic programming tables
        // bestScore[i] = best cumulative score to reach position i
        var bestScore: [Float] = Array(repeating: -Float.infinity, count: n + 1)
        bestScore[0] = 0.0

        // bestPrev[i] = previous position in best path to position i
        var bestPrev: [Int] = Array(repeating: -1, count: n + 1)

        // bestTokenId[i] = token ID used to reach position i
        var bestTokenId: [Int] = Array(repeating: unkTokenId, count: n + 1)

        // Forward pass - fill DP table
        for i in 1...n {
            // Try all possible token endings at position i
            for j in 0..<i {
                // Extract substring from j to i
                let substring = String(textArray[j..<i])

                // Check if this substring exists in vocabulary
                if let tokenId = vocab[substring] {
                    // Calculate score: previous best score + current token score
                    let score = bestScore[j] + scores[tokenId]

                    // Update if this path is better
                    if score > bestScore[i] {
                        bestScore[i] = score
                        bestPrev[i] = j
                        bestTokenId[i] = tokenId
                    }
                }
            }

            // If no valid token found for position i, use unknown token
            if bestScore[i] == -Float.infinity {
                // Fallback: single character as unknown
                bestScore[i] = bestScore[i - 1] + scores[unkTokenId]
                bestPrev[i] = i - 1
                bestTokenId[i] = unkTokenId
            }
        }

        // Backward pass - reconstruct optimal token sequence
        var tokens: [Int] = []
        var pos = n

        while pos > 0 {
            let prevPos = bestPrev[pos]
            let tokenId = bestTokenId[pos]

            tokens.append(tokenId)
            pos = prevPos
        }

        // Reverse to get correct order (we built backwards)
        return tokens.reversed()
    }

    /// Normalize text for tokenization
    /// SentencePiece adds ▁ (U+2581) as space marker ONLY before words after spaces
    /// NOTE: Do NOT add ▁ at the very beginning - that's handled by caller
    private func normalizeText(_ text: String) -> String {
        // SentencePiece preprocessing:
        // Replace spaces with ▁ (space marker)
        // Do NOT add leading ▁ - text at start of sequence has no space before it

        let normalized = text.replacingOccurrences(of: " ", with: "▁")

        return normalized
    }

    // MARK: - Private Methods - Protobuf Parsing

    /// Parse SentencePiece protobuf model file
    private func parseSentencePieceModel(_ data: Data) throws {
        var offset = 0

        while offset < data.count {
            // Read protobuf field header
            guard let (fieldNumber, wireType, newOffset) = readProtobufField(data, offset: offset) else {
                break
            }
            offset = newOffset

            switch fieldNumber {
            case 1: // pieces (repeated)
                if let piece = try readSentencePiecePiece(data, offset: &offset) {
                    pieces.append(piece.piece)
                    scores.append(piece.score)
                }
            default:
                // Skip unknown fields
                offset = try skipProtobufField(data, offset: offset, wireType: wireType)
            }
        }
    }

    private func readProtobufField(_ data: Data, offset: Int) -> (fieldNumber: Int, wireType: Int, newOffset: Int)? {
        guard offset < data.count else { return nil }

        let byte = data[offset]
        let fieldNumber = Int(byte >> 3)
        let wireType = Int(byte & 0x07)

        return (fieldNumber, wireType, offset + 1)
    }

    private func readSentencePiecePiece(_ data: Data, offset: inout Int) throws -> (piece: String, score: Float)? {
        // Read length-delimited message (wire type 2)
        guard let messageLength = readVarint(data, offset: &offset) else { return nil }

        let messageStart = offset
        let messageEnd = offset + Int(messageLength)

        var piece = ""
        var score: Float = 0.0
        var scoreRaw: UInt32 = 0

        offset = messageStart

        while offset < messageEnd {
            guard let (fieldNumber, wireType, newOffset) = readProtobufField(data, offset: offset) else {
                break
            }
            offset = newOffset

            switch fieldNumber {
            case 1: // piece (string)
                if let pieceData = readLengthDelimited(data, offset: &offset) {
                    piece = String(data: pieceData, encoding: .utf8) ?? ""
                }
            case 2: // score (float) - wire type should be 5 (fixed32)
                if wireType != 5 {
                    print("[TOKENIZER ERROR] Score field has wrong wire type: \(wireType), expected 5")
                }
                if let scoreData = readFixed32(data, offset: &offset) {
                    scoreRaw = scoreData
                    score = Float(bitPattern: scoreData)
                }
            case 3: // type (int32) - we skip this
                _ = readVarint(data, offset: &offset)
            default:
                break
            }
        }

        return (piece, score)
    }

    private func readVarint(_ data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift = 0

        while offset < data.count && shift < 64 {
            let byte = data[offset]
            offset += 1

            result |= UInt64(byte & 0x7F) << shift

            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
        }

        return nil
    }

    private func readLengthDelimited(_ data: Data, offset: inout Int) -> Data? {
        guard let length = readVarint(data, offset: &offset) else { return nil }

        let start = offset
        let end = offset + Int(length)

        guard end <= data.count else { return nil }

        offset = end
        return data.subdata(in: start..<end)
    }

    private func readFixed32(_ data: Data, offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }

        let byte0 = UInt32(data[offset])
        let byte1 = UInt32(data[offset + 1])
        let byte2 = UInt32(data[offset + 2])
        let byte3 = UInt32(data[offset + 3])

        let value = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)

        offset += 4
        return value
    }

    private func skipProtobufField(_ data: Data, offset: Int, wireType: Int) throws -> Int {
        switch wireType {
        case 0: // Varint
            var newOffset = offset
            _ = readVarint(data, offset: &newOffset)
            return newOffset
        case 1: // Fixed64
            return offset + 8
        case 2: // Length-delimited
            var newOffset = offset
            guard let length = readVarint(data, offset: &newOffset) else {
                throw TokenizerError.invalidFormat("Invalid protobuf length")
            }
            return newOffset + Int(length)
        case 5: // Fixed32
            return offset + 4
        default:
            throw TokenizerError.invalidFormat("Unknown protobuf wire type: \(wireType)")
        }
    }
}

// MARK: - Error Types

enum TokenizerError: Error, LocalizedError {
    case invalidFormat(String)
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid tokenizer format: \(message)"
        case .modelLoadFailed(let message):
            return "Model load failed: \(message)"
        }
    }
}
