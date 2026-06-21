import 'package:flutter_gemma/core/services/vector_store_filter.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart';

/// Abstract repository for vector store operations
///
/// Platform-specific implementations:
/// - Mobile: MobileVectorStoreRepository (via Pigeon → native SQLite)
/// - Web: WebVectorStoreRepository (SQLite WASM)
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

  /// Remove a document from the vector store by its ID.
  ///
  /// If the document does not exist, this is a no-op (does not throw).
  ///
  /// Throws [StateError] if not initialized.
  Future<void> removeDocument({required String id});

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
  /// - [filter]: Optional payload predicate. Honored by implementations that
  ///   support it (qdrant-edge, and sqlite-vec over declared [FilterSchema]
  ///   columns on both native and web). A condition on an undeclared/unsupported
  ///   field is treated as a no-op rather than an error, so passing a non-empty
  ///   filter to an implementation (or field) that ignores it returns the same
  ///   hits as `filter: null` — never throws.
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
    Filter? filter,
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

  /// Legacy no-op kept for source compatibility.
  ///
  /// Vector search now runs inside the store's engine (qdrant-edge, or
  /// sqlite-vec/`vec0`), so there is no Dart-side HNSW to toggle. Implementations
  /// accept the get/set but ignore it. Scheduled for removal in 2.0.
  bool get enableHnsw;
  set enableHnsw(bool value);

  /// The filterable-metadata schema this store was configured with.
  ///
  /// Concrete (bodied) member with a no-op default so that adding it does NOT
  /// force an override on existing or external `implements`-ers (this is an
  /// `abstract class`, not an `interface class`, so the body is inherited).
  /// Stores that honor [Filter] (qdrant, sqlite/vec0) override [configure] to
  /// stash the schema and expose it here; everyone else keeps the empty default.
  FilterSchema get filterSchema => const FilterSchema();

  /// Declare which metadata fields this store should make filterable.
  ///
  /// Called **once at registration, before [initialize]** — the schema is
  /// threaded from `FlutterGemma.initialize(filterSchema:)` through the service
  /// registry into the store's constructor wiring, so the store can promote the
  /// declared fields to typed storage columns (vec0) or top-level payload keys
  /// (qdrant) the first time it creates its table / writes a document.
  ///
  /// Default is a no-op: a store that does not override this keeps ignoring
  /// filters, and the never-throws contract on [searchSimilar] still holds — an
  /// empty or undeclared-key [Filter] returns the same hits as `filter: null`,
  /// it never throws.
  void configure(FilterSchema schema) {}
}

/// Exception thrown by VectorStore operations
class VectorStoreException implements Exception {
  final String message;
  final Object? cause;

  const VectorStoreException(this.message, [this.cause]);

  @override
  String toString() =>
      'VectorStoreException: $message${cause != null ? '\nCause: $cause' : ''}';
}
