import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';

/// Integration tests for VectorStore
///
/// Tests full stack: Dart → sqlite3 dart:ffi (unified across all native platforms)
/// Run: flutter test integration_test/vector_store_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;

  setUpAll(() async {
    await FlutterGemma.initialize();
    final tempDir = await getTemporaryDirectory();
    databasePath = '${tempDir.path}/test_vector_store.db';
  });

  Future<void> initStore() async {
    await FlutterGemmaPlugin.instance.initializeVectorStore(databasePath);
  }

  Future<void> cleanupStore() async {
    try {
      await FlutterGemmaPlugin.instance.clearVectorStore();
    } catch (_) {}
    final dbFile = File(databasePath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  }

  group('VectorStore Integration Tests', () {
    testWidgets('Test 1: Initialize VectorStore', (tester) async {
      await initStore();
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 0);
      expect(stats.vectorDimension, 0);
      await cleanupStore();
    });

    testWidgets('Test 2: Add Document with Embedding', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Hello, world!',
        embedding: [1.0, 0.0, 0.0],
        metadata: '{"source": "test"}',
      );

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);
      expect(stats.vectorDimension, 3);
      await cleanupStore();
    });

    testWidgets('Test 3: Search Similar Documents', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document about cats',
        embedding: [1.0, 0.0, 0.0],
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Document about dogs',
        embedding: [0.9, 0.1, 0.0],
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc3',
        content: 'Document about cars',
        embedding: [0.0, 1.0, 0.0],
      );

      final results = await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 2,
        threshold: 0.5,
      );

      expect(results.length, 2);
      expect(results[0].id, 'doc1');
      expect(results[0].similarity, closeTo(1.0, 0.01));
      expect(results[1].id, 'doc2');
      expect(results[1].similarity, greaterThan(0.9));
      await cleanupStore();
    });

    testWidgets('Test 4: Get Stats', (tester) async {
      await initStore();
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
      await cleanupStore();
    });

    testWidgets('Test 5: Clear Store', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document 1',
        embedding: [1.0, 0.0, 0.0],
      );

      var stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);

      await FlutterGemmaPlugin.instance.clearVectorStore();

      stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 0);
      await cleanupStore();
    });

    testWidgets('Test 6: Dimension Validation - Reject Mismatched', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document 1',
        embedding: [1.0, 0.0, 0.0],
      );

      // ArgumentError is an Error, not Exception — use throwsA
      await expectLater(
        () => FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: 'doc2',
          content: 'Document 2',
          embedding: [1.0, 0.0, 0.0, 0.0], // 4D instead of 3D
        ),
        throwsA(isA<ArgumentError>()),
      );
      await cleanupStore();
    });

    testWidgets('Test 7: BLOB Compatibility - Round Trip', (tester) async {
      await initStore();
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

      final results = await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
        queryEmbedding: originalEmbedding,
        topK: 1,
        threshold: 0.0,
      );

      expect(results.length, 1);
      expect(results[0].id, 'doc1');
      expect(results[0].similarity, closeTo(1.0, 0.0001));
      await cleanupStore();
    });

    testWidgets('Test 8: Metadata Storage and Retrieval', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Document with metadata',
        embedding: [1.0, 0.0, 0.0],
        metadata: '{"author": "Alice", "date": "2024-11-18"}',
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Document without metadata',
        embedding: [0.9, 0.1, 0.0],
      );

      final results = await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 2,
        threshold: 0.0,
      );

      expect(results.length, 2);
      expect(results[0].metadata, isNotNull);
      expect(results[0].metadata, contains('Alice'));
      expect(results[1].metadata, isNull);
      await cleanupStore();
    });

    testWidgets('Test 9: Threshold Filtering', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Very similar',
        embedding: [1.0, 0.0, 0.0],
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Somewhat similar',
        embedding: [0.7, 0.7, 0.0],
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc3',
        content: 'Not similar',
        embedding: [0.0, 1.0, 0.0],
      );

      final resultsHighThreshold = await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 10,
        threshold: 0.8,
      );
      expect(resultsHighThreshold.length, 1);
      expect(resultsHighThreshold[0].id, 'doc1');

      final resultsLowThreshold = await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 10,
        threshold: 0.0,
      );
      expect(resultsLowThreshold.length, 3);
      await cleanupStore();
    });

    testWidgets('Test 10: INSERT OR REPLACE - Document Update', (tester) async {
      await initStore();
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Original content',
        embedding: [1.0, 0.0, 0.0],
        metadata: '{"version": 1}',
      );

      var stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Updated content',
        embedding: [0.0, 1.0, 0.0],
        metadata: '{"version": 2}',
      );

      stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, 1);

      final results = await ServiceRegistry.instance.vectorStoreRepository.searchSimilar(
        queryEmbedding: [0.0, 1.0, 0.0],
        topK: 1,
        threshold: 0.0,
      );

      expect(results.length, 1);
      expect(results[0].id, 'doc1');
      expect(results[0].content, 'Updated content');
      expect(results[0].metadata, contains('version": 2'));
      await cleanupStore();
    });
  });
}
