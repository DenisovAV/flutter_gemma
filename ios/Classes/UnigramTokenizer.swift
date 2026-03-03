import Foundation

/// Pure Swift Unigram tokenizer that loads tokenizer.json (HuggingFace format).
/// Uses Viterbi algorithm — exact port of SentencePiece C++ unigram_model.cc:889-1020.
/// No C++ dependencies, no protobuf — avoids iOS heap corruption crash.
class UnigramTokenizer: TokenizerProtocol {

    // MARK: - Trie

    private final class TrieNode {
        var children: [UInt8: TrieNode] = [:]
        var vocabId: Int = -1
    }

    private let root = TrieNode()

    // MARK: - Vocab

    private var pieces: [String] = []
    private var scores: [Float] = []
    private var isUserDefined: [Bool] = []

    // MARK: - Computed at init

    private var unkId: Int = 3
    private var minScore: Float = 0.0
    private var maxScore: Float = 0.0
    private let unkPenalty: Float = 10.0

    // Special token IDs
    private let padId = 0
    private let eosId = 1
    private let bosId = 2

    // MARK: - Initialization

    init(jsonPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              let vocab = model["vocab"] as? [[Any]] else {
            throw TokenizerError.invalidFormat("Cannot parse tokenizer.json")
        }

        let vocabSize = vocab.count
        pieces.reserveCapacity(vocabSize)
        scores.reserveCapacity(vocabSize)
        isUserDefined = [Bool](repeating: false, count: vocabSize)

        var computedMinScore: Float = 0.0
        var computedMaxScore: Float = 0.0
        var hasNormal = false

        for (index, entry) in vocab.enumerated() {
            guard entry.count >= 2,
                  let piece = entry[0] as? String,
                  let scoreNum = entry[1] as? Double else {
                throw TokenizerError.invalidFormat("Invalid vocab entry at index \(index)")
            }

            let score = Float(scoreNum)
            pieces.append(piece)
            scores.append(score)

            // Classify token
            if piece == "<unk>" {
                unkId = index
                isUserDefined[index] = false
            } else if score == 0.0 {
                // score == 0.0 (includes -0.0 since IEEE 754 -0.0 == 0.0)
                let isControl = (piece.hasPrefix("<") && piece.hasSuffix(">")) ||
                                piece.hasPrefix("[")
                if isControl {
                    // Control/byte tokens — NOT in trie
                    isUserDefined[index] = false
                } else {
                    // User-defined: newlines, tabs, ▁▁, ▁t, etc.
                    isUserDefined[index] = true
                }
            } else {
                // score < 0: normal token
                isUserDefined[index] = false
            }

            // Add to trie only normal and user-defined tokens
            if score < 0 || isUserDefined[index] {
                addToTrie(piece: piece, vocabId: index)
            }

            // Track min/max among normal tokens (score < 0)
            if score < 0 {
                if !hasNormal {
                    computedMinScore = score
                    computedMaxScore = score
                    hasNormal = true
                } else {
                    if score < computedMinScore { computedMinScore = score }
                    if score > computedMaxScore { computedMaxScore = score }
                }
            }
        }

        minScore = computedMinScore
        maxScore = computedMaxScore
    }

    // MARK: - Trie insertion

    private func addToTrie(piece: String, vocabId: Int) {
        let utf8Bytes = Array(piece.utf8)
        var node = root
        for byte in utf8Bytes {
            if node.children[byte] == nil {
                node.children[byte] = TrieNode()
            }
            node = node.children[byte]!
        }
        node.vocabId = vocabId
    }

    // MARK: - TokenizerProtocol

    func encode(_ text: String) -> [Int] {
        if text.isEmpty { return [] }
        let normalized = normalize(text)
        return viterbi(normalized)
    }

    func decode(_ tokens: [Int]) -> String {
        let text = tokens.map { id -> String in
            guard id >= 0 && id < pieces.count else { return "" }
            return pieces[id]
        }.joined()
        return text.replacingOccurrences(of: "▁", with: " ")
                   .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    func getUnkTokenId() -> Int { unkId }
    func getBosTokenId() -> Int { bosId }
    func getEosTokenId() -> Int { eosId }

    // MARK: - Normalization

    /// Port of normalizer.cc:104-173
    /// Replace spaces with ▁, prepend ▁
    private func normalize(_ text: String) -> String {
        let replaced = text.replacingOccurrences(of: " ", with: "▁")
        return "▁" + replaced
    }

    // MARK: - Viterbi

    /// Exact port of unigram_model.cc:889-1020 (EncodeOptimized)
    private func viterbi(_ normalized: String) -> [Int] {
        let bytes = Array(normalized.utf8)
        let size = bytes.count
        if size == 0 { return [] }

        let unkScore = minScore - unkPenalty

        // best_path_ends_at[i] = best path ending at byte position i
        var bestPathId = [Int](repeating: -1, count: size + 1)
        var bestPathScore = [Float](repeating: 0, count: size + 1)
        var bestPathStartsAt = [Int](repeating: -1, count: size + 1)

        var startsAt = 0
        while startsAt < size {
            let bestScoreTillHere = bestPathScore[startsAt]
            var hasSingleNode = false

            // UTF-8 char length at current position
            let mblen = min(utf8CharLength(bytes[startsAt]), size - startsAt)

            // Trie traversal (port of darts.h traverse)
            var node = root
            var keyPos = startsAt
            while keyPos < size {
                guard let next = node.children[bytes[keyPos]] else {
                    break
                }
                node = next
                keyPos += 1

                if node.vocabId >= 0 {
                    let id = node.vocabId
                    let length = keyPos - startsAt
                    let score: Float
                    if isUserDefined[id] {
                        // USER_DEFINED bonus (C++ line 979-980)
                        score = Float(length) * maxScore - 0.1
                    } else {
                        score = scores[id]
                    }

                    let candidateScore = score + bestScoreTillHere

                    if bestPathStartsAt[keyPos] == -1 ||
                       candidateScore > bestPathScore[keyPos] {
                        bestPathScore[keyPos] = candidateScore
                        bestPathStartsAt[keyPos] = startsAt
                        bestPathId[keyPos] = id
                    }

                    if !hasSingleNode && length == mblen {
                        hasSingleNode = true
                    }
                }
            }

            // UNK handling (C++ lines 995-1004)
            if !hasSingleNode {
                let candidateScore = unkScore + bestScoreTillHere
                let targetPos = startsAt + mblen
                if bestPathStartsAt[targetPos] == -1 ||
                   candidateScore > bestPathScore[targetPos] {
                    bestPathScore[targetPos] = candidateScore
                    bestPathStartsAt[targetPos] = startsAt
                    bestPathId[targetPos] = unkId
                }
            }

            // Advance by one unicode character (C++ line 1007)
            startsAt += mblen
        }

        // Backtrack (C++ lines 1010-1018)
        var tokenIds: [Int] = []
        var endsAt = size
        while endsAt > 0 {
            tokenIds.append(bestPathId[endsAt])
            endsAt = bestPathStartsAt[endsAt]
        }
        tokenIds.reverse()

        return tokenIds
    }

    // MARK: - UTF-8 utilities

    /// Port of util.h:154-156 OneCharLen
    private func utf8CharLength(_ byte: UInt8) -> Int {
        let table: [Int] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 4]
        return table[Int(byte >> 4)]
    }
}

// MARK: - Error

// TokenizerError is defined in BPETokenizer.swift
