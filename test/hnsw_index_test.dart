import 'dart:math' show sqrt;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/infrastructure/hnsw_vector_index.dart';

/// Unit tests for HnswVectorIndex
///
/// Tests cover:
/// - Basic add/search operations
/// - Dimension validation
/// - Rebuild from documents
/// - Clear functionality
/// - Search accuracy vs brute-force
void main() {
  group('HnswVectorIndex', () {
    late HnswVectorIndex index;

    setUp(() {
      index = HnswVectorIndex();
    });

    group('Basic Operations', () {
      test('starts empty', () {
        expect(index.isEmpty, true);
        expect(index.count, 0);
        expect(index.dimension, null);
      });

      test('add sets dimension', () {
        index.add('doc1', [1.0, 0.0, 0.0]);

        expect(index.isEmpty, false);
        expect(index.count, 1);
        expect(index.dimension, 3);
      });

      test('add multiple documents', () {
        index.add('doc1', [1.0, 0.0, 0.0]);
        index.add('doc2', [0.0, 1.0, 0.0]);
        index.add('doc3', [0.0, 0.0, 1.0]);

        expect(index.count, 3);
        expect(index.dimension, 3);
      });

      test('add rejects dimension mismatch', () {
        index.add('doc1', [1.0, 0.0, 0.0]);

        expect(
          () => index.add('doc2', [1.0, 0.0, 0.0, 0.0]),
          throwsArgumentError,
        );
      });

      test('add updates existing document', () {
        index.add('doc1', [1.0, 0.0, 0.0]);
        index.add('doc1', [0.0, 1.0, 0.0]); // Same ID, different embedding

        expect(index.count, 1);

        // Search should find updated embedding
        final results = index.search([0.0, 1.0, 0.0], 1);
        expect(results.length, 1);
        expect(results[0].id, 'doc1');
        expect(results[0].similarity, closeTo(1.0, 0.001));
      });
    });

    group('Search', () {
      test('search returns empty for empty index', () {
        final results = index.search([1.0, 0.0, 0.0], 5);
        expect(results, isEmpty);
      });

      test('search finds exact match', () {
        index.add('doc1', [1.0, 0.0, 0.0]);

        final results = index.search([1.0, 0.0, 0.0], 1);

        expect(results.length, 1);
        expect(results[0].id, 'doc1');
        expect(results[0].similarity, closeTo(1.0, 0.001));
      });

      test('search returns results sorted by similarity', () {
        // Add more documents to ensure HNSW has enough to work with
        index.add('exact', [1.0, 0.0, 0.0]);
        index.add('similar', [0.9, 0.1, 0.0]);
        index.add('different', [0.0, 1.0, 0.0]);

        final results = index.search([1.0, 0.0, 0.0], 3);

        // HNSW is approximate, so we just verify:
        // 1. Results are sorted by similarity (descending)
        // 2. First result should be exact match
        expect(results.isNotEmpty, true);
        expect(results[0].id, 'exact');
        expect(results[0].similarity, closeTo(1.0, 0.001));

        // Verify results are sorted
        for (int i = 1; i < results.length; i++) {
          expect(results[i].similarity, lessThanOrEqualTo(results[i - 1].similarity));
        }
      });

      test('search respects threshold', () {
        index.add('doc1', [1.0, 0.0, 0.0]); // similarity = 1.0
        index.add('doc2', [0.7, 0.7, 0.0]); // similarity ~0.707
        index.add('doc3', [0.0, 1.0, 0.0]); // similarity = 0.0

        final results = index.search([1.0, 0.0, 0.0], 10, threshold: 0.5);

        // All results should be above threshold
        for (final result in results) {
          expect(result.similarity, greaterThanOrEqualTo(0.5));
        }

        // doc1 (exact match) should definitely be included
        expect(results.any((r) => r.id == 'doc1'), true);

        // doc3 (similarity = 0.0) should not be included
        expect(results.any((r) => r.id == 'doc3'), false);
      });

      test('search respects topK', () {
        for (int i = 0; i < 10; i++) {
          index.add('doc$i', [i.toDouble() / 10, 0.0, 0.0]);
        }

        final results = index.search([1.0, 0.0, 0.0], 3);

        expect(results.length, 3);
      });

      test('search rejects dimension mismatch', () {
        index.add('doc1', [1.0, 0.0, 0.0]);

        expect(
          () => index.search([1.0, 0.0, 0.0, 0.0], 1),
          throwsArgumentError,
        );
      });
    });

    group('Clear', () {
      test('clear removes all documents', () {
        index.add('doc1', [1.0, 0.0, 0.0]);
        index.add('doc2', [0.0, 1.0, 0.0]);

        index.clear();

        expect(index.isEmpty, true);
        expect(index.count, 0);
        expect(index.dimension, null);
      });

      test('clear allows new dimension', () {
        index.add('doc1', [1.0, 0.0, 0.0]); // 3D
        index.clear();
        index.add('doc1', [1.0, 0.0, 0.0, 0.0]); // 4D - should work

        expect(index.dimension, 4);
      });
    });

    group('Rebuild', () {
      test('rebuild from empty list', () {
        index.add('doc1', [1.0, 0.0, 0.0]);

        index.rebuild([]);

        expect(index.isEmpty, true);
        expect(index.dimension, null);
      });

      test('rebuild from document list', () {
        final docs = [
          DocumentEmbedding(id: 'doc1', embedding: [1.0, 0.0, 0.0]),
          DocumentEmbedding(id: 'doc2', embedding: [0.0, 1.0, 0.0]),
          DocumentEmbedding(id: 'doc3', embedding: [0.0, 0.0, 1.0]),
        ];

        index.rebuild(docs);

        expect(index.count, 3);
        expect(index.dimension, 3);

        // Verify search works after rebuild
        final results = index.search([1.0, 0.0, 0.0], 1);
        expect(results[0].id, 'doc1');
      });

      test('rebuild clears existing data', () {
        index.add('old', [1.0, 2.0, 3.0]);

        index.rebuild([
          DocumentEmbedding(id: 'new', embedding: [4.0, 5.0, 6.0]),
        ]);

        expect(index.count, 1);

        // Old document should not be found
        final results = index.search([1.0, 2.0, 3.0], 1);
        expect(results[0].id, 'new');
      });
    });

    group('Remove', () {
      test('remove decreases count', () {
        index.add('doc1', [1.0, 0.0, 0.0]);
        index.add('doc2', [0.0, 1.0, 0.0]);

        index.remove('doc1');

        expect(index.count, 1);
      });

      test('remove non-existent document is safe', () {
        index.add('doc1', [1.0, 0.0, 0.0]);

        // Should not throw
        index.remove('non_existent');

        expect(index.count, 1);
      });

      test('removed document not found in search', () {
        index.add('doc1', [1.0, 0.0, 0.0]);
        index.add('doc2', [0.9, 0.1, 0.0]);

        index.remove('doc1');

        final results = index.search([1.0, 0.0, 0.0], 10);
        expect(results.any((r) => r.id == 'doc1'), false);
        expect(results.any((r) => r.id == 'doc2'), true);
      });
    });

    group('Accuracy vs Brute-Force', () {
      test('similarity matches brute-force calculation', () {
        // Add test vectors
        index.add('doc1', [1.0, 0.0, 0.0]);
        index.add('doc2', [0.9, 0.1, 0.0]);
        index.add('doc3', [0.7, 0.7, 0.0]);

        final query = [1.0, 0.0, 0.0];
        final results = index.search(query, 3);

        // Verify similarity values match brute-force
        for (final result in results) {
          final expectedSimilarity = _bruteForceCosineSimilarity(
            query,
            _getEmbedding(result.id),
          );
          expect(result.similarity, closeTo(expectedSimilarity, 0.0001));
        }
      });

      test('finds correct top-K with high-dimensional vectors', () {
        // Add vectors with clear similarity relationships
        // Use normalized unit vectors for predictable similarity
        final docs = <DocumentEmbedding>[];

        // Create a query vector
        final queryVec = List.generate(768, (j) => j == 0 ? 1.0 : 0.0);
        docs.add(DocumentEmbedding(id: 'exact_match', embedding: queryVec));

        // Create similar vectors (pointing mostly in same direction)
        for (int i = 0; i < 10; i++) {
          final vec = List.generate(768, (j) {
            if (j == 0) return 0.9 - i * 0.05;
            if (j == i + 1) return 0.1 + i * 0.05;
            return 0.0;
          });
          docs.add(DocumentEmbedding(id: 'similar_$i', embedding: vec));
        }

        // Create orthogonal vectors
        for (int i = 0; i < 10; i++) {
          final vec = List.generate(768, (j) => j == i + 100 ? 1.0 : 0.0);
          docs.add(DocumentEmbedding(id: 'orthogonal_$i', embedding: vec));
        }

        index.rebuild(docs);

        // Search
        final results = index.search(queryVec, 5);

        // Should find the exact match with similarity = 1.0
        expect(results.isNotEmpty, true);
        expect(results[0].similarity, closeTo(1.0, 0.0001));
        expect(results[0].id, 'exact_match');

        // All results should have positive similarity (pointing somewhat in same direction)
        for (final result in results) {
          expect(result.similarity, greaterThan(0.0));
        }
      });
    });
  });
}

/// Helper: Get embedding by document ID (for test verification)
List<double> _getEmbedding(String id) {
  switch (id) {
    case 'doc1':
      return [1.0, 0.0, 0.0];
    case 'doc2':
      return [0.9, 0.1, 0.0];
    case 'doc3':
      return [0.7, 0.7, 0.0];
    default:
      throw ArgumentError('Unknown doc ID: $id');
  }
}

/// Brute-force cosine similarity (reference implementation)
double _bruteForceCosineSimilarity(List<double> a, List<double> b) {
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
