// Native vec0 store test — runs against the real sqlite-vec loadable extension
// pointed to by $VEC0_DYLIB (the same gate as test/vec0_text_pk_test.dart).
//
//   VEC0_DYLIB=/path/to/vec0.dylib flutter test test/sqlite_vector_store_test.dart
//
// When $VEC0_DYLIB is unset the whole group is skipped (the store can't load
// vec0 without it on a host VM that has no bundled Native Assets dylib).
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';

String? get _vec0Path {
  final p = Platform.environment['VEC0_DYLIB'];
  if (p == null || p.isEmpty) return null;
  return File(p).existsSync() ? p : null;
}

void main() {
  final vec0 = _vec0Path;
  final skip = vec0 == null
      ? 'set \$VEC0_DYLIB to a prebuilt vec0 loadable (asg017/sqlite-vec)'
      : null;

  group('SqliteVectorStore (vec0)', () {
    late SqliteVectorStore repo;
    late String dbPath;

    setUp(() {
      repo = SqliteVectorStore();
      dbPath =
          '${Directory.systemTemp.path}/test_vec0_store_'
          '${DateTime.now().microsecondsSinceEpoch}.db';
    });

    tearDown(() async {
      await repo.close();
      final file = File(dbPath);
      if (file.existsSync()) file.deleteSync();
    });

    test('initialize creates a database file', () async {
      await repo.initialize(dbPath);
      expect(repo.isInitialized, true);
      expect(File(dbPath).existsSync(), true);
    });

    test('addDocument + getStats reports count and dimension', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Hello world',
        embedding: [1.0, 0.0, 0.0, 0.0],
      );
      final stats = await repo.getStats();
      expect(stats.documentCount, 1);
      expect(stats.vectorDimension, 4);
    });

    test('getStats before any add reports zero / zero', () async {
      await repo.initialize(dbPath);
      final stats = await repo.getStats();
      expect(stats.documentCount, 0);
      expect(stats.vectorDimension, 0);
    });

    test('addDocument with same id replaces (INSERT OR REPLACE)', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Version 1',
        embedding: [1.0, 0.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc1',
        content: 'Version 2',
        embedding: [0.0, 1.0, 0.0, 0.0],
      );
      final stats = await repo.getStats();
      expect(stats.documentCount, 1);

      final results = await repo.searchSimilar(
        queryEmbedding: [0.0, 1.0, 0.0, 0.0],
        topK: 1,
      );
      expect(results.single.content, 'Version 2');
    });

    test('addDocument validates dimension', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Hello',
        embedding: [1.0, 0.0, 0.0, 0.0],
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

    test('searchSimilar returns cosine similarity (1 = identical), top-K '
        'ordered descending', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Similar',
        embedding: [1.0, 0.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc2',
        content: 'Near',
        embedding: [0.9, 0.1, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc3',
        content: 'Orthogonal',
        embedding: [0.0, 1.0, 0.0, 0.0],
      );
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0, 0.0],
        topK: 3,
      );
      expect(results.length, 3);
      expect(results.first.id, 'doc1');
      expect(results.first.similarity, closeTo(1.0, 0.01));
      // Descending similarity order.
      for (var i = 1; i < results.length; i++) {
        expect(
          results[i].similarity,
          lessThanOrEqualTo(results[i - 1].similarity),
        );
      }
      expect(results.last.id, 'doc3');
    });

    test('searchSimilar respects topK', () async {
      await repo.initialize(dbPath);
      for (var i = 0; i < 5; i++) {
        await repo.addDocument(
          id: 'doc$i',
          content: 'Document $i',
          embedding: [1.0 - i * 0.1, i * 0.1, 0.0, 0.0],
        );
      }
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0, 0.0],
        topK: 2,
      );
      expect(results.length, 2);
    });

    test('searchSimilar respects threshold', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Identical',
        embedding: [1.0, 0.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc2',
        content: 'Orthogonal',
        embedding: [0.0, 1.0, 0.0, 0.0],
      );
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0, 0.0],
        topK: 2,
        threshold: 0.5,
      );
      expect(results.length, 1);
      expect(results.first.id, 'doc1');
    });

    test('searchSimilar before any add returns empty', () async {
      await repo.initialize(dbPath);
      final results = await repo.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0, 0.0],
        topK: 5,
      );
      expect(results, isEmpty);
    });

    test(
      'removeDocument removes the row (and is a no-op for missing id)',
      () async {
        await repo.initialize(dbPath);
        await repo.addDocument(
          id: 'doc1',
          content: 'Hello',
          embedding: [1.0, 0.0, 0.0, 0.0],
        );
        await repo.removeDocument(id: 'missing'); // no-op, no throw
        await repo.removeDocument(id: 'doc1');
        final stats = await repo.getStats();
        expect(stats.documentCount, 0);
      },
    );

    test('clear removes all documents and resets dimension', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Hello',
        embedding: [1.0, 0.0, 0.0, 0.0],
      );
      await repo.clear();
      final stats = await repo.getStats();
      expect(stats.documentCount, 0);
      expect(stats.vectorDimension, 0);
      // Re-detect a NEW dimension after clear.
      await repo.addDocument(
        id: 'doc2',
        content: 'New dims',
        embedding: [1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      );
      final stats2 = await repo.getStats();
      expect(stats2.vectorDimension, 6);
    });

    test('close then reinitialize — data persists on disk', () async {
      await repo.initialize(dbPath);
      await repo.addDocument(
        id: 'doc1',
        content: 'Persistent',
        embedding: [1.0, 0.0, 0.0, 0.0],
      );
      await repo.close();

      repo = SqliteVectorStore();
      await repo.initialize(dbPath);
      final stats = await repo.getStats();
      expect(stats.documentCount, 1);
      expect(stats.vectorDimension, 4);
    });

    test('uninitialized operations throw StateError', () async {
      final fresh = SqliteVectorStore();
      expect(
        () => fresh.addDocument(id: 'x', content: 'x', embedding: [1.0]),
        throwsStateError,
      );
      expect(
        () => fresh.searchSimilar(queryEmbedding: [1.0], topK: 1),
        throwsStateError,
      );
      expect(fresh.getStats, throwsStateError);
      expect(fresh.clear, throwsStateError);
      expect(() => fresh.removeDocument(id: 'x'), throwsStateError);
    });

    group('declared-column Filter', () {
      const schema = FilterSchema(
        fields: [
          FilterField(name: 'lang', type: FilterFieldType.string),
          FilterField(name: 'year', type: FilterFieldType.number),
          FilterField(name: 'archived', type: FilterFieldType.bool),
        ],
      );

      setUp(() {
        repo.configure(schema);
      });

      Future<void> seed() async {
        await repo.addDocument(
          id: 'en2020',
          content: 'English 2020',
          embedding: [1.0, 0.0, 0.0, 0.0],
          metadata: '{"lang":"en","year":2020,"archived":false}',
        );
        await repo.addDocument(
          id: 'fr2020',
          content: 'French 2020',
          embedding: [0.95, 0.05, 0.0, 0.0],
          metadata: '{"lang":"fr","year":2020,"archived":false}',
        );
        await repo.addDocument(
          id: 'en1999',
          content: 'English 1999 archived',
          embedding: [0.9, 0.1, 0.0, 0.0],
          metadata: '{"lang":"en","year":1999,"archived":true}',
        );
      }

      test('filterSchema is exposed after configure', () {
        expect(repo.filterSchema.fields, hasLength(3));
      });

      test('FieldEquals on a declared string column', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(
            must: [FieldEquals(key: 'lang', value: 'en')],
          ),
        );
        expect(results.map((r) => r.id).toSet(), {'en2020', 'en1999'});
      });

      test('FieldRange on a declared number column', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(must: [FieldRange(key: 'year', gte: 2000.0)]),
        );
        expect(results.map((r) => r.id).toSet(), {'en2020', 'fr2020'});
      });

      test('FieldMatchAny on a declared string column', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(
            must: [
              FieldMatchAny(key: 'lang', values: ['fr', 'de']),
            ],
          ),
        );
        expect(results.map((r) => r.id).toSet(), {'fr2020'});
      });

      test('bool column filters via mustNot', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(
            mustNot: [FieldEquals(key: 'archived', value: true)],
          ),
        );
        expect(results.map((r) => r.id).toSet(), {'en2020', 'fr2020'});
      });

      test('mustNot with TWO conditions excludes if EITHER matches', () async {
        // Regression test for the AND/OR mustNot bug: a row must be excluded if
        // it matches ANY mustNot condition (NOT (A OR B)), not only if it
        // matches ALL of them (the old buggy NOT (A AND B)).
        //   en2020: lang=en, year=2020 → matches neither → KEPT
        //   fr2020: lang=fr          → matches first    → excluded
        //   en1999: year=1999        → matches second   → excluded
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(
            mustNot: [
              FieldEquals(key: 'lang', value: 'fr'),
              FieldRange(key: 'year', lte: 1999.0),
            ],
          ),
        );
        // With the bug this would return all three rows.
        expect(results.map((r) => r.id).toSet(), {'en2020'});
      });

      test('must + should + mustNot combine', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(
            must: [FieldRange(key: 'year', gte: 2000.0)],
            should: [
              FieldEquals(key: 'lang', value: 'en'),
              FieldEquals(key: 'lang', value: 'fr'),
            ],
            mustNot: [FieldEquals(key: 'archived', value: true)],
          ),
        );
        expect(results.map((r) => r.id).toSet(), {'en2020', 'fr2020'});
      });

      test('undeclared-key filter is a no-op (never throws)', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 10,
          filter: const Filter(
            must: [FieldEquals(key: 'not_declared', value: 'x')],
          ),
        );
        // No declared column → filter contributes nothing → all rows returned.
        expect(results, hasLength(3));
      });

      test('metadata round-trips on the result', () async {
        await repo.initialize(dbPath);
        await seed();
        final results = await repo.searchSimilar(
          queryEmbedding: [1.0, 0.0, 0.0, 0.0],
          topK: 1,
        );
        expect(results.single.metadata, contains('"lang":"en"'));
      });
    });
  }, skip: skip);
}
