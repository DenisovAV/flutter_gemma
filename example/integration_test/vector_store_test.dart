import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Integration tests for VectorStore (Level 1: E2E on real devices)
///
/// Tests full stack: Dart → Pigeon → Native (iOS/Android)
/// Requires real device/simulator to run
///
/// Run with: flutter test integration_test/vector_store_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;
  late PlatformService platformService;

  setUpAll(() async {
    // Initialize FlutterGemma (required for ServiceRegistry)
    await FlutterGemma.initialize();

    // Get a unique temporary database path for tests
    final tempDir = await getTemporaryDirectory();
    databasePath = '${tempDir.path}/test_vector_store.db';

    // Create platform service for direct API access (bypasses embedding model requirement)
    platformService = PlatformService();
  });

  setUp(() async {
    // Initialize vector store before each test
    await FlutterGemmaPlugin.instance.initializeVectorStore(databasePath);
  });

  tearDown(() async {
    // Clean up after each test
    try {
      await FlutterGemmaPlugin.instance.clearVectorStore();
    } catch (_) {
      // Ignore cleanup errors
    }

    // Delete database file
    final dbFile = File(databasePath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  });

  group('VectorStore Integration Tests', () {
    testWidgets('Test 1: Initialize VectorStore', (WidgetTester tester) async {
      // Verify database is initialized by checking stats
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 0);
      expect(stats.vectorDimension, 0); // No documents yet
    });

    testWidgets('Test 2: Add Document with Embedding',
        (WidgetTester tester) async {
      // Add a document with a simple 3D embedding
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Hello, world!',
        embedding: [1.0, 0.0, 0.0],
        metadata: '{"source": "test"}',
      );

      // Verify document was added
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);
      expect(stats.vectorDimension, 3);
    });

    testWidgets('Test 3: Search Similar Documents',
        (WidgetTester tester) async {
      // Add multiple documents with different embeddings
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document about cats',
        embedding: [1.0, 0.0, 0.0],
      );

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Document about dogs',
        embedding: [0.9, 0.1, 0.0], // Similar to doc1
      );

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc3',
        content: 'Document about cars',
        embedding: [0.0, 1.0, 0.0], // Different from doc1
      );

      // Search for documents similar to [1.0, 0.0, 0.0]
      // Use PlatformService directly to search by embedding (no embedding model required)
      final results = await platformService.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 2,
        threshold: 0.5,
      );

      // Should find doc1 and doc2
      expect(results.length, 2);
      expect(results[0].id, 'doc1'); // Exact match
      expect(results[0].similarity, closeTo(1.0, 0.01));
      expect(results[1].id, 'doc2'); // Similar
      expect(results[1].similarity, greaterThan(0.9));
    });

    testWidgets('Test 4: Get Stats', (WidgetTester tester) async {
      // Add 5 documents
      for (int i = 0; i < 5; i++) {
        await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: 'doc$i',
          content: 'Document $i',
          embedding: [i.toDouble(), 0.0, 0.0],
        );
      }

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 5);
      expect(stats.vectorDimension, 3);
    });

    testWidgets('Test 5: Clear Store', (WidgetTester tester) async {
      // Add documents
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document 1',
        embedding: [1.0, 0.0, 0.0],
      );

      // Verify document was added
      var stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);

      // Clear store
      await FlutterGemmaPlugin.instance.clearVectorStore();

      // Verify store is empty
      stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 0);
    });

    testWidgets('Test 6: Dimension Validation - Reject Mismatched',
        (WidgetTester tester) async {
      // Add first document with 3D embedding
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document 1',
        embedding: [1.0, 0.0, 0.0],
      );

      // Try to add document with different dimension (should fail)
      expect(
        () => FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: 'doc2',
          content: 'Document 2',
          embedding: [1.0, 0.0, 0.0, 0.0], // 4D instead of 3D
        ),
        throwsException,
      );
    });

    testWidgets('Test 7: BLOB Compatibility - Round Trip',
        (WidgetTester tester) async {
      // Add document with precise floating point values
      final originalEmbedding = [
        0.123456789,
        -0.987654321,
        0.5,
        0.0,
        1.0,
      ];

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Test document',
        embedding: originalEmbedding,
      );

      // Search with same embedding - should get exact match with similarity ~1.0
      final results = await platformService.searchSimilar(
        queryEmbedding: originalEmbedding,
        topK: 1,
        threshold: 0.0,
      );

      expect(results.length, 1);
      expect(results[0].id, 'doc1');
      // Similarity should be very close to 1.0 (allowing for float32 precision loss)
      expect(results[0].similarity, closeTo(1.0, 0.0001));
    });

    testWidgets('Test 8: Metadata Storage and Retrieval',
        (WidgetTester tester) async {
      // Add document with metadata
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document with metadata',
        embedding: [1.0, 0.0, 0.0],
        metadata: '{"author": "Alice", "date": "2024-11-18"}',
      );

      // Add document without metadata
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Document without metadata',
        embedding: [0.9, 0.1, 0.0],
      );

      // Search and verify metadata is preserved
      final results = await platformService.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 2,
        threshold: 0.0,
      );

      expect(results.length, 2);
      expect(results[0].metadata, isNotNull);
      expect(results[0].metadata, contains('Alice'));
      expect(results[1].metadata, isNull);
    });

    testWidgets('Test 9: Threshold Filtering', (WidgetTester tester) async {
      // Add documents with varying similarity
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Very similar',
        embedding: [1.0, 0.0, 0.0], // similarity = 1.0
      );

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Somewhat similar',
        embedding: [0.7, 0.7, 0.0], // similarity ~0.7
      );

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc3',
        content: 'Not similar',
        embedding: [0.0, 1.0, 0.0], // similarity = 0.0
      );

      // Search with high threshold (0.8)
      final resultsHighThreshold = await platformService.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 10,
        threshold: 0.8,
      );

      // Should only return doc1
      expect(resultsHighThreshold.length, 1);
      expect(resultsHighThreshold[0].id, 'doc1');

      // Search with low threshold (0.0)
      final resultsLowThreshold = await platformService.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 10,
        threshold: 0.0,
      );

      // Should return all 3 documents
      expect(resultsLowThreshold.length, 3);
    });

    testWidgets('Test 10: INSERT OR REPLACE - Document Update',
        (WidgetTester tester) async {
      // Add initial document
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Original content',
        embedding: [1.0, 0.0, 0.0],
        metadata: '{"version": 1}',
      );

      var stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);

      // Update same document (same ID, different content)
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Updated content',
        embedding: [0.0, 1.0, 0.0],
        metadata: '{"version": 2}',
      );

      // Should still have only 1 document
      stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);

      // Verify updated content is returned
      final results = await platformService.searchSimilar(
        queryEmbedding: [0.0, 1.0, 0.0],
        topK: 1,
        threshold: 0.0,
      );

      expect(results.length, 1);
      expect(results[0].id, 'doc1');
      expect(results[0].content, 'Updated content');
      expect(results[0].metadata, contains('version": 2'));
    });
  });
}
