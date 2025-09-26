import Foundation

/// iOS implementation of Universal Tokenizer - equivalent to Android DJL
/// Supports both HuggingFace (tokenizer.json) and SentencePiece (.model) formats
class HuggingFaceTokenizer {
    
    // MARK: - Types
    private enum TokenizerType {
        case huggingFace    // tokenizer.json format
        case sentencePiece  // sentencepiece.model format
    }
    
    // MARK: - Properties
    private var tokenizerType: TokenizerType = .huggingFace
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    private var merges: [(String, String)] = []
    private var addedTokens: [String: Int] = [:]
    private var unkToken: String = "<unk>"
    private var unkTokenId: Int = 0
    private var bosToken: String? = nil
    private var eosToken: String? = nil
    private var padToken: String? = nil
    
    // SentencePiece specific properties
    private var spVocab: [String] = []
    private var spScores: [Float] = []
    private var spTokenTypes: [Int] = []
    
    // MARK: - Initialization
    
    /// Initialize tokenizer from file (auto-detects format)
    /// - Parameter tokenizerPath: Path to tokenizer.json or sentencepiece.model file
    init(tokenizerPath: String) throws {
        // Auto-detect tokenizer type by file extension
        if tokenizerPath.hasSuffix(".json") {
            tokenizerType = .huggingFace
            try loadHuggingFaceTokenizer(from: tokenizerPath)
        } else if tokenizerPath.hasSuffix(".model") {
            tokenizerType = .sentencePiece
            try loadSentencePieceTokenizer(from: tokenizerPath)
        } else {
            // Fallback: try to detect by file content
            tokenizerType = .huggingFace
            try loadHuggingFaceTokenizer(from: tokenizerPath)
        }
    }
    
    // MARK: - Public Methods
    
    /// Encode text to token IDs (main method equivalent to DJL's encode)
    /// - Parameter text: Input text to tokenize
    /// - Returns: Array of token IDs
    func encode(_ text: String) -> [Int] {
        switch tokenizerType {
        case .huggingFace:
            return encodeHuggingFace(text)
        case .sentencePiece:
            return encodeSentencePiece(text)
        }
    }
    
    /// Encode using HuggingFace BPE method
    private func encodeHuggingFace(_ text: String) -> [Int] {
        // Apply normalization
        let normalizedText = normalize(text)
        
        // Pre-tokenization - split into words/subwords
        let words = preTokenize(normalizedText)
        
        // Apply BPE encoding to each word
        var allTokens: [Int] = []
        for word in words {
            let wordTokens = bpeEncode(word)
            allTokens.append(contentsOf: wordTokens)
        }
        
        return allTokens
    }
    
    /// Encode using SentencePiece method
    private func encodeSentencePiece(_ text: String) -> [Int] {
        // SentencePiece tokenization algorithm
        return sentencePieceEncode(text)
    }
    
    /// Decode token IDs back to text
    /// - Parameter tokens: Array of token IDs
    /// - Returns: Decoded text
    func decode(_ tokens: [Int]) -> String {
        let words = tokens.compactMap { reverseVocab[$0] }
        return words.joined().replacingOccurrences(of: "▁", with: " ").trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Private Methods - Tokenizer Loading
    
    /// Load HuggingFace tokenizer.json format
    private func loadHuggingFaceTokenizer(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        
        guard let json = json else {
            throw TokenizerError.invalidFormat("Invalid JSON format")
        }
        
        try parseModel(json)
        try parseAddedTokens(json)
        
        // Build reverse vocabulary
        for (token, id) in vocab {
            reverseVocab[id] = token
        }
        for (token, id) in addedTokens {
            reverseVocab[id] = token
        }
    }
    
    /// Load SentencePiece .model format
    private func loadSentencePieceTokenizer(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        
        // Parse SentencePiece protobuf format
        try parseSentencePieceModel(data)
        
        // Build reverse vocabulary for SentencePiece
        for (index, piece) in spVocab.enumerated() {
            vocab[piece] = index
            reverseVocab[index] = piece
        }
        
        // Set special tokens for SentencePiece
        unkTokenId = 0 // Usually first token in SentencePiece
        unkToken = spVocab.isEmpty ? "<unk>" : spVocab[0]
    }
    
    private func parseModel(_ json: [String: Any]) throws {
        guard let model = json["model"] as? [String: Any] else {
            throw TokenizerError.missingModel("Model section not found")
        }
        
        // Parse vocabulary
        if let vocabDict = model["vocab"] as? [String: Int] {
            self.vocab = vocabDict
        }
        
        // Parse BPE merges
        if let mergesList = model["merges"] as? [String] {
            self.merges = mergesList.compactMap { merge in
                let parts = merge.components(separatedBy: " ")
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            }
        }
        
        // Parse special tokens
        if let unkToken = model["unk_token"] as? String {
            self.unkToken = unkToken
            self.unkTokenId = vocab[unkToken] ?? 0
        }
    }
    
    private func parseAddedTokens(_ json: [String: Any]) throws {
        guard let addedTokensList = json["added_tokens"] as? [[String: Any]] else {
            return // Optional section
        }
        
        for tokenInfo in addedTokensList {
            guard let content = tokenInfo["content"] as? String,
                  let id = tokenInfo["id"] as? Int else { continue }
            
            addedTokens[content] = id
            
            // Identify special tokens
            if content.contains("<s>") || content.contains("[BOS]") {
                bosToken = content
            } else if content.contains("</s>") || content.contains("[EOS]") {
                eosToken = content
            } else if content.contains("[PAD]") {
                padToken = content
            }
        }
    }
    
    // MARK: - Text Normalization
    
    private func normalize(_ text: String) -> String {
        // Basic normalization - can be extended based on tokenizer config
        return text
            .precomposedStringWithCanonicalMapping // Unicode NFKC normalization
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Pre-tokenization
    
    private func preTokenize(_ text: String) -> [String] {
        // Split on whitespace and add SentencePiece prefix
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        return words.map { word in
            // Add SentencePiece prefix for first word
            if word == words.first {
                return "▁" + word
            } else {
                return "▁" + word
            }
        }
    }
    
    // MARK: - BPE Encoding
    
    private func bpeEncode(_ word: String) -> [Int] {
        // Handle added tokens first
        if let tokenId = addedTokens[word] {
            return [tokenId]
        }
        
        // Handle empty word
        if word.isEmpty {
            return []
        }
        
        // Start with individual characters as separate tokens
        var wordTokens = Array(word).map { String($0) }
        
        if wordTokens.count <= 1 {
            // Single character or empty - return its token ID
            let tokenStr = wordTokens.first ?? ""
            return [vocab[tokenStr] ?? unkTokenId]
        }
        
        // Apply BPE merges iteratively
        while true {
            let pairs = getPairsFromTokens(wordTokens)
            
            guard let bestMerge = findBestMergeFromTokens(pairs) else {
                break // No more merges possible
            }
            
            // Apply the merge
            wordTokens = applyMergeToTokens(wordTokens, merge: bestMerge)
        }
        
        // Convert final tokens to IDs
        return wordTokens.map { token in
            return vocab[token] ?? unkTokenId
        }
    }
    
    private func getPairsFromTokens(_ tokens: [String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        
        for i in 0..<(tokens.count - 1) {
            pairs.append((tokens[i], tokens[i + 1]))
        }
        
        return pairs
    }
    
    private func findBestMergeFromTokens(_ pairs: [(String, String)]) -> (String, String)? {
        var bestMerge: (String, String)? = nil
        var bestRank = Int.max
        
        for pair in pairs {
            // Find rank in merges list
            for (rank, merge) in merges.enumerated() {
                if merge.0 == pair.0 && merge.1 == pair.1 {
                    if rank < bestRank {
                        bestRank = rank
                        bestMerge = pair
                    }
                    break
                }
            }
        }
        
        return bestMerge
    }
    
    private func applyMergeToTokens(_ tokens: [String], merge: (String, String)) -> [String] {
        var newTokens: [String] = []
        var i = 0
        
        while i < tokens.count {
            if i < tokens.count - 1 && tokens[i] == merge.0 && tokens[i + 1] == merge.1 {
                // Apply merge - combine the two tokens
                let merged = merge.0 + merge.1
                newTokens.append(merged)
                i += 2 // Skip next token as it's been merged
            } else {
                newTokens.append(tokens[i])
                i += 1
            }
        }
        
        return newTokens
    }
    
    // MARK: - SentencePiece Implementation
    
    /// Parse SentencePiece protobuf model file
    private func parseSentencePieceModel(_ data: Data) throws {
        // Simple protobuf parser for SentencePiece .model files
        // SentencePiece stores vocabulary as protobuf with pieces, scores, and types
        
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
                    spVocab.append(piece.piece)
                    spScores.append(piece.score)
                    spTokenTypes.append(piece.type)
                }
            default:
                // Skip unknown fields
                offset = try skipProtobufField(data, offset: offset, wireType: wireType)
            }
        }
        
        print("[TOKENIZER] Loaded \(spVocab.count) SentencePiece tokens")
    }
    
    /// Simple SentencePiece encoding algorithm
    private func sentencePieceEncode(_ text: String) -> [Int] {
        var tokens: [Int] = []
        
        // Add BOS token if exists
        if let bosId = vocab["<s>"] {
            tokens.append(bosId)
        }
        
        // Simple greedy tokenization - find longest matching pieces
        var remaining = text
        
        while !remaining.isEmpty {
            var bestMatch = ""
            var bestId = unkTokenId
            
            // Find longest matching piece
            for (piece, id) in vocab {
                if remaining.hasPrefix(piece) && piece.count > bestMatch.count {
                    bestMatch = piece
                    bestId = id
                }
            }
            
            if bestMatch.isEmpty {
                // No match found - use first character as unknown
                tokens.append(unkTokenId)
                remaining = String(remaining.dropFirst())
            } else {
                tokens.append(bestId)
                remaining = String(remaining.dropFirst(bestMatch.count))
            }
        }
        
        // Add EOS token if exists
        if let eosId = vocab["</s>"] {
            tokens.append(eosId)
        }
        
        return tokens
    }
    
    // MARK: - Protobuf Utilities
    
    private func readProtobufField(_ data: Data, offset: Int) -> (fieldNumber: Int, wireType: Int, newOffset: Int)? {
        guard offset < data.count else { return nil }
        
        let byte = data[offset]
        let fieldNumber = Int(byte >> 3)
        let wireType = Int(byte & 0x07)
        
        return (fieldNumber, wireType, offset + 1)
    }
    
    private func readSentencePiecePiece(_ data: Data, offset: inout Int) throws -> (piece: String, score: Float, type: Int)? {
        // Read length-delimited message (wire type 2)
        guard let messageLength = readVarint(data, offset: &offset) else { return nil }
        
        let messageStart = offset
        let messageEnd = offset + Int(messageLength)
        
        var piece = ""
        var score: Float = 0.0
        var type = 0
        
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
            case 2: // score (float)
                if let scoreData = readFixed32(data, offset: &offset) {
                    score = Float(bitPattern: scoreData)
                }
            case 3: // type (int32)
                if let typeValue = readVarint(data, offset: &offset) {
                    type = Int(typeValue)
                }
            default:
                offset = try skipProtobufField(data, offset: offset, wireType: wireType)
            }
        }
        
        return (piece, score, type)
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
        
        // Read bytes individually to avoid alignment issues
        let byte0 = UInt32(data[offset])
        let byte1 = UInt32(data[offset + 1])
        let byte2 = UInt32(data[offset + 2])
        let byte3 = UInt32(data[offset + 3])
        
        // Combine bytes in little-endian format
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
    case missingModel(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid tokenizer format: \(message)"
        case .missingModel(let message):
            return "Missing model data: \(message)"
        case .fileNotFound(let message):
            return "Tokenizer file not found: \(message)"
        }
    }
}

// MARK: - Extensions for debugging

extension HuggingFaceTokenizer {
    
    /// Get vocabulary size
    var vocabularySize: Int {
        return vocab.count + addedTokens.count
    }
    
    /// Get token for ID (for debugging)
    func tokenForId(_ id: Int) -> String? {
        return reverseVocab[id]
    }
    
    /// Get ID for token (for debugging)
    func idForToken(_ token: String) -> Int? {
        return vocab[token] ?? addedTokens[token]
    }
}