import Foundation
import SQLite3

/// iOS VectorStore implementation - equivalent to Android VectorStore.kt
/// Stores document embeddings in SQLite with binary BLOB format
class VectorStore {

    // MARK: - Properties

    private var db: OpaquePointer?
    private var dimension: Int?
    private var detectedDimension: Int?

    // Database schema
    private static let databaseVersion = 2
    private static let tableName = "documents"
    private static let columnId = "id"
    private static let columnContent = "content"
    private static let columnEmbedding = "embedding"
    private static let columnMetadata = "metadata"
    private static let columnCreatedAt = "created_at"

    // Common dimensions (informational only)
    static let DIM_GECKO_SMALL = 256
    static let DIM_MINI_LM = 384
    static let DIM_BERT_BASE = 768
    static let DIM_BERT_LARGE = 1024
    static let DIM_COHERE_V3 = 1024
    static let DIM_OPENAI_ADA = 1536
    static let DIM_OPENAI_LARGE = 3072
    static let DIM_QWEN_3 = 4096

    // MARK: - Initialization

    /// Initialize VectorStore with optional dimension
    /// - Parameter dimension: Expected embedding dimension (nil = auto-detect)
    init(dimension: Int? = nil) {
        self.dimension = dimension
    }

    /// Initialize database at specified path
    func initialize(databasePath: String) throws {
        // Close existing connection if any
        close()

        // Open SQLite database
        if sqlite3_open(databasePath, &db) != SQLITE_OK {
            throw VectorStoreError.databaseOpenFailed("Failed to open database at: \(databasePath)")
        }

        // Create table if not exists
        try createTable()
    }

    // MARK: - Public Methods

    /// Add document with embedding to vector store
    func addDocument(id: String, content: String, embedding: [Double], metadata: String?) throws {
        guard let db = db else {
            throw VectorStoreError.databaseNotInitialized
        }

        // Auto-detect dimension from first document
        if detectedDimension == nil {
            detectedDimension = dimension ?? embedding.count

            // Validate if dimension was specified
            if let expectedDim = dimension, expectedDim != embedding.count {
                throw VectorStoreError.dimensionMismatch(
                    expected: expectedDim,
                    actual: embedding.count
                )
            }
        }

        // Validate dimension consistency
        if embedding.count != detectedDimension {
            throw VectorStoreError.dimensionMismatch(
                expected: detectedDimension!,
                actual: embedding.count
            )
        }

        // Convert embedding to binary BLOB
        let embeddingBlob = embeddingToBlob(embedding)

        // Prepare INSERT statement
        let insertSQL = """
        INSERT OR REPLACE INTO \(Self.tableName)
        (\(Self.columnId), \(Self.columnContent), \(Self.columnEmbedding), \(Self.columnMetadata))
        VALUES (?, ?, ?, ?);
        """

        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (content as NSString).utf8String, -1, nil)

            // Bind BLOB
            embeddingBlob.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(embeddingBlob.count), nil)
            }

            if let metadata = metadata {
                sqlite3_bind_text(stmt, 4, (metadata as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_finalize(stmt)
                throw VectorStoreError.insertFailed("Failed to insert document")
            }
        } else {
            throw VectorStoreError.insertFailed("Failed to prepare insert statement")
        }

        sqlite3_finalize(stmt)
    }

    /// Search for similar documents using cosine similarity
    func searchSimilar(
        queryEmbedding: [Double],
        topK: Int,
        threshold: Double
    ) throws -> [RetrievalResult] {
        guard let db = db else {
            throw VectorStoreError.databaseNotInitialized
        }

        // Validate query embedding dimension
        if let detectedDim = detectedDimension, queryEmbedding.count != detectedDim {
            throw VectorStoreError.dimensionMismatch(
                expected: detectedDim,
                actual: queryEmbedding.count
            )
        }

        let querySQL = """
        SELECT \(Self.columnId), \(Self.columnContent), \(Self.columnEmbedding), \(Self.columnMetadata)
        FROM \(Self.tableName);
        """

        var stmt: OpaquePointer?
        var results: [(result: RetrievalResult, similarity: Double)] = []

        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                // Extract columns
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let content = String(cString: sqlite3_column_text(stmt, 1))

                // Extract BLOB
                if let embeddingBlob = sqlite3_column_blob(stmt, 2) {
                    let embeddingSize = sqlite3_column_bytes(stmt, 2)
                    let embeddingData = Data(bytes: embeddingBlob, count: Int(embeddingSize))
                    let docEmbedding = blobToEmbedding(embeddingData)

                    // Calculate similarity
                    let similarity = VectorUtils.cosineSimilarity(queryEmbedding, docEmbedding)

                    if similarity >= threshold {
                        var metadata: String? = nil
                        if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                            metadata = String(cString: sqlite3_column_text(stmt, 3))
                        }

                        let result = RetrievalResult(
                            id: id,
                            content: content,
                            similarity: similarity,
                            metadata: metadata
                        )
                        results.append((result: result, similarity: similarity))
                    }
                }
            }
        }

        sqlite3_finalize(stmt)

        // Sort by similarity (descending) and take top K
        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(topK)
            .map { $0.result }
    }

    /// Get vector store statistics
    func getStats() throws -> VectorStoreStats {
        guard let db = db else {
            throw VectorStoreError.databaseNotInitialized
        }

        let countSQL = "SELECT COUNT(*) FROM \(Self.tableName);"
        var stmt: OpaquePointer?
        var count: Int64 = 0

        if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int64(stmt, 0)
            }
        }

        sqlite3_finalize(stmt)

        return VectorStoreStats(
            documentCount: count,
            vectorDimension: Int64(detectedDimension ?? 0)
        )
    }

    /// Clear all documents from vector store
    func clear() throws {
        guard let db = db else {
            throw VectorStoreError.databaseNotInitialized
        }

        let deleteSQL = "DELETE FROM \(Self.tableName);"

        if sqlite3_exec(db, deleteSQL, nil, nil, nil) != SQLITE_OK {
            throw VectorStoreError.deleteFailed("Failed to clear vector store")
        }
    }

    /// Close database connection
    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Private Methods

    private func createTable() throws {
        guard let db = db else {
            throw VectorStoreError.databaseNotInitialized
        }

        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(Self.tableName) (
            \(Self.columnId) TEXT PRIMARY KEY,
            \(Self.columnContent) TEXT NOT NULL,
            \(Self.columnEmbedding) BLOB NOT NULL,
            \(Self.columnMetadata) TEXT,
            \(Self.columnCreatedAt) INTEGER DEFAULT (strftime('%s', 'now'))
        );
        CREATE INDEX IF NOT EXISTS idx_created_at ON \(Self.tableName)(\(Self.columnCreatedAt));
        """

        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            throw VectorStoreError.tableCreationFailed("Failed to create table")
        }
    }

    /// Convert embedding List<Double> to binary BLOB (float32)
    /// Format: Little-endian float32 array
    private func embeddingToBlob(_ embedding: [Double]) -> Data {
        var data = Data(count: embedding.count * 4)
        data.withUnsafeMutableBytes { ptr in
            let floatPtr = ptr.bindMemory(to: Float.self)
            for (i, value) in embedding.enumerated() {
                floatPtr[i] = Float(value)
            }
        }
        return data
    }

    /// Convert binary BLOB (float32) to embedding List<Double>
    private func blobToEmbedding(_ data: Data) -> [Double] {
        return data.withUnsafeBytes { ptr in
            let floatPtr = ptr.bindMemory(to: Float.self)
            return (0..<floatPtr.count).map { Double(floatPtr[$0]) }
        }
    }

    deinit {
        close()
    }
}

// MARK: - Error Types

enum VectorStoreError: Error, LocalizedError {
    case databaseNotInitialized
    case databaseOpenFailed(String)
    case tableCreationFailed(String)
    case insertFailed(String)
    case deleteFailed(String)
    case dimensionMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Database not initialized. Call initialize() first."
        case .databaseOpenFailed(let message):
            return "Failed to open database: \(message)"
        case .tableCreationFailed(let message):
            return "Failed to create table: \(message)"
        case .insertFailed(let message):
            return "Failed to insert document: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete: \(message)"
        case .dimensionMismatch(let expected, let actual):
            return "Embedding dimension mismatch: expected \(expected), got \(actual)"
        }
    }
}
