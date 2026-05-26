// Smoke test for QdrantEdgeClient — exercises the full FFI path end to
// end against the bundled native dylib on whatever device the test runs on.
//
// Run with:
//   cd example && flutter test integration_test/qdrant_client_smoke_test.dart -d macos

import 'dart:io';

import 'package:flutter_gemma/core/qdrant/filter_codec.dart';
import 'package:flutter_gemma/core/qdrant/point_id_hasher.dart';
import 'package:flutter_gemma/core/qdrant/qdrant_edge_client.dart';
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
        '${base.path}/qdrant_smoke_${DateTime.now().microsecondsSinceEpoch}');
  });

  tearDown(() async {
    if (shardDir.existsSync()) {
      shardDir.deleteSync(recursive: true);
    }
  });

  test('open + version', () async {
    final client = await QdrantEdgeClient.open(
      path: shardDir.path,
      dim: 4,
    );
    addTearDown(client.close);

    final v = client.version();
    expect(v, contains('qdrant-edge-ffi'));
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
    final filterJson = FilterCodec.encode(const Filter(
      must: [
        FieldEquals(key: 'lang', value: 'en'),
        FieldRange(key: 'price', gte: 200.0, lte: 1000.0),
      ],
    ));
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
}
