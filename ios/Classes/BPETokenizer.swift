import Foundation

/// SentencePiece BPE tokenizer that loads tokenizer.json (HuggingFace format).
/// Uses greedy pair-merge algorithm with priority queue — matches SentencePiece C++ bpe_model.cc.
/// Replaces UnigramTokenizer which incorrectly used Viterbi on BPE vocab.
class BPETokenizer: TokenizerProtocol {

    // MARK: - Vocab

    private var pieces: [String] = []
    private var scores: [Float] = []
    private var pieceToId: [String: Int] = [:]

    // Special token IDs
    private var unkId: Int = 3
    private let padId = 0
    private let eosId = 1
    private let bosId = 2

    // MARK: - Linked list symbol for BPE merging

    private struct Symbol {
        var piece: String
        var prev: Int       // -1 = none
        var next: Int       // -1 = none
    }

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
        pieceToId.reserveCapacity(vocabSize)

        for (index, entry) in vocab.enumerated() {
            guard entry.count >= 2,
                  let piece = entry[0] as? String,
                  let scoreNum = entry[1] as? Double else {
                throw TokenizerError.invalidFormat("Invalid vocab entry at index \(index)")
            }

            let score = Float(scoreNum)
            pieces.append(piece)
            scores.append(score)

            if piece == "<unk>" {
                unkId = index
            }

            // Index mergeable tokens: score < 0 (normal) or -0.0 (highest priority merge)
            // Score +0.0 tokens are control/byte tokens that don't participate in merges
            // IEEE 754: Float(-0.0).sign == .minus, Float(+0.0).sign == .plus
            if score.sign == .minus {
                pieceToId[piece] = index
            }
        }
    }

    // MARK: - TokenizerProtocol

    func encode(_ text: String) -> [Int] {
        if text.isEmpty { return [] }
        let normalized = normalize(text)
        return bpeEncode(normalized)
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

    /// escape_whitespaces=True: replace " " → "▁"
    /// add_dummy_prefix=False: no prepend
    private func normalize(_ text: String) -> String {
        return text.replacingOccurrences(of: " ", with: "▁")
    }

    // MARK: - BPE Encode

    /// SentencePiece BPE algorithm (bpe_model.cc):
    /// 1. Split into Unicode characters → linked list of symbols
    /// 2. For each adjacent pair, compute merge rank from vocab scores
    /// 3. Greedily merge the best pair (lowest rank), update neighbors
    /// 4. Repeat until no more merges possible
    /// 5. Map remaining symbols to token IDs
    private func bpeEncode(_ text: String) -> [Int] {
        // 1. Split into Unicode characters
        let chars = Array(text).map { String($0) }
        if chars.isEmpty { return [] }
        if chars.count == 1 {
            return [lookupId(chars[0])]
        }

        // 2. Build linked list of symbols
        var symbols = [Symbol]()
        symbols.reserveCapacity(chars.count)
        for (i, ch) in chars.enumerated() {
            symbols.append(Symbol(
                piece: ch,
                prev: i - 1,
                next: i + 1 < chars.count ? i + 1 : -1
            ))
        }

        // 3. Build initial agenda of merge candidates
        // Each entry: (mergeRank, leftIndex, rightIndex)
        var agenda: [(rank: Float, left: Int, right: Int)] = []
        for i in 0..<(symbols.count - 1) {
            if let rank = getMergeRank(symbols[i].piece, symbols[i + 1].piece) {
                agenda.append((rank, i, i + 1))
            }
        }
        agenda.sort { $0.rank < $1.rank }

        // 4. Greedy merge loop
        while !agenda.isEmpty {
            let best = agenda.removeFirst()

            // Validate: symbols must still be active and adjacent
            guard symbols[best.left].next == best.right,
                  symbols[best.right].prev == best.left else {
                continue
            }

            // Validate: merged piece still exists in vocab
            let mergedPiece = symbols[best.left].piece + symbols[best.right].piece
            guard pieceToId[mergedPiece] != nil else {
                continue
            }

            // Merge: extend left symbol, remove right symbol from linked list
            symbols[best.left].piece = mergedPiece
            symbols[best.left].next = symbols[best.right].next
            if symbols[best.right].next != -1 {
                symbols[symbols[best.right].next].prev = best.left
            }
            // Mark right as inactive
            symbols[best.right].prev = -1
            symbols[best.right].next = -1
            symbols[best.right].piece = ""

            // Add new merge candidates for updated neighbors
            let leftIdx = best.left

            // Check merge with previous symbol
            if symbols[leftIdx].prev != -1 {
                let prevIdx = symbols[leftIdx].prev
                if let rank = getMergeRank(symbols[prevIdx].piece, symbols[leftIdx].piece) {
                    insertSorted(&agenda, entry: (rank, prevIdx, leftIdx))
                }
            }

            // Check merge with next symbol
            if symbols[leftIdx].next != -1 {
                let nextIdx = symbols[leftIdx].next
                if let rank = getMergeRank(symbols[leftIdx].piece, symbols[nextIdx].piece) {
                    insertSorted(&agenda, entry: (rank, leftIdx, nextIdx))
                }
            }
        }

        // 5. Collect remaining symbols as token IDs
        var tokenIds: [Int] = []
        var idx = 0
        // Find first active symbol
        while idx < symbols.count && symbols[idx].piece.isEmpty {
            idx += 1
        }
        while idx != -1 && idx < symbols.count {
            if !symbols[idx].piece.isEmpty {
                tokenIds.append(lookupId(symbols[idx].piece))
            }
            idx = symbols[idx].next
            if idx == -1 { break }
        }

        return tokenIds
    }

    // MARK: - Helpers

    /// Get merge rank for a pair of pieces.
    /// In SentencePiece BPE, score is negative and rank = -score (lower rank = higher priority).
    private func getMergeRank(_ left: String, _ right: String) -> Float? {
        let merged = left + right
        guard let id = pieceToId[merged] else { return nil }
        return -scores[id]  // score < 0, so -score > 0; lower rank = merge first
    }

    /// Lookup token ID for a piece, falling back to unk for unknown pieces.
    private func lookupId(_ piece: String) -> Int {
        if let id = pieceToId[piece] {
            return id
        }
        // Check all pieces including score==0 tokens (byte fallbacks, etc.)
        for (i, p) in pieces.enumerated() {
            if p == piece { return i }
        }
        return unkId
    }

    /// Insert entry into sorted agenda maintaining sort order by rank.
    private func insertSorted(_ agenda: inout [(rank: Float, left: Int, right: Int)],
                               entry: (rank: Float, left: Int, right: Int)) {
        var lo = 0, hi = agenda.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if agenda[mid].rank < entry.rank {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        agenda.insert(entry, at: lo)
    }
}

// MARK: - Error

enum TokenizerError: Error, LocalizedError {
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Tokenizer error: \(message)"
        }
    }
}
