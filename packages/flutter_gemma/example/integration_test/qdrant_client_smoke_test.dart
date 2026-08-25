// Smoke test for QdrantEdgeClient — exercises the full FFI path end to
// end against the bundled native dylib on whatever device the test runs on.
//
// Run with:
//   cd example && flutter test integration_test/qdrant_client_smoke_test.dart -d macos

import 'dart:io';

import 'package:flutter_gemma_rag_qdrant/src/filter_codec.dart';
import 'package:flutter_gemma_rag_qdrant/src/point_id_hasher.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_vector_store.dart';
import 'package:flutter_gemma/core/services/vector_store_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory shardDir;

  setUp(() async {
    final base = await getApplicationSupportDirectory();
    shardDir = Directory(
      '${base.path}/qdrant_smoke_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    if (shardDir.existsSync()) {
      shardDir.deleteSync(recursive: true);
    }
  });

  test('open + empty count', () async {
    final client = await QdrantEdgeClient.open(path: shardDir.path, dim: 4);
    addTearDown(client.close);

    expect(await client.count(), equals(0));
  });

  test('upsert + count + search exact match', () async {
    final client = await QdrantEdgeClient.open(path: shardDir.path, dim: 4);
    addTearDown(client.close);

    await client.upsert(
      id: PointIdHasher.hash('doc_a'),
      vector: [0.95, 0.10, 0.10, 0.10],
      payload: {'tag': 'target', 'price': 999.0},
    );
    await client.upsert(
      id: PointIdHasher.hash('doc_b'),
      vector: [0.05, 0.95, 0.10, 0.10],
      payload: {'tag': 'other', 'price': 50.0},
    );
    expect(await client.count(), equals(2));

    final hits = await client.search(
      queryVector: [0.95, 0.10, 0.10, 0.10],
      topK: 5,
    );
    expect(hits, hasLength(2));
    expect(hits.first.id, equals(PointIdHasher.hash('doc_a')));
    expect(hits.first.score, greaterThan(0.9));
    expect(hits.first.payload?['tag'], equals('target'));
  });

  test('batch upsert + filtered search', () async {
    final client = await QdrantEdgeClient.open(path: shardDir.path, dim: 4);
    addTearDown(client.close);

    await client.upsertBatch([
      (
        id: PointIdHasher.hash('a'),
        vector: [0.95, 0.10, 0.10, 0.10],
        payload: {'lang': 'en', 'price': 250.0},
      ),
      (
        id: PointIdHasher.hash('b'),
        vector: [0.90, 0.20, 0.10, 0.10],
        payload: {'lang': 'fr', 'price': 100.0},
      ),
      (
        id: PointIdHasher.hash('c'),
        vector: [0.85, 0.30, 0.10, 0.10],
        payload: {'lang': 'en', 'price': 500.0},
      ),
    ]);
    expect(await client.count(), equals(3));

    // Filter: english docs priced 200-1000.
    final filterJson = FilterCodec.encode(
      const Filter(
        must: [
          FieldEquals(key: 'lang', value: 'en'),
          FieldRange(key: 'price', gte: 200.0, lte: 1000.0),
        ],
      ),
      FilterSchema(
        fields: [
          FilterField(name: 'lang', type: FilterFieldType.string),
          FilterField(name: 'price', type: FilterFieldType.number),
        ],
      ),
    );
    expect(filterJson, isNotNull);

    final hits = await client.search(
      queryVector: [0.95, 0.10, 0.10, 0.10],
      topK: 5,
      filterJson: filterJson,
    );
    final ids = hits.map((h) => h.id).toSet();
    expect(ids, contains(PointIdHasher.hash('a')));
    expect(ids, contains(PointIdHasher.hash('c')));
    expect(ids, isNot(contains(PointIdHasher.hash('b')))); // wrong lang
  });

  test('delete + persistence across close/reopen', () async {
    final c1 = await QdrantEdgeClient.open(path: shardDir.path, dim: 4);
    await c1.upsertBatch([
      (id: PointIdHasher.hash('p1'), vector: [1, 0, 0, 0], payload: null),
      (id: PointIdHasher.hash('p2'), vector: [0, 1, 0, 0], payload: null),
      (id: PointIdHasher.hash('p3'), vector: [0, 0, 1, 0], payload: null),
    ]);
    expect(await c1.count(), equals(3));
    await c1.delete([PointIdHasher.hash('p2')]);
    expect(await c1.count(), equals(2));
    await c1.close();

    // Reopen — points should persist.
    final c2 = await QdrantEdgeClient.open(path: shardDir.path, dim: 4);
    addTearDown(c2.close);
    expect(await c2.count(), equals(2));
  });

  // ---------------------------------------------------------------------
  // QdrantVectorStore — the layer the 2.0 migration actually rewrote, and
  // the one every fix in this release lives in. Until these were added, no
  // test touched it on a real device on any of the eight shipped platforms:
  // the cases above drive QdrantEdgeClient directly.
  // ---------------------------------------------------------------------

  List<double> vec(int dim, double seed) => List<double>.filled(dim, seed);

  test(
    'store: a reopened store reports its contents before any write',
    () async {
      final first = QdrantVectorStore();
      await first.initialize(shardDir.path);
      for (var i = 0; i < 3; i++) {
        await first.addDocument(
          id: 'doc$i',
          content: 'content $i',
          embedding: vec(4, i + 1.0),
        );
      }
      await first.close();

      // A second store on the same path stands in for an app restart. Before
      // 2.0's fix the client opened lazily on the first write, so this reported
      // zero documents and no hits over a fully populated index.
      final reopened = QdrantVectorStore();
      await reopened.initialize(shardDir.path);
      addTearDown(reopened.close);

      expect((await reopened.getStats()).documentCount, equals(3));
      expect(
        await reopened.searchSimilar(queryEmbedding: vec(4, 1), topK: 5),
        isNotEmpty,
      );
    },
  );

  test('store: concurrent addDocument calls do not race the WAL lock', () async {
    // Indexing a corpus with Future.wait is the obvious thing to write. Before
    // the fix both callers opened the same shard, qdrant holds the WAL
    // exclusively, and the loser failed with Kind(WouldBlock) — losing a
    // document. Worth running on device: the failure is timing-dependent and
    // storage there is slower than a dev box.
    final store = QdrantVectorStore();
    await store.initialize(shardDir.path);
    addTearDown(store.close);

    await Future.wait([
      for (var i = 0; i < 8; i++)
        store.addDocument(
          id: 'doc$i',
          content: 'content $i',
          embedding: vec(4, i + 1.0),
        ),
    ]);

    expect((await store.getStats()).documentCount, equals(8));
  });

  test('store: a 1.x layout is refused, and clear() removes it', () async {
    // A store written by 1.x sits directly at databasePath; 2.0 only opens its
    // owned subdir. Undetected it comes up empty with no error and the old
    // corpus keeps its disk. On device this is the case that would silently
    // cost a user their index on upgrade.
    shardDir.createSync(recursive: true);
    File('${shardDir.path}/edge_config.json').writeAsStringSync('{}');
    Directory('${shardDir.path}/wal').createSync();
    Directory('${shardDir.path}/segments').createSync();
    File('${shardDir.path}/user_file.txt').writeAsStringSync('keep me');

    final store = QdrantVectorStore();
    await store.initialize(shardDir.path);
    addTearDown(store.close);

    await expectLater(
      store.addDocument(id: 'x', content: 'y', embedding: vec(4, 1)),
      throwsA(isA<Exception>()),
    );

    await store.clear();
    expect(File('${shardDir.path}/edge_config.json').existsSync(), isFalse);
    expect(File('${shardDir.path}/user_file.txt').existsSync(), isTrue);

    // ...and the store is usable again afterwards.
    await store.addDocument(id: 'a', content: 'b', embedding: vec(4, 1));
    expect((await store.getStats()).documentCount, equals(1));
  });
}
