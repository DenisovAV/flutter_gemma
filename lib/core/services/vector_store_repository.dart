import 'package:flutter_gemma/pigeon.g.dart';

/// Abstract repository for vector store operations
///
/// Platform-specific implementations:
/// - Mobile: MobileVectorStoreRepository (via Pigeon → native SQLite)
/// - Web: WebVectorStoreRepository (IndexedDB) - Phase 2
///
/// Design Principles:
/// - Repository pattern: Abstracts storage implementation
/// - Dependency Inversion: High-level code depends on abstraction
/// - Single Responsibility: Each method has one clear purpose
///
/// Thread Safety:
/// - Mobile: SQLite handles concurrency via ACID transactions
/// - Web: IndexedDB transactions provide isolation
abstract class VectorStoreRepository {
  /// Initialize vector store at given database path
  ///
  /// - Mobile: Creates/opens SQLite database file
  /// - Web: Opens IndexedDB database (path used as DB name)
  ///
  /// Must be called before any other operations.
  ///
  /// Throws [VectorStoreException] if initialization fails.
  Future<void> initialize(String databasePath);

  /// Add document with embedding to vector store
  ///
  /// **Auto-dimension detection**:
  /// - First document sets the dimension (e.g., 768D)
  /// - Subsequent documents must match that dimension
  ///
  /// **INSERT OR REPLACE behavior**:
  /// - If [id] exists, document is updated (replace)
  /// - If [id] is new, document is inserted
  ///
  /// Parameters:
  /// - [id]: Unique document identifier (PRIMARY KEY)
  /// - [content]: Document text content
  /// - [embedding]: Vector embedding (dimension auto-detected from first add)
  /// - [metadata]: Optional JSON string metadata
  ///
  /// Throws:
  /// - [StateError] if not initialized
  /// - [ArgumentError] if embedding dimension doesn't match existing documents
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  });

  /// Search for similar documents using cosine similarity
  ///
  /// Returns documents sorted by similarity (descending) where:
  /// - similarity >= [threshold]
  /// - Limited to top [topK] results
  ///
  /// **Cosine similarity formula**:
  /// ```
  /// similarity = (A · B) / (||A|| * ||B||)
  /// ```
  /// Where:
  /// - A · B = dot product
  /// - ||A|| = L2 norm of A
  ///
  /// Parameters:
  /// - [queryEmbedding]: Query vector (must match stored dimension)
  /// - [topK]: Maximum number of results to return
  /// - [threshold]: Minimum similarity score (0.0 to 1.0, default 0.0)
  ///
  /// Returns:
  /// - List of [RetrievalResult] sorted by similarity (highest first)
  ///
  /// Throws:
  /// - [StateError] if not initialized
  /// - [ArgumentError] if query dimension doesn't match stored dimension
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  });

  /// Get vector store statistics
  ///
  /// Returns:
  /// - [documentCount]: Total number of documents
  /// - [vectorDimension]: Embedding dimension (0 if empty)
  ///
  /// Throws [StateError] if not initialized
  Future<VectorStoreStats> getStats();

  /// Clear all documents from vector store
  ///
  /// **Side effects**:
  /// - Deletes all rows from documents table
  /// - Resets dimension (next add will auto-detect again)
  ///
  /// Throws [StateError] if not initialized
  Future<void> clear();

  /// Close vector store and release resources
  ///
  /// **Resource cleanup**:
  /// - Mobile: Closes SQLite database connection
  /// - Web: Closes IndexedDB connection
  ///
  /// Idempotent: Safe to call multiple times
  Future<void> close();

  /// Check if vector store is initialized
  ///
  /// Returns true if [initialize] was called successfully
  bool get isInitialized;
}

/// Exception thrown by VectorStore operations
class VectorStoreException implements Exception {
  final String message;
  final Object? cause;

  const VectorStoreException(this.message, [this.cause]);

  @override
  String toString() => 'VectorStoreException: $message${cause != null ? '\nCause: $cause' : ''}';
}
