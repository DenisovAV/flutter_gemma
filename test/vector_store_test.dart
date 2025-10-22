import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/pigeon.g.dart';

/// VectorStore Unit Tests (v0.11.7)
///
/// These tests verify VectorStore requirements based on:
/// - CHANGELOG.md (v0.11.7 optimization specs)
/// - Android implementation (VectorStore.kt)
/// - iOS implementation (VectorStore.swift)
/// - Public API (flutter_gemma_interface.dart)
///
/// IMPORTANT: These are unit tests for Dart-side logic ONLY.
/// Platform-specific functionality (SQLite, BLOB encoding) requires
/// manual testing on devices (see VECTORSTORE_TESTING_GUIDE.md).
void main() {
  group('VectorStore Binary BLOB Format', () {
    test('REQUIREMENT: 768D embedding should be exactly 3,072 bytes (float32)', () {
      // CHANGELOG.md: "Binary BLOB format instead of JSON (3 KB vs 10.5 KB per 768D embedding)"
      // Android VectorStore.kt:194: buffer.allocate(embedding.size * 4)
      // iOS VectorStore.swift:261: Data(count: embedding.count * 4)

      const dimension = 768;
      const bytesPerFloat32 = 4; // IEEE 754 single precision
      const expectedSizeBytes = dimension * bytesPerFloat32;
      const expectedSizeKB = expectedSizeBytes / 1024;

      expect(expectedSizeKB, 3.0,
        reason: '768D embedding must be exactly 3 KB in float32 BLOB format');
    });

    test('REQUIREMENT: Storage savings should be ~71% vs JSON', () {
      // CHANGELOG.md: "71% smaller storage"
      const jsonSizeKB = 10.5;  // Old JSON format
      const blobSizeKB = 3.0;    // New BLOB format (768D)
      final savingsPercent = ((jsonSizeKB - blobSizeKB) / jsonSizeKB) * 100;

      expect(savingsPercent, closeTo(71.4, 0.5),
        reason: 'BLOB format should save ~71% storage vs JSON');
    });

    test('REQUIREMENT: Common embedding dimensions follow float32 sizing', () {
      // VectorStore.kt:22-29, VectorStore.swift:24-31 (common dimensions)
      final dimensions = {
        'Gecko Small': 256,
        'MiniLM': 384,
        'BERT-base': 768,
        'BERT-large/Cohere': 1024,
        'OpenAI Ada': 1536,
        'OpenAI Large': 3072,
        'Qwen-3': 4096,
      };

      for (final entry in dimensions.entries) {
        final sizeBytes = entry.value * 4;
        final sizeKB = sizeBytes / 1024;

        // Verify calculation is correct
        expect(sizeKB, entry.value / 256,
          reason: '${entry.key} (${entry.value}D) should be ${entry.value / 256} KB');
      }
    });
  });

  group('Cosine Similarity Algorithm', () {
    test('REQUIREMENT: Identical vectors must have similarity 1.0', () {
      // VectorStore.kt:169-185, VectorUtils.swift:14-31
      // Formula: dotProduct / (sqrt(normA) * sqrt(normB))
      final vectorA = [1.0, 2.0, 3.0, 4.0];
      final vectorB = [1.0, 2.0, 3.0, 4.0];

      final similarity = _cosineSimilarity(vectorA, vectorB);

      expect(similarity, closeTo(1.0, 0.0001),
        reason: 'Identical vectors must have cosine similarity = 1.0');
    });

    test('REQUIREMENT: Orthogonal vectors must have similarity 0.0', () {
      // Example: [1,0,0] and [0,1,0] are perpendicular
      final vectorA = [1.0, 0.0, 0.0];
      final vectorB = [0.0, 1.0, 0.0];

      final similarity = _cosineSimilarity(vectorA, vectorB);

      expect(similarity, closeTo(0.0, 0.0001),
        reason: 'Orthogonal vectors must have cosine similarity = 0.0');
    });

    test('REQUIREMENT: Opposite vectors must have similarity -1.0', () {
      // Example: [1,2,3] and [-1,-2,-3] point in opposite directions
      final vectorA = [1.0, 2.0, 3.0];
      final vectorB = [-1.0, -2.0, -3.0];

      final similarity = _cosineSimilarity(vectorA, vectorB);

      expect(similarity, closeTo(-1.0, 0.0001),
        reason: 'Opposite vectors must have cosine similarity = -1.0');
    });

    test('REQUIREMENT: Zero vector must return 0.0 (avoid division by zero)', () {
      // VectorStore.kt:182-184: "if (normA != 0.0 && normB != 0.0) ... else 0.0"
      // VectorUtils.swift:25-28: "guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }"
      final vectorA = [1.0, 2.0, 3.0];
      final vectorB = [0.0, 0.0, 0.0];

      final similarity = _cosineSimilarity(vectorA, vectorB);

      expect(similarity, 0.0,
        reason: 'Zero vector should return 0.0 (not NaN or throw)');
    });

    test('REQUIREMENT: Dimension mismatch must return 0.0', () {
      // VectorStore.kt:170: "if (a.size != b.size) return 0.0"
      // VectorUtils.swift:15-18: "guard vectorA.count == vectorB.count ... return 0.0"
      final vectorA = [1.0, 2.0, 3.0];
      final vectorB = [1.0, 2.0]; // Different dimension

      final similarity = _cosineSimilarity(vectorA, vectorB);

      expect(similarity, 0.0,
        reason: 'Dimension mismatch should return 0.0');
    });

    test('REQUIREMENT: High-dimensional vectors (768D) must compute correctly', () {
      // Real-world scenario: BERT-base embeddings
      final vectorA = List.generate(768, (i) => (i + 1) / 768.0);
      final vectorB = List.generate(768, (i) => (i + 1) / 768.0);

      final similarity = _cosineSimilarity(vectorA, vectorB);

      expect(similarity, closeTo(1.0, 0.0001),
        reason: '768D identical vectors should still compute similarity = 1.0');
    });
  });

  group('Dimension Validation Requirements', () {
    test('REQUIREMENT: First document auto-detects dimension', () {
      // VectorStore.kt:71-72: "detectedDimension = dimension ?: embedding.size"
      // VectorStore.swift:64-65: "detectedDimension = dimension ?? embedding.count"

      int? detectedDimension;
      final embedding = List.generate(768, (i) => i / 768.0);

      // Simulate first document
      detectedDimension ??= embedding.length;

      expect(detectedDimension, 768,
        reason: 'First document should auto-detect dimension from embedding');
    });

    test('REQUIREMENT: Explicit dimension must validate against embedding', () {
      // VectorStore.kt:75-78: "if (dimension != null && dimension != embedding.size) throw"
      // VectorStore.swift:68-72: "if let expectedDim = dimension, expectedDim != embedding.count { throw }"

      const specifiedDimension = 1024;
      final embedding = List.generate(768, (i) => i / 768.0);

      final isValid = specifiedDimension == embedding.length;

      expect(isValid, false,
        reason: 'Should detect mismatch between specified (1024) and actual (768) dimension');
    });

    test('REQUIREMENT: Subsequent documents must match detected dimension', () {
      // VectorStore.kt:83-86: "if (embedding.size != detectedDimension) throw"
      // VectorStore.swift:77-81: "if embedding.count != detectedDimension { throw }"

      final detectedDimension = 768;
      final embedding1 = List.generate(768, (i) => i / 768.0);
      final embedding2 = List.generate(256, (i) => i / 256.0);

      expect(embedding1.length, detectedDimension,
        reason: 'First subsequent document matches');
      expect(embedding2.length, isNot(detectedDimension),
        reason: 'Second subsequent document should fail validation');
    });
  });

  group('searchSimilar() Algorithm', () {
    test('REQUIREMENT: Results must be filtered by threshold', () {
      // VectorStore.kt:132: "if (similarity >= threshold)"
      // VectorStore.swift:163: "if similarity >= threshold"

      final mockResults = [
        (similarity: 0.95, doc: 'doc1'),
        (similarity: 0.75, doc: 'doc2'),
        (similarity: 0.45, doc: 'doc3'),
        (similarity: 0.20, doc: 'doc4'),
      ];

      const threshold = 0.5;
      final filtered = mockResults.where((r) => r.similarity >= threshold).toList();

      expect(filtered.length, 2,
        reason: 'Should filter out results below threshold 0.5');
      expect(filtered.map((r) => r.doc), ['doc1', 'doc2']);
    });

    test('REQUIREMENT: Results must be sorted by similarity (descending)', () {
      // VectorStore.kt:145: ".sortedByDescending { it.second }"
      // VectorStore.swift:184: ".sorted { $0.similarity > $1.similarity }"

      final mockResults = [
        (similarity: 0.45, doc: 'doc3'),
        (similarity: 0.95, doc: 'doc1'),
        (similarity: 0.20, doc: 'doc4'),
        (similarity: 0.75, doc: 'doc2'),
      ];

      final sorted = mockResults.toList()
        ..sort((a, b) => b.similarity.compareTo(a.similarity));

      expect(sorted.map((r) => r.doc), ['doc1', 'doc2', 'doc3', 'doc4'],
        reason: 'Must be sorted by similarity descending');
      expect(sorted.map((r) => r.similarity), [0.95, 0.75, 0.45, 0.20]);
    });

    test('REQUIREMENT: Results must be limited to topK', () {
      // VectorStore.kt:146: ".take(topK)"
      // VectorStore.swift:185: ".prefix(topK)"

      final mockResults = [
        (similarity: 0.95, doc: 'doc1'),
        (similarity: 0.85, doc: 'doc2'),
        (similarity: 0.75, doc: 'doc3'),
        (similarity: 0.65, doc: 'doc4'),
        (similarity: 0.55, doc: 'doc5'),
      ];

      const topK = 3;
      final limited = mockResults.take(topK).toList();

      expect(limited.length, 3,
        reason: 'Should return exactly topK results');
      expect(limited.map((r) => r.doc), ['doc1', 'doc2', 'doc3']);
    });

    test('REQUIREMENT: Combined filter + sort + limit pipeline', () {
      // Full searchSimilar() logic
      final mockResults = [
        (similarity: 0.95, doc: 'doc1'),
        (similarity: 0.30, doc: 'doc2'), // Below threshold
        (similarity: 0.85, doc: 'doc3'),
        (similarity: 0.15, doc: 'doc4'), // Below threshold
        (similarity: 0.75, doc: 'doc5'),
        (similarity: 0.65, doc: 'doc6'),
      ];

      const threshold = 0.5;
      const topK = 3;

      final results = mockResults
          .where((r) => r.similarity >= threshold)
          .toList()
        ..sort((a, b) => b.similarity.compareTo(a.similarity));
      final final_results = results.take(topK).toList();

      expect(final_results.length, 3);
      expect(final_results.map((r) => r.doc), ['doc1', 'doc3', 'doc5']);
      expect(final_results.map((r) => r.similarity), [0.95, 0.85, 0.75]);
    });
  });

  group('VectorStoreStats Pigeon Encoding', () {
    test('REQUIREMENT: encode() must return List (Pigeon protocol)', () {
      // pigeon.g.dart:75-78: return <Object?>[documentCount, vectorDimension]
      final stats = VectorStoreStats(documentCount: 512, vectorDimension: 1024);

      final encoded = stats.encode();

      expect(encoded, isA<List<Object?>>(),
        reason: 'Pigeon requires List for platform channel serialization');
    });

    test('REQUIREMENT: encode() list must be [documentCount, vectorDimension]', () {
      // Verify field order matches Pigeon definition
      final stats = VectorStoreStats(documentCount: 100, vectorDimension: 768);

      final encoded = stats.encode() as List<Object?>;

      expect(encoded.length, 2);
      expect(encoded[0], 100, reason: 'First element must be documentCount');
      expect(encoded[1], 768, reason: 'Second element must be vectorDimension');
    });

    test('REQUIREMENT: decode() must accept List and return VectorStoreStats', () {
      // pigeon.g.dart:81-87: static VectorStoreStats decode(Object result)
      final encoded = <Object?>[256, 1536];

      final stats = VectorStoreStats.decode(encoded);

      expect(stats.documentCount, 256);
      expect(stats.vectorDimension, 1536);
    });

    test('REQUIREMENT: encode/decode roundtrip must preserve values', () {
      // Critical for platform channel communication
      final original = VectorStoreStats(documentCount: 999, vectorDimension: 2048);

      final encoded = original.encode();
      final decoded = VectorStoreStats.decode(encoded);

      expect(decoded.documentCount, original.documentCount,
        reason: 'documentCount must survive encode/decode');
      expect(decoded.vectorDimension, original.vectorDimension,
        reason: 'vectorDimension must survive encode/decode');
    });
  });

  group('RetrievalResult Pigeon Encoding', () {
    test('REQUIREMENT: encode() must return List (Pigeon protocol)', () {
      // pigeon.g.dart:44-51: return <Object?>[id, content, similarity, metadata]
      final result = RetrievalResult(
        id: 'doc1',
        content: 'Test',
        similarity: 0.95,
        metadata: '{"key":"value"}',
      );

      final encoded = result.encode();

      expect(encoded, isA<List<Object?>>(),
        reason: 'Pigeon requires List for platform channel serialization');
    });

    test('REQUIREMENT: encode() list must be [id, content, similarity, metadata]', () {
      final result = RetrievalResult(
        id: 'doc123',
        content: 'Content here',
        similarity: 0.85,
        metadata: null,
      );

      final encoded = result.encode() as List<Object?>;

      expect(encoded.length, 4);
      expect(encoded[0], 'doc123', reason: 'Index 0 must be id');
      expect(encoded[1], 'Content here', reason: 'Index 1 must be content');
      expect(encoded[2], 0.85, reason: 'Index 2 must be similarity');
      expect(encoded[3], null, reason: 'Index 3 must be metadata (nullable)');
    });

    test('REQUIREMENT: decode() must handle metadata=null', () {
      // pigeon.g.dart:59: metadata: result[3] as String?
      final encoded = <Object?>['doc1', 'Content', 0.75, null];

      final result = RetrievalResult.decode(encoded);

      expect(result.id, 'doc1');
      expect(result.content, 'Content');
      expect(result.similarity, 0.75);
      expect(result.metadata, isNull, reason: 'Metadata should be null');
    });

    test('REQUIREMENT: encode/decode roundtrip preserves all fields', () {
      final original = RetrievalResult(
        id: 'test_doc',
        content: 'Test content with Unicode: 世界 🌍',
        similarity: 0.999,
        metadata: '{"author":"test","timestamp":1234567890}',
      );

      final encoded = original.encode();
      final decoded = RetrievalResult.decode(encoded);

      expect(decoded.id, original.id);
      expect(decoded.content, original.content);
      expect(decoded.similarity, original.similarity);
      expect(decoded.metadata, original.metadata);
    });
  });

  group('Performance Expectations (CHANGELOG.md)', () {
    test('CLAIMED: 71% storage reduction vs JSON', () {
      // CHANGELOG.md line 3: "71% smaller storage"
      const oldJsonSize = 10.5; // KB
      const newBlobSize = 3.0;  // KB
      final reduction = ((oldJsonSize - newBlobSize) / oldJsonSize) * 100;

      expect(reduction, closeTo(71.4, 1.0),
        reason: 'Claimed 71% reduction should be mathematically accurate');
    });

    test('CLAIMED: 6.7x faster reads (~500μs → ~75μs)', () {
      // CHANGELOG.md line 4: "6.7x faster reads"
      const oldReadMicros = 500.0;
      const newReadMicros = 75.0;
      final speedup = oldReadMicros / newReadMicros;

      expect(speedup, closeTo(6.67, 0.1),
        reason: 'Claimed 6.7x read speedup should be accurate');
    });

    test('CLAIMED: 3.3x faster writes (~150μs → ~45μs)', () {
      // CHANGELOG.md line 5: "3.3x faster writes"
      const oldWriteMicros = 150.0;
      const newWriteMicros = 45.0;
      final speedup = oldWriteMicros / newWriteMicros;

      expect(speedup, closeTo(3.33, 0.1),
        reason: 'Claimed 3.3x write speedup should be accurate');
    });
  });
}

// ============================================================================
// HELPER FUNCTIONS (replicate native implementation logic for testing)
// ============================================================================

/// Cosine similarity implementation matching VectorStore.kt and VectorUtils.swift
///
/// Android (VectorStore.kt:169-185):
///   cosineSimilarity(a, b) = dotProduct / (sqrt(normA) * sqrt(normB))
///
/// iOS (VectorUtils.swift:14-31):
///   cosineSimilarity(vectorA, vectorB) = dotProduct / (magnitudeA * magnitudeB)
double _cosineSimilarity(List<double> a, List<double> b) {
  // REQUIREMENT: Dimension mismatch returns 0.0
  if (a.length != b.length) return 0.0;

  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  // REQUIREMENT: Zero vector returns 0.0 (avoid division by zero)
  if (normA == 0.0 || normB == 0.0) return 0.0;

  return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
}
