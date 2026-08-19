// One filter, one document set, two stores — the same answer, or a failure.
//
// WHY THIS FILE EXISTS
//
// The two RAG backends are supposed to be interchangeable: `VectorStoreRepository`
// promises the same `Filter` means the same thing on sqlite-vec/vec0 and on
// qdrant-edge. Three review passes over PR #442 found nine ways that was false,
// and every one of them was invisible to the tests that existed, for one reason:
//
//   the tests compared each codec's OUTPUT to a string in the same file.
//
// `filter_to_vec0_test.dart` asserts generated SQL. `filter_codec_test.dart`
// asserts JSON shape. Both are restatements of their own implementation, so a
// codec and its test can be wrong together and stay green forever — and both
// were. Worse, neither package's tests could even see the other backend, so
// "parity" was a word in a group name, not a thing being checked.
//
// This file asserts on ROWS returned by both REAL stores. It cannot pass by
// agreeing with a comment.
//
// HOW BOTH BACKENDS GET HERE
//
// qdrant-edge needs no local Rust build and no environment variable. Its dylib
// arrives exactly the way LiteRT's does: flutter_gemma_rag_qdrant's
// `hook/build.dart` downloads the release archive, verifies its SHA256 and
// caches it, and Native Assets links it into whichever package is under test —
// this package dev-depends on rag_qdrant, so `flutter test` here resolves it
// like any other native asset. An earlier draft of this file reached for
// $QDRANT_DYLIB and a cargo target path; that was solving a problem the hook
// had already solved.
//
// vec0 is the one that still needs $VEC0_DYLIB, because SqliteVectorStore
// resolves it as `vec0.framework/vec0` — a path that exists only inside a built
// app. tool/test_all.sh exports it; vec0_locator.dart is the gate.
//
// If qdrant does NOT initialize, this file fails rather than skipping. That is
// the point: three review passes found nine cross-backend defects, every one of
// them invisible because no test ran both stores, and a suite that silently
// checks half of what it claims is the very defect it exists to catch.
//
//   flutter test test/cross_backend_parity_test.dart
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qdrant_locator.dart';
import 'vec0_locator.dart';

/// One document: an id and the metadata JSON it carries.
typedef Doc = ({String id, String metadata});

/// One row of the table: a filter, and the ids both stores must return.
typedef Case = ({String name, Filter filter, List<String> expected});

/// Declared once for every case, so a divergence cannot be blamed on the
/// schema differing between the two stores.
final schema = FilterSchema(
  fields: [
    FilterField(name: 'lang', type: FilterFieldType.string),
    FilterField(name: 'price', type: FilterFieldType.number),
    FilterField(name: 'archived', type: FilterFieldType.bool),
  ],
);

/// The corpus. Deliberately heterogeneous — a field missing here, a value of
/// the wrong type there — because that is where the two backends came apart,
/// not on well-formed rows.
const docs = <Doc>[
  (id: 'en_cheap', metadata: '{"lang":"en","price":10,"archived":false}'),
  (id: 'fr_dear', metadata: '{"lang":"fr","price":90,"archived":false}'),
  (id: 'de_arch', metadata: '{"lang":"de","price":50,"archived":true}'),
  // archived written as 1 rather than true — the same document to a reader,
  // and two different payload variants to qdrant.
  (id: 'es_arch1', metadata: '{"lang":"es","price":50,"archived":1}'),
  // No `price` at all. The normal RAG case, and the one that could not even be
  // inserted before absent-value sentinels.
  (id: 'no_price', metadata: '{"lang":"it","archived":false}'),
  // A price that is not a number. sqlite cannot store it; qdrant keeps it.
  (id: 'str_price', metadata: '{"lang":"pt","price":"cheap","archived":false}'),
];

final cases = <Case>[
  (
    name: 'equality on a string field',
    filter: const Filter(
      must: [FieldEquals(key: 'lang', value: 'en')],
    ),
    expected: ['en_cheap'],
  ),
  (
    name: 'equality compares numbers by value, not by JSON spelling',
    // 50 and 50.0 are the same number; a store must not disagree.
    filter: const Filter(must: [FieldEquals(key: 'price', value: 50.0)]),
    expected: ['de_arch', 'es_arch1'],
  ),
  (
    name: 'a missing field never satisfies a condition',
    filter: const Filter(must: [FieldRange(key: 'price', gte: 0)]),
    expected: ['en_cheap', 'fr_dear', 'de_arch', 'es_arch1'],
  ),
  (
    name: 'mustNot RETURNS the document that lacks the field',
    // The rule core documents: must excludes it, mustNot keeps it.
    filter: const Filter(mustNot: [FieldRange(key: 'price', gte: 60)]),
    expected: ['en_cheap', 'de_arch', 'es_arch1', 'no_price', 'str_price'],
  ),
  (
    name: 'both JSON spellings of a bool are one value',
    filter: const Filter(must: [FieldEquals(key: 'archived', value: true)]),
    expected: ['de_arch', 'es_arch1'],
  ),
  (
    name: 'a value that cannot inhabit the declared type matches nothing',
    // qdrant used to match str_price here and sqlite did not.
    filter: const Filter(
      must: [FieldEquals(key: 'price', value: 'cheap')],
    ),
    expected: [],
  ),
  (
    name: 'a non-bool-ish number is not a bool',
    // `value == 1` made 2 mean false, matching every unarchived document.
    filter: const Filter(must: [FieldEquals(key: 'archived', value: 2)]),
    expected: [],
  ),
  (
    name: 'set membership over a string field',
    filter: const Filter(
      must: [
        FieldMatchAny(key: 'lang', values: ['en', 'de']),
      ],
    ),
    expected: ['en_cheap', 'de_arch'],
  ),
  (
    name: 'set membership over a number field',
    filter: const Filter(
      must: [
        FieldMatchAny(key: 'price', values: [10, 90]),
      ],
    ),
    expected: ['en_cheap', 'fr_dear'],
  ),
  (
    name: 'an off-type member of a set is dropped, not matched',
    filter: const Filter(
      must: [
        FieldMatchAny(key: 'price', values: ['cheap', 10]),
      ],
    ),
    expected: ['en_cheap'],
  ),
  (
    name: 'an undeclared key is a no-op, not a narrowing',
    filter: const Filter(
      must: [
        FieldEquals(key: 'lang', value: 'en'),
        FieldEquals(key: 'nosuchfield', value: 'x'),
      ],
    ),
    expected: ['en_cheap'],
  ),
  (
    name: 'an undeclared key in should does not narrow either',
    filter: const Filter(
      should: [
        FieldEquals(key: 'lang', value: 'en'),
        FieldEquals(key: 'nosuchfield', value: 'x'),
      ],
    ),
    expected: ['en_cheap'],
  ),
  (
    name: 'an unbounded range constrains nothing',
    filter: const Filter(
      must: [
        FieldEquals(key: 'lang', value: 'en'),
        FieldRange(key: 'price'),
      ],
    ),
    expected: ['en_cheap'],
  ),
  (
    name: 'an always-true arm makes the whole should bucket true',
    filter: const Filter(
      should: [
        FieldEquals(key: 'lang', value: 'en'),
        FieldRange(key: 'price'),
      ],
    ),
    expected: [
      'en_cheap',
      'fr_dear',
      'de_arch',
      'es_arch1',
      'no_price',
      'str_price',
    ],
  ),
  (
    name: 'an ignored range on a string field is skipped in should',
    filter: const Filter(
      should: [
        FieldEquals(key: 'lang', value: 'en'),
        FieldRange(key: 'lang', gte: 1),
      ],
    ),
    expected: ['en_cheap'],
  ),
  (
    name: 'an empty set matches nothing',
    filter: const Filter(
      must: [FieldMatchAny(key: 'lang', values: [])],
    ),
    expected: [],
  ),
  (
    name: 'excluding an empty set excludes nothing',
    filter: const Filter(
      mustNot: [FieldMatchAny(key: 'lang', values: [])],
    ),
    expected: [
      'en_cheap',
      'fr_dear',
      'de_arch',
      'es_arch1',
      'no_price',
      'str_price',
    ],
  ),
  (
    name: 'mustNot over a set',
    filter: const Filter(
      mustNot: [
        FieldMatchAny(key: 'lang', values: ['en', 'fr']),
      ],
    ),
    expected: ['de_arch', 'es_arch1', 'no_price', 'str_price'],
  ),
  (
    name: 'must and mustNot compose',
    filter: const Filter(
      must: [FieldRange(key: 'price', gte: 10, lte: 90)],
      mustNot: [FieldEquals(key: 'lang', value: 'fr')],
    ),
    expected: ['en_cheap', 'de_arch', 'es_arch1'],
  ),
];

/// A vector that is the same for every document, so distance never decides the
/// result set and any difference is the filter's doing.
final embedding = List<double>.filled(4, 0.5);

void main() {
  final vec0Skip = vec0SkipReason;

  group('cross-backend filter parity', () {
    late Directory tmp;
    late SqliteVectorStore sqlite;
    QdrantVectorStore? qdrant;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('parity_');

      sqlite = SqliteVectorStore();
      sqlite.configure(schema);
      await sqlite.initialize('${tmp.path}/vec.db');

      // Pointed at the file the HOOK downloaded — see qdrant_locator.dart.
      // Outside a built app the client cannot resolve its own bundled name,
      // the same gap vec0 has.
      // ignore: invalid_use_of_visible_for_testing_member
      QdrantEdgeClient.debugOverrideDylibPath = qdrantPath;
      final q = QdrantVectorStore();
      q.configure(schema);
      await q.initialize('${tmp.path}/shard');
      qdrant = q;

      for (final doc in docs) {
        await sqlite.addDocument(
          id: doc.id,
          content: doc.id,
          embedding: embedding,
          metadata: doc.metadata,
        );
        await qdrant?.addDocument(
          id: doc.id,
          content: doc.id,
          embedding: embedding,
          metadata: doc.metadata,
        );
      }
    });

    tearDown(() async {
      await sqlite.close();
      await qdrant?.close();
      qdrant = null;
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<List<String>> ids(VectorStoreRepository store, Filter f) async {
      final hits = await store.searchSimilar(
        queryEmbedding: embedding,
        topK: docs.length,
        filter: f,
      );
      return hits.map((h) => h.id).toList()..sort();
    }

    for (final c in cases) {
      test(c.name, () async {
        final want = [...c.expected]..sort();

        // The sqlite half always runs, so the table is asserted even on a
        // machine without the qdrant dylib.
        expect(await ids(sqlite, c.filter), want, reason: 'sqlite-vec');

        final q = qdrant;
        if (q == null) return;
        expect(await ids(q, c.filter), want, reason: 'qdrant-edge');
      });
    }
  }, skip: vec0Skip);

  // Not a decoration. Three review passes found nine cross-backend defects, and
  // the reason none was caught earlier is that no test ran both stores. So the
  // file states, as an assertion rather than as a comment, that both halves
  // actually executed.
  //
  // The qdrant half needs no guard of its own: setUp initializes the store
  // unconditionally, so a missing native asset fails every case above. This
  // covers the other half — vec0, which really can be absent, and whose absence
  // would otherwise skip the group and leave the file looking green.
  test('both backends were actually exercised', () {
    expect(
      vec0SkipReason,
      isNull,
      reason:
          'the sqlite-vec half did not run, so nothing in this file was '
          'compared across backends: $vec0SkipReason',
    );
    expect(
      qdrantSkipReason,
      isNull,
      reason:
          'the qdrant half did not run, so nothing in this file was compared '
          'across backends: $qdrantSkipReason',
    );
  });
}
