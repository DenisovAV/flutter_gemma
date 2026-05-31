import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/infrastructure/dart_vector_store_repository.dart';

void main() {
  late DartVectorStoreRepository repo;
  late String dbPath;

  setUp(() {
    repo = DartVectorStoreRepository();
    dbPath =
        '${Directory.systemTemp.path}/test_vector_store_${DateTime.now().millisecondsSinceEpoch}.db';
  });

  tearDown(() async {
    await repo.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  group('DartVectorStoreRepository', () {
    test('initialize creates database', () async {
      await repo.initialize(dbPath);
      expect(repo.isInitialized, true);
      expect(File(dbPath).existsSync(), true);
    });

    test('addDocument and getStats', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Hello world',
        embedding: [1.0, 0.0, 0.0],
      );
      final stats = await repo.getStats();
      expect(stats.documentCount, 1);
      expect(stats.vectorDimension, 3);
    });

    test('addDocument replaces existing', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Version 1',
        embedding: [1.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc1',
        content: 'Version 2',
        embedding: [0.0, 1.0, 0.0],
      );
      final stats = await repo.getStats();
      expect(stats.documentCount, 1);
    });

    test('addDocument validates dimension', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Hello',
        embedding: [1.0, 0.0, 0.0],
      );
      expect(
        () => repo.addDocument(
          id: 'doc2',
          content: 'World',
          embedding: [1.0, 0.0], // wrong dimension
        ),
        throwsArgumentError,
      );
    });

    test('searchSimilar returns correct results', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Similar',
        embedding: [1.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc2',
        content: 'Different',
        embedding: [0.0, 1.0, 0.0],
      );
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 2,
      );
      expect(results.length, 2);
      expect(results.first.id, 'doc1');
      expect(results.first.similarity, closeTo(1.0, 0.001));
    });

    test('searchSimilar respects threshold', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Similar',
        embedding: [1.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc2',
        content: 'Orthogonal',
        embedding: [0.0, 1.0, 0.0],
      );
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 2,
        threshold: 0.5,
      );
      expect(results.length, 1);
      expect(results.first.id, 'doc1');
    });

    test('clear removes all documents', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Hello',
        embedding: [1.0, 0.0, 0.0],
      );
      await repo.clear();
      final stats = await repo.getStats();
      expect(stats.documentCount, 0);
    });

    test('close and reinitialize', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Persistent',
        embedding: [1.0, 0.0, 0.0],
      );
      await repo.close();

      // Reinitialize — data should persist
      repo = DartVectorStoreRepository();
      await repo.initialize(dbPath);
      final stats = await repo.getStats();
      expect(stats.documentCount, 1);
    });

    test('HNSW integration — search uses HNSW for large datasets', () async {
      await repo.initialize(dbPath);
      // Add 150 docs (above _hnswThreshold = 100)
      for (int i = 0; i < 150; i++) {
        final vec = List.filled(3, 0.0);
        vec[i % 3] = 1.0;
        await repo.addDocument(
          id: 'doc$i',
          content: 'Document $i',
          embedding: vec,
        );
      }
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 5,
      );
      expect(results.isNotEmpty, true);
      // Top result should be a doc with [1,0,0] embedding
      expect(results.first.similarity, closeTo(1.0, 0.01));
    });
  });
}
