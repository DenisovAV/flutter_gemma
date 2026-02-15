import 'dart:math' show sqrt;
import 'package:local_hnsw/local_hnsw.dart';
import 'package:local_hnsw/local_hnsw.item.dart';

/// HNSW index wrapper for fast vector similarity search
///
/// **Purpose:**
/// Provides O(log n) approximate nearest neighbor search instead of
/// O(n) brute-force scan. Used as a cache layer on top of SQLite storage.
///
/// **Architecture:**
/// ```
/// SQLite (source of truth) ← persistence
/// HNSW Index (cache) ← fast search
/// ```
///
/// **Key Design Decisions:**
/// - In-memory index: Rebuilt on initialize() from SQLite data
/// - ID mapping: HNSW uses integer labels, we map to string document IDs
/// - Cosine metric: Matches SQLite brute-force implementation
/// - Over-fetch + rerank: Search 2x candidates, recalculate exact similarity
///
/// **Thread Safety:**
/// - Not thread-safe: Designed for single-isolate use
/// - Synchronization handled at repository level
class HnswVectorIndex {
  /// Vector dimension (set on first add or rebuild)
  int? _dimension;

  /// HNSW index instance
  LocalHNSW<String>? _index;

  /// Document embeddings cache for exact similarity recalculation
  /// Key: document ID, Value: embedding vector
  final Map<String, List<double>> _embeddings = {};

  /// Get current dimension (null if empty)
  int? get dimension => _dimension;

  /// Get document count
  int get count => _embeddings.length;

  /// Check if index is empty
  bool get isEmpty => _embeddings.isEmpty;

  /// Add document to HNSW index
  ///
  /// **First add sets dimension:**
  /// - Subsequent adds must match this dimension
  /// - Use [clear] to reset dimension
  ///
  /// **Duplicate handling:**
  /// - If ID exists, document is replaced (same as SQLite)
  ///
  /// Throws [ArgumentError] if dimension doesn't match existing
  void add(String id, List<double> embedding) {
    // Validate/set dimension
    if (_dimension == null) {
      _dimension = embedding.length;
      _index = LocalHNSW<String>(
        dim: _dimension!,
        metric: LocalHnswMetric.cosine,
      );
    } else if (embedding.length != _dimension) {
      throw ArgumentError(
        'Embedding dimension mismatch: expected $_dimension, got ${embedding.length}',
      );
    }

    // Remove existing if present (for updates)
    if (_embeddings.containsKey(id)) {
      _removeFromIndex(id);
    }

    // Add to HNSW index
    _index!.add(LocalHnswItem(
      item: id,
      vector: embedding,
    ));

    // Cache embedding for exact similarity recalculation
    _embeddings[id] = List.unmodifiable(embedding);
  }

  /// Search for similar documents
  ///
  /// **Over-fetch strategy:**
  /// - Fetches `topK * 2` candidates from HNSW (approximate)
  /// - Recalculates exact cosine similarity
  /// - Returns top `topK` results above threshold
  ///
  /// **Returns:**
  /// List of (id, similarity) pairs sorted by similarity descending
  ///
  /// **Empty index:**
  /// Returns empty list if no documents added
  List<HnswSearchResult> search(
    List<double> queryEmbedding,
    int topK, {
    double threshold = 0.0,
  }) {
    if (_index == null || _embeddings.isEmpty) {
      return [];
    }

    // Validate query dimension
    if (queryEmbedding.length != _dimension) {
      throw ArgumentError(
        'Query dimension mismatch: expected $_dimension, got ${queryEmbedding.length}',
      );
    }

    // Over-fetch candidates (HNSW returns approximate results)
    final candidateCount = (topK * 2).clamp(1, _embeddings.length);
    final searchResult = _index!.search(queryEmbedding, candidateCount);

    // Recalculate exact similarity and filter by threshold
    final results = <HnswSearchResult>[];
    for (final candidate in searchResult.items) {
      final id = candidate.item;
      final embedding = _embeddings[id];
      if (embedding == null) continue;

      final similarity = _cosineSimilarity(queryEmbedding, embedding);
      if (similarity >= threshold) {
        results.add(HnswSearchResult(id: id, similarity: similarity));
      }
    }

    // Sort by similarity descending and take topK
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    return results.take(topK).toList();
  }

  /// Rebuild index from document list
  ///
  /// **Use case:**
  /// Called during initialize() to restore HNSW from SQLite data
  ///
  /// **Clears existing data:**
  /// - Removes all current documents
  /// - Sets dimension from first document (if any)
  void rebuild(List<DocumentEmbedding> documents) {
    clear();

    if (documents.isEmpty) return;

    for (final doc in documents) {
      add(doc.id, doc.embedding);
    }
  }

  /// Clear all documents and reset dimension
  void clear() {
    _index = null;
    _dimension = null;
    _embeddings.clear();
  }

  /// Remove document by ID
  ///
  /// **Note:** local_hnsw doesn't support direct deletion by item,
  /// so we track embeddings separately and skip deleted items in search
  void remove(String id) {
    _removeFromIndex(id);
    _embeddings.remove(id);
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /// Remove item from HNSW index
  void _removeFromIndex(String id) {
    if (_index != null) {
      try {
        // delete() takes the item value directly, not LocalHnswItem
        _index!.delete(id);
      } catch (_) {
        // Ignore deletion errors (item may not exist in index)
      }
    }
  }

  /// Calculate cosine similarity between two vectors
  ///
  /// **Formula:**
  /// ```
  /// similarity = (A · B) / (||A|| * ||B||)
  /// ```
  ///
  /// **IDENTICAL to:**
  /// - Android: VectorStore.kt
  /// - iOS: VectorUtils.swift
  /// - Web: sqlite_vector_store.js
  /// - Parity tests: vector_store_parity_test.dart
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}

/// Document with embedding for HNSW rebuild
class DocumentEmbedding {
  final String id;
  final List<double> embedding;

  const DocumentEmbedding({
    required this.id,
    required this.embedding,
  });
}

/// HNSW search result
class HnswSearchResult {
  final String id;
  final double similarity;

  const HnswSearchResult({
    required this.id,
    required this.similarity,
  });
}
