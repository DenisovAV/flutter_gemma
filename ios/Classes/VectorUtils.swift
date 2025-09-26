import Foundation

/// Vector utilities for embedding similarity calculations
/// Equivalent to Android article's cosine similarity implementation
class VectorUtils {
    
    // MARK: - Cosine Similarity
    
    /// Calculate cosine similarity between two embedding vectors
    /// - Parameters:
    ///   - vectorA: First embedding vector
    ///   - vectorB: Second embedding vector
    /// - Returns: Cosine similarity score (-1.0 to 1.0)
    static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else {
            print("[VECTOR UTILS] Error: Vector dimensions don't match or vectors are empty")
            return 0.0
        }
        
        let dotProduct = dot(vectorA, vectorB)
        let magnitudeA = magnitude(vectorA)
        let magnitudeB = magnitude(vectorB)
        
        // Avoid division by zero
        guard magnitudeA > 0 && magnitudeB > 0 else {
            print("[VECTOR UTILS] Error: Vector magnitude is zero")
            return 0.0
        }
        
        let similarity = dotProduct / (magnitudeA * magnitudeB)
        return similarity
    }
    
    /// Calculate cosine similarity between Float arrays (for internal use)
    /// - Parameters:
    ///   - vectorA: First embedding vector
    ///   - vectorB: Second embedding vector
    /// - Returns: Cosine similarity score (-1.0 to 1.0)
    static func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Double {
        let doubleA = vectorA.map { Double($0) }
        let doubleB = vectorB.map { Double($0) }
        return cosineSimilarity(doubleA, doubleB)
    }
    
    // MARK: - Vector Operations
    
    /// Calculate dot product of two vectors
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    /// - Returns: Dot product value
    static func dot(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count else { return 0.0 }
        
        var sum: Double = 0.0
        for i in 0..<vectorA.count {
            sum += vectorA[i] * vectorB[i]
        }
        return sum
    }
    
    /// Calculate magnitude (L2 norm) of a vector
    /// - Parameter vector: Input vector
    /// - Returns: Vector magnitude
    static func magnitude(_ vector: [Double]) -> Double {
        let sumOfSquares = vector.reduce(0.0) { $0 + ($1 * $1) }
        return sqrt(sumOfSquares)
    }
    
    /// Normalize vector to unit length
    /// - Parameter vector: Input vector
    /// - Returns: Normalized vector
    static func normalize(_ vector: [Double]) -> [Double] {
        let mag = magnitude(vector)
        guard mag > 0 else { return vector }
        
        return vector.map { $0 / mag }
    }
    
    /// Normalize Float vector to unit length
    /// - Parameter vector: Input vector
    /// - Returns: Normalized vector
    static func normalize(_ vector: [Float]) -> [Float] {
        let doubleVector = vector.map { Double($0) }
        let normalizedDouble = normalize(doubleVector)
        return normalizedDouble.map { Float($0) }
    }
    
    // MARK: - Distance Metrics
    
    /// Calculate Euclidean distance between two vectors
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    /// - Returns: Euclidean distance
    static func euclideanDistance(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count else { return Double.infinity }
        
        var sumOfSquares: Double = 0.0
        for i in 0..<vectorA.count {
            let diff = vectorA[i] - vectorB[i]
            sumOfSquares += diff * diff
        }
        return sqrt(sumOfSquares)
    }
    
    /// Calculate Manhattan distance between two vectors
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    /// - Returns: Manhattan distance
    static func manhattanDistance(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count else { return Double.infinity }
        
        var sum: Double = 0.0
        for i in 0..<vectorA.count {
            sum += abs(vectorA[i] - vectorB[i])
        }
        return sum
    }
    
    // MARK: - Similarity Scoring
    
    /// Convert cosine similarity to a percentage score
    /// - Parameter similarity: Cosine similarity (-1.0 to 1.0)
    /// - Returns: Percentage score (0% to 100%)
    static func similarityToPercentage(_ similarity: Double) -> Double {
        // Convert from [-1, 1] to [0, 1] then to [0, 100]
        return ((similarity + 1.0) / 2.0) * 100.0
    }
    
    /// Check if similarity meets threshold
    /// - Parameters:
    ///   - similarity: Cosine similarity score
    ///   - threshold: Minimum threshold (typically 0.7-0.9 for good matches)
    /// - Returns: True if similarity meets threshold
    static func meetsThreshold(_ similarity: Double, threshold: Double) -> Bool {
        return similarity >= threshold
    }
    
    // MARK: - Batch Operations
    
    /// Find most similar vector from a collection
    /// - Parameters:
    ///   - queryVector: Query vector to compare against
    ///   - candidates: Collection of candidate vectors with their IDs
    /// - Returns: Most similar vector with its similarity score
    static func findMostSimilar(
        queryVector: [Double],
        candidates: [(id: String, vector: [Double])]
    ) -> (id: String, similarity: Double)? {
        var bestMatch: (id: String, similarity: Double)? = nil
        var maxSimilarity: Double = -1.0
        
        for candidate in candidates {
            let similarity = cosineSimilarity(queryVector, candidate.vector)
            if similarity > maxSimilarity {
                maxSimilarity = similarity
                bestMatch = (id: candidate.id, similarity: similarity)
            }
        }
        
        return bestMatch
    }
    
    /// Find top K most similar vectors
    /// - Parameters:
    ///   - queryVector: Query vector to compare against
    ///   - candidates: Collection of candidate vectors with their IDs
    ///   - topK: Number of top results to return
    ///   - threshold: Minimum similarity threshold
    /// - Returns: Array of top K matches sorted by similarity (descending)
    static func findTopSimilar(
        queryVector: [Double],
        candidates: [(id: String, vector: [Double])],
        topK: Int,
        threshold: Double = 0.0
    ) -> [(id: String, similarity: Double)] {
        var similarities: [(id: String, similarity: Double)] = []
        
        for candidate in candidates {
            let similarity = cosineSimilarity(queryVector, candidate.vector)
            if similarity >= threshold {
                similarities.append((id: candidate.id, similarity: similarity))
            }
        }
        
        // Sort by similarity (descending) and take top K
        similarities.sort { $0.similarity > $1.similarity }
        return Array(similarities.prefix(topK))
    }
    
    // MARK: - Debugging Utilities
    
    /// Print vector statistics for debugging
    /// - Parameters:
    ///   - vector: Vector to analyze
    ///   - name: Name for identification
    static func printVectorStats(_ vector: [Double], name: String = "Vector") {
        print("[VECTOR UTILS] \(name) Statistics:")
        print("[VECTOR UTILS] - Dimensions: \(vector.count)")
        print("[VECTOR UTILS] - Magnitude: \(magnitude(vector))")
        print("[VECTOR UTILS] - Min value: \(vector.min() ?? 0)")
        print("[VECTOR UTILS] - Max value: \(vector.max() ?? 0)")
        print("[VECTOR UTILS] - Mean value: \(vector.reduce(0, +) / Double(vector.count))")
        print("[VECTOR UTILS] - First 5 values: \(Array(vector.prefix(5)))")
    }
    
    /// Validate embedding vector format
    /// - Parameter vector: Vector to validate
    /// - Returns: True if vector is valid for embeddings
    static func isValidEmbedding(_ vector: [Double]) -> Bool {
        // Check basic requirements
        guard !vector.isEmpty else {
            print("[VECTOR UTILS] Invalid: Empty vector")
            return false
        }
        
        // Check for common embedding dimensions
        let commonDimensions = [128, 256, 384, 512, 768, 1024, 1536]
        if !commonDimensions.contains(vector.count) {
            print("[VECTOR UTILS] Warning: Unusual embedding dimension: \(vector.count)")
        }
        
        // Check for NaN or infinite values
        for (index, value) in vector.enumerated() {
            if value.isNaN {
                print("[VECTOR UTILS] Invalid: NaN value at index \(index)")
                return false
            }
            if value.isInfinite {
                print("[VECTOR UTILS] Invalid: Infinite value at index \(index)")
                return false
            }
        }
        
        return true
    }
}

// MARK: - Extensions

extension VectorUtils {
    
    /// Convenience method for similarity calculation with automatic validation
    /// - Parameters:
    ///   - vectorA: First embedding vector
    ///   - vectorB: Second embedding vector
    /// - Returns: Cosine similarity score or nil if vectors are invalid
    static func safeSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double? {
        guard isValidEmbedding(vectorA) && isValidEmbedding(vectorB) else {
            return nil
        }
        
        guard vectorA.count == vectorB.count else {
            print("[VECTOR UTILS] Error: Vector dimensions don't match (\(vectorA.count) vs \(vectorB.count))")
            return nil
        }
        
        return cosineSimilarity(vectorA, vectorB)
    }
    
    /// Test vector operations with sample data
    static func runTests() {
        print("[VECTOR UTILS] Running self-tests...")
        
        // Test vectors
        let vectorA = [1.0, 2.0, 3.0, 4.0]
        let vectorB = [2.0, 3.0, 4.0, 5.0]
        let vectorC = [1.0, 2.0, 3.0, 4.0] // Same as A
        
        // Test similarity
        let simAB = cosineSimilarity(vectorA, vectorB)
        let simAC = cosineSimilarity(vectorA, vectorC)
        
        print("[VECTOR UTILS] Similarity A-B: \(simAB)")
        print("[VECTOR UTILS] Similarity A-C (identical): \(simAC)")
        
        // Test normalization
        let normalized = normalize(vectorA)
        let normalizedMagnitude = magnitude(normalized)
        print("[VECTOR UTILS] Normalized magnitude: \(normalizedMagnitude)")
        
        // Test distance metrics
        let euclidean = euclideanDistance(vectorA, vectorB)
        let manhattan = manhattanDistance(vectorA, vectorB)
        print("[VECTOR UTILS] Euclidean distance: \(euclidean)")
        print("[VECTOR UTILS] Manhattan distance: \(manhattan)")
        
        print("[VECTOR UTILS] Tests completed!")
    }
}