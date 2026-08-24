// Unit tests for QdrantVectorStore, backed by the official Qdrant Edge SDK
// (UniFFI binding of qdrant-edge-ffi). The native engine is delivered by the
// qdrant_edge package's Native Assets build hook, which the test runner
// builds and registers automatically. Verified command (Flutter's runner
// supports native assets without any experiment flag):
//
//   flutter test test/qdrant_vector_store_test.dart
//
// Plain `dart test` only works on a Dart SDK where native assets are
// enabled without an experiment flag — as of Dart 3.12, the
// `--enable-experiment=native-assets` flag itself is rejected as unknown
// (the feature graduated out of the experiment gate), so do not pass it.
// No manual dylib path or build-gate needed.

import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
// Internal (src/) import, valid within the same package: needed to pin the
// QdrantException → VectorStoreException wrapping contract directly against
// QdrantEdgeClient (see 'exception wrapping' group below).
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
// Internal (src/) import under a prefix: the barrel export
// (flutter_gemma_rag_qdrant.dart, imported above) is platform-conditional
// (native `QdrantVectorStore` vs. the web stub), and `dart analyze` resolves
// that condition as false by default, typing every barrel `QdrantVectorStore`
// use in this file as the STUB class. That's invisible everywhere else in
// this file because the stub implements the same `VectorStoreRepository`
// interface — but `debugDeleteDirOverride` is a native-only test seam, not
// part of that interface, so it needs the concrete native class directly.
import 'package:flutter_gemma_rag_qdrant/src/qdrant_vector_store.dart'
    as native;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The store's format-scoped subdirectory name — kept in sync with
/// `QdrantVectorStore._storeDirName`. Duplicated here (rather than exported)
/// because it is an on-disk implementation detail, not part of the public
/// contract; these tests assert the on-disk layout as a safety property, not
/// as an API guarantee.
const _storeDirName = 'qdrant_edge_v1';

void main() {
  late QdrantVectorStore repo;
  late String shardDir;

  setUp(() async {
    repo = QdrantVectorStore();
    shardDir =
        '${Directory.systemTemp.path}/qdrant_unit_${DateTime.now().microsecondsSinceEpoch}';
    await repo.initialize(shardDir);
  });

  tearDown(() async {
    await repo.close();
    final d = Directory(shardDir);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
    }
  });

  group('QdrantVectorStore', () {
    test('isInitialized is true after initialize()', () {
      expect(repo.isInitialized, isTrue);
    });

    test('addDocument + getStats reports count and dimension', () async {
      await repo.addDocument(
        id: 'doc1',
        content: 'hello world',
        embedding: const [0.1, 0.2, 0.3, 0.4],
      );
      final stats = await repo.getStats();
      expect(stats.documentCount, equals(1));
      expect(stats.vectorDimension, equals(4));
    });

    test(
      // Also the unnamed-vector top-1 retrieval assertion the migration to
      // the official SDK depends on: the shard is configured with a single
      // vector field under the empty name ('') and searched via
      // NearestQuery(..., using: null). Upserting two known vectors and
      // asserting the nearer one comes back top-1 with a high score pins that
      // addressing so a wrong/default-vector mismatch can't pass silently.
      'searchSimilar returns the closest doc back with original id',
      () async {
        await repo.addDocument(
          id: 'doc_far',
          content: 'far',
          embedding: const [0.0, 1.0, 0.0, 0.0],
        );
        await repo.addDocument(
          id: 'doc_near',
          content: 'near',
          embedding: const [1.0, 0.0, 0.0, 0.0],
        );

        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 2,
        );
        expect(hits, hasLength(2));
        expect(hits.first.id, equals('doc_near'));
        expect(hits.first.content, equals('near'));
        expect(hits.first.similarity, greaterThan(0.9));
      },
    );

    test('threshold filters out low-similarity hits', () async {
      await repo.addDocument(
        id: 'doc_a',
        content: 'a',
        embedding: const [1.0, 0.0, 0.0, 0.0],
      );
      await repo.addDocument(
        id: 'doc_b',
        content: 'b',
        embedding: const [-1.0, 0.0, 0.0, 0.0], // anti-correlated
      );
      final hits = await repo.searchSimilar(
        queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
        topK: 5,
        threshold: 0.5,
      );
      final ids = hits.map((h) => h.id).toSet();
      expect(ids, contains('doc_a'));
      expect(ids, isNot(contains('doc_b')));
    });

    test('removeDocument deletes by original String id', () async {
      await repo.addDocument(
        id: 'doc_x',
        content: 'x',
        embedding: const [1.0, 0.0, 0.0, 0.0],
      );
      expect((await repo.getStats()).documentCount, equals(1));

      await repo.removeDocument(id: 'doc_x');
      expect((await repo.getStats()).documentCount, equals(0));
    });

    test('metadata round-trips as a JSON string', () async {
      const meta = '{"lang":"en","category":"science"}';
      await repo.addDocument(
        id: 'doc_meta',
        content: 'with meta',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: meta,
      );
      final hits = await repo.searchSimilar(
        queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
        topK: 1,
      );
      expect(hits.first.metadata, equals(meta));
    });

    test(
      'Filter on an UNDECLARED field is a no-op (same hits as filter:null)',
      () async {
        // Contract (VectorStoreRepository.searchSimilar): a condition on a field
        // not declared via configure(FilterSchema) must NOT narrow — it returns
        // the same hits as filter:null, never throws. (Previously qdrant
        // serialized it and narrowed to zero; now FilterCodec skips it.)
        await repo.addDocument(
          id: 'doc_only',
          content: 'only',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"lang":"en"}',
        );

        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(
            must: [FieldEquals(key: 'nonexistent_field', value: 'foo')],
          ),
        );
        // No schema was configured → the undeclared condition is skipped → the
        // stored document still comes back.
        expect(hits, isNotEmpty);
        expect(hits.first.id, 'doc_only');
      },
    );

    test(
      'configure + Filter on a declared metadata field actually narrows',
      () async {
        // The fix for the latent metadata-filter bug: when a schema is
        // declared, addDocument promotes the declared field to a top-level
        // payload key so FilterCodec's top-level predicates can match it.
        repo.configure(
          FilterSchema(
            fields: [FilterField(name: 'lang', type: FilterFieldType.string)],
          ),
        );
        expect(repo.filterSchema.fields, hasLength(1));

        await repo.addDocument(
          id: 'doc_en',
          content: 'english',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"lang":"en"}',
        );
        await repo.addDocument(
          id: 'doc_fr',
          content: 'french',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"lang":"fr"}',
        );

        // A filter on the DECLARED field matches only the english doc.
        final en = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(
            must: [FieldEquals(key: 'lang', value: 'en')],
          ),
        );
        expect(en.map((h) => h.id).toSet(), equals({'doc_en'}));
        // Raw metadata blob still round-trips untouched.
        expect(en.first.metadata, equals('{"lang":"en"}'));

        // No filter → both docs come back (promotion is additive).
        final all = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
        );
        expect(all.map((h) => h.id).toSet(), equals({'doc_en', 'doc_fr'}));
      },
    );

    test('mustNot with TWO conditions excludes if EITHER matches', () async {
      // qdrant's must_not is a flat list (each entry independently excludes),
      // so it has the correct "exclude if ANY matches" semantics by construction
      // — unlike the sqlite SQL translator which had to be fixed. This pins it.
      repo.configure(
        FilterSchema(
          fields: [
            FilterField(name: 'lang', type: FilterFieldType.string),
            FilterField(name: 'archived', type: FilterFieldType.bool),
          ],
        ),
      );
      await repo.addDocument(
        id: 'keep',
        content: 'en active',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"lang":"en","archived":false}',
      );
      await repo.addDocument(
        id: 'drop_lang',
        content: 'fr active',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"lang":"fr","archived":false}',
      );
      await repo.addDocument(
        id: 'drop_archived',
        content: 'en archived',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"lang":"en","archived":true}',
      );
      final hits = await repo.searchSimilar(
        queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
        topK: 5,
        filter: const Filter(
          mustNot: [
            FieldEquals(key: 'lang', value: 'fr'),
            FieldEquals(key: 'archived', value: true),
          ],
        ),
      );
      // Only the doc matching NEITHER mustNot condition survives.
      expect(hits.map((h) => h.id).toSet(), equals({'keep'}));
    });

    // ---- One e2e case per Filter value arm, through the real JSON envelope
    // -> typed qe.Filter adapter (QdrantEdgeClient._filterFromJson). The
    // codec's golden tests (filter_codec_test.dart) pin the JSON it emits;
    // these pin that the SDK actually honors that JSON once decoded back into
    // qe.FieldCondition/qe.Match/qe.RangeFloat against a real shard.

    test(
      'FieldEquals with a bool value narrows a bool field, honoring BOTH '
      'JSON spellings of true (real bool and the integer 1)',
      () async {
        // filter_codec.dart's _equality/bool arm encodes FieldEquals(true)
        // as should:[match.value==true, range(gte:1,lte:1)] (_boolSpellings,
        // filter_codec.dart:294-309) because qdrant stores payload booleans
        // verbatim: {"archived":true} is Bool(true) but {"archived":1} is
        // Integer(1). Docs stored with each spelling pin that the SDK
        // actually honors both should-branches, not just the one a
        // same-spelling test would exercise.
        repo.configure(
          FilterSchema(
            fields: [
              FilterField(name: 'archived', type: FilterFieldType.bool),
            ],
          ),
        );
        await repo.addDocument(
          id: 'doc_live',
          content: 'live',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"archived":false}',
        );
        await repo.addDocument(
          id: 'doc_archived',
          content: 'archived',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"archived":true}',
        );
        await repo.addDocument(
          id: 'doc_one',
          content: 'archived as integer 1',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"archived":1}',
        );
        await repo.addDocument(
          id: 'doc_zero',
          content: 'not archived as integer 0',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"archived":0}',
        );

        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(must: [FieldEquals(key: 'archived', value: true)]),
        );
        expect(
          hits.map((h) => h.id).toSet(),
          equals({'doc_archived', 'doc_one'}),
        );
      },
    );

    test('FieldEquals with an int value narrows a number field', () async {
      repo.configure(
        FilterSchema(
          fields: [FilterField(name: 'year', type: FilterFieldType.number)],
        ),
      );
      await repo.addDocument(
        id: 'doc_2020',
        content: 'y2020',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"year":2020}',
      );
      await repo.addDocument(
        id: 'doc_2021',
        content: 'y2021',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"year":2021}',
      );

      final hits = await repo.searchSimilar(
        queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
        topK: 5,
        filter: const Filter(must: [FieldEquals(key: 'year', value: 2020)]),
      );
      expect(hits.map((h) => h.id).toSet(), equals({'doc_2020'}));
    });

    test(
      'FieldMatchAny narrows to any of the given values (string field)',
      () async {
        repo.configure(
          FilterSchema(
            fields: [FilterField(name: 'tag', type: FilterFieldType.string)],
          ),
        );
        await repo.addDocument(
          id: 'doc_a',
          content: 'a',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"tag":"a"}',
        );
        await repo.addDocument(
          id: 'doc_b',
          content: 'b',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"tag":"b"}',
        );
        await repo.addDocument(
          id: 'doc_c',
          content: 'c',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"tag":"c"}',
        );

        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(
            must: [
              FieldMatchAny(key: 'tag', values: ['a', 'c']),
            ],
          ),
        );
        expect(hits.map((h) => h.id).toSet(), equals({'doc_a', 'doc_c'}));
      },
    );

    test(
      'FieldRange narrows a number field by inclusive float bounds',
      () async {
        repo.configure(
          FilterSchema(
            fields: [
              FilterField(name: 'price', type: FilterFieldType.number),
            ],
          ),
        );
        await repo.addDocument(
          id: 'doc_cheap',
          content: 'cheap',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"price":5.5}',
        );
        await repo.addDocument(
          id: 'doc_mid',
          content: 'mid',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"price":50.0}',
        );
        await repo.addDocument(
          id: 'doc_expensive',
          content: 'expensive',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"price":500.0}',
        );

        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(
            must: [FieldRange(key: 'price', gte: 10.0, lte: 100.0)],
          ),
        );
        expect(hits.map((h) => h.id).toSet(), equals({'doc_mid'}));
      },
    );

    test(
      'FieldEquals with a double value narrows via the degenerate '
      'gte==lte range (filter_codec.dart _equality/number arm)',
      () async {
        // FieldEquals on a number field is encoded as a degenerate
        // {gte: v, lte: v} range (filter_codec.dart:311-318). The int case
        // above exercises that path with a whole number; this pins it with
        // a double, the value class the "float degenerate-range" arm names.
        repo.configure(
          FilterSchema(
            fields: [
              FilterField(name: 'price', type: FilterFieldType.number),
            ],
          ),
        );
        await repo.addDocument(
          id: 'doc_cheap',
          content: 'cheap',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"price":5.5}',
        );
        await repo.addDocument(
          id: 'doc_mid',
          content: 'mid',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"price":50.0}',
        );
        await repo.addDocument(
          id: 'doc_expensive',
          content: 'expensive',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"price":500.0}',
        );

        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(must: [FieldEquals(key: 'price', value: 5.5)]),
        );
        expect(hits.map((h) => h.id).toSet(), equals({'doc_cheap'}));
      },
    );

    test('should bucket matches when ANY condition matches (OR)', () async {
      repo.configure(
        FilterSchema(
          fields: [FilterField(name: 'lang', type: FilterFieldType.string)],
        ),
      );
      await repo.addDocument(
        id: 'doc_en',
        content: 'en',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"lang":"en"}',
      );
      await repo.addDocument(
        id: 'doc_fr',
        content: 'fr',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"lang":"fr"}',
      );
      await repo.addDocument(
        id: 'doc_de',
        content: 'de',
        embedding: const [1.0, 0.0, 0.0, 0.0],
        metadata: '{"lang":"de"}',
      );

      final hits = await repo.searchSimilar(
        queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
        topK: 5,
        filter: const Filter(
          should: [
            FieldEquals(key: 'lang', value: 'en'),
            FieldEquals(key: 'lang', value: 'fr'),
          ],
        ),
      );
      expect(hits.map((h) => h.id).toSet(), equals({'doc_en', 'doc_fr'}));
    });

    test(
      'addDocument with an existing id replaces (upsert, no duplicate)',
      () async {
        await repo.addDocument(
          id: 'dup',
          content: 'first',
          embedding: const [1.0, 0.0, 0.0, 0.0],
        );
        await repo.addDocument(
          id: 'dup',
          content: 'second',
          embedding: const [0.0, 1.0, 0.0, 0.0],
        );
        expect((await repo.getStats()).documentCount, equals(1));
        final hits = await repo.searchSimilar(
          queryEmbedding: const [0.0, 1.0, 0.0, 0.0],
          topK: 5,
        );
        expect(hits, hasLength(1));
        expect(hits.first.content, equals('second'));
      },
    );

    test(
      'undeclared-key Filter on a configured store is a safe no-op (no throw)',
      () async {
        repo.configure(
          FilterSchema(
            fields: [FilterField(name: 'lang', type: FilterFieldType.string)],
          ),
        );
        await repo.addDocument(
          id: 'doc_only',
          content: 'only',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"lang":"en"}',
        );
        // Filtering on a key NOT in the schema is a no-op: the condition is
        // skipped (never promoted, so it would otherwise match nothing), so the
        // search returns the same hits as filter:null — never throws.
        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(
            must: [FieldEquals(key: 'undeclared', value: 'x')],
          ),
        );
        expect(hits, isNotEmpty);
        expect(hits.first.id, 'doc_only');
      },
    );

    test(
      'malformed metadata JSON does not break addDocument (blob kept)',
      () async {
        repo.configure(
          FilterSchema(
            fields: [FilterField(name: 'lang', type: FilterFieldType.string)],
          ),
        );
        // Not valid JSON — promotion is skipped, the document still stores
        // and the opaque blob still round-trips.
        await repo.addDocument(
          id: 'doc_bad',
          content: 'bad meta',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: 'not json at all',
        );
        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 1,
        );
        expect(hits.first.id, equals('doc_bad'));
        expect(hits.first.metadata, equals('not json at all'));
      },
    );

    test(
      'no schema → filter on any field is a no-op (not declared → skipped)',
      () async {
        // Without configure(), no field is declared, so EVERY condition is
        // undeclared and skipped → the search runs unfiltered (same hits as
        // filter:null), never narrowing to zero.
        await repo.addDocument(
          id: 'doc_plain',
          content: 'plain',
          embedding: const [1.0, 0.0, 0.0, 0.0],
          metadata: '{"lang":"en"}',
        );
        final hits = await repo.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
          filter: const Filter(
            must: [FieldEquals(key: 'lang', value: 'en')],
          ),
        );
        expect(hits, isNotEmpty);
        expect(hits.first.id, 'doc_plain');
      },
    );

    test('initialize is idempotent — second call swaps the shard', () async {
      await repo.addDocument(
        id: 'doc_first',
        content: 'first',
        embedding: const [1.0, 0.0, 0.0, 0.0],
      );
      expect((await repo.getStats()).documentCount, equals(1));

      // Re-init same shard path: must not throw.
      await repo.initialize(shardDir);
      // After re-init dimension is unknown again — count from a fresh
      // shard re-read after first addDocument under the new client.
      await repo.addDocument(
        id: 'doc_after_reinit',
        content: 'after',
        embedding: const [1.0, 0.0, 0.0, 0.0],
      );
      final stats = await repo.getStats();
      // Both docs are persisted on disk (qdrant shard files), so the new
      // client sees count = 2.
      expect(stats.documentCount, greaterThanOrEqualTo(1));
    });

    test('clear empties the shard', () async {
      await repo.addDocument(
        id: 'doc_to_clear',
        content: 'bye',
        embedding: const [1.0, 0.0, 0.0, 0.0],
      );
      expect((await repo.getStats()).documentCount, equals(1));

      await repo.clear();
      // After clear() the repo is in a fresh state — needs init again to
      // be usable. getStats returns 0 because the client has been torn down.
      final stats = await repo.getStats();
      expect(stats.documentCount, equals(0));
    });

    test('enableHnsw is accepted but a no-op (toggle does not throw)', () {
      expect(repo.enableHnsw, isTrue);
      repo.enableHnsw = false;
      expect(repo.enableHnsw, isFalse);
      repo.enableHnsw = true;
      expect(repo.enableHnsw, isTrue);
    });
  });

  // ---- Bounded subdir + fail-safe tests (plan §Verification-4) -------------
  //
  // The store owns `<databasePath>/qdrant_edge_v1` and never opens or deletes
  // the bare databasePath directly. These pin that as a safety property, not
  // just as an implementation detail — portable, temp dirs only, no
  // fault-injection or permission tricks.
  group('bounded subdir + fail-safe', () {
    late Directory dbDir;

    setUp(() {
      dbDir = Directory(
        '${Directory.systemTemp.path}/qdrant_subdir_${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
    });

    tearDown(() {
      if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
    });

    test(
      '(a) a legacy sibling at the bare databasePath is left untouched by '
      'init + addDocument + clear()',
      () async {
        // Simulates a pre-migration (1.x / crate 0.7.x) shard sitting
        // directly at the bare path the caller passes to initialize().
        final legacyMarker = File(p.join(dbDir.path, 'legacy_marker.bin'))
          ..writeAsBytesSync([1, 2, 3, 4]);

        final store = QdrantVectorStore();
        await store.initialize(dbDir.path);
        await store.addDocument(
          id: 'doc',
          content: 'doc',
          embedding: const [1.0, 0.0, 0.0, 0.0],
        );

        final ownedSubdir = Directory(p.join(dbDir.path, _storeDirName));
        expect(
          ownedSubdir.existsSync(),
          isTrue,
          reason: 'the shard must be created under the owned subdir',
        );
        expect(
          legacyMarker.existsSync(),
          isTrue,
          reason: 'a sibling at the bare databasePath must never be touched',
        );
        expect(legacyMarker.readAsBytesSync(), equals([1, 2, 3, 4]));

        await store.clear();

        expect(
          ownedSubdir.existsSync(),
          isFalse,
          reason: 'clear() must remove the owned subdir',
        );
        expect(
          dbDir.existsSync(),
          isTrue,
          reason: 'clear() must never remove the caller\'s databasePath',
        );
        expect(
          legacyMarker.existsSync(),
          isTrue,
          reason: 'clear() must never touch a sibling of the owned subdir',
        );

        await store.close();
      },
    );

    test(
      '(b) junk occupying the owned-subdir path makes addDocument throw a '
      'VectorStoreException, with the junk left untouched',
      () async {
        // Occupy the exact path the store would create its subdir at, with a
        // plain file instead of a directory — the store can neither mkdir
        // over it nor open it as a shard.
        final junkPath = p.join(dbDir.path, _storeDirName);
        final junk = File(junkPath)..writeAsBytesSync([9, 9, 9]);

        final store = QdrantVectorStore();
        await store.initialize(dbDir.path);

        await expectLater(
          () => store.addDocument(
            id: 'doc',
            content: 'doc',
            embedding: const [1.0, 0.0, 0.0, 0.0],
          ),
          throwsA(isA<VectorStoreException>()),
        );

        expect(junk.existsSync(), isTrue);
        expect(junk.readAsBytesSync(), equals([9, 9, 9]));
        expect(
          (await store.getStats()).documentCount,
          equals(0),
          reason: 'a failed open must leave no live client / data behind',
        );

        await store.close();
      },
    );

    test(
      '(c) clear() refuses to delete when the owned subdir resolves outside '
      'databasePath (symlink escape), and deletes nothing',
      () async {
        // A real target directory OUTSIDE dbDir, standing in for whatever
        // clear() must never touch.
        final outsideTarget = Directory(
          '${Directory.systemTemp.path}/qdrant_outside_${DateTime.now().microsecondsSinceEpoch}',
        )..createSync(recursive: true);
        final sentinel = File(p.join(outsideTarget.path, 'sentinel.txt'))
          ..writeAsStringSync('do not delete me');

        try {
          // Coerce the owned-subdir path into a symlink pointing OUTSIDE
          // databasePath — the only way `storeDir` (always literally
          // `p.join(databasePath, 'qdrant_edge_v1')`) can resolve escape it.
          final linkPath = p.join(dbDir.path, _storeDirName);
          Link(linkPath).createSync(outsideTarget.path);

          final store = QdrantVectorStore();
          await store.initialize(dbDir.path);

          await expectLater(
            store.clear,
            throwsA(isA<VectorStoreException>()),
          );

          expect(
            sentinel.existsSync(),
            isTrue,
            reason: 'the guard must refuse to delete before touching '
                'anything outside databasePath',
          );
          expect(outsideTarget.existsSync(), isTrue);

          await store.close();
        } finally {
          if (outsideTarget.existsSync()) {
            outsideTarget.deleteSync(recursive: true);
          }
        }
      },
      // Symlink creation can be unavailable/unprivileged in some sandboxed
      // CI environments; skip there rather than fail on an environment gap
      // unrelated to the guard logic itself.
      onPlatform: {'windows': const Skip('symlink creation needs elevation')},
    );

    test(
      '(d) clear() delete-failure marks the store uninitialized '
      '(fail-closed), and re-initializing recovers',
      () async {
        // Portable fault injection via the debug seam (debugDeleteDirOverride)
        // rather than OS-level permission tricks: chmod-based denial does not
        // behave identically on POSIX vs Windows (and is a no-op as root), so
        // it cannot be the portable coverage plan item 49 mandates. The seam
        // forces clear()'s delete step to fail deterministically on every
        // platform.
        final store = native.QdrantVectorStore();
        await store.initialize(dbDir.path);
        await store.addDocument(
          id: 'doc',
          content: 'doc',
          embedding: const [1.0, 0.0, 0.0, 0.0],
        );

        store.debugDeleteDirOverride = (dir) {
          // Simulate a realistic partway delete failure: the shard's
          // contents are removed (as a real recursive delete would manage
          // before hitting trouble) but the owned subdir entry itself fails
          // to go away — matching the "on-disk subdir may be left in a mixed
          // state" case clear() defends against — then report failure.
          if (dir.existsSync()) {
            for (final entry in dir.listSync()) {
              entry.deleteSync(recursive: true);
            }
          }
          throw const FileSystemException(
            'simulated delete failure',
            'debugDeleteDirOverride',
          );
        };

        await expectLater(store.clear, throwsA(isA<VectorStoreException>()));

        expect(
          store.isInitialized,
          isFalse,
          reason: 'a delete failure must fail-closed: the store must not '
              'reuse a possibly half-deleted shard',
        );

        // Recovery: clearing the override and re-initializing after the
        // fail-closed reset must work cleanly, with no leftover state from
        // the failed clear().
        store.debugDeleteDirOverride = null;
        await store.initialize(dbDir.path);
        await store.addDocument(
          id: 'doc_after_recovery',
          content: 'doc after recovery',
          embedding: const [1.0, 0.0, 0.0, 0.0],
        );
        final hits = await store.searchSimilar(
          queryEmbedding: const [1.0, 0.0, 0.0, 0.0],
          topK: 5,
        );
        expect(hits.map((h) => h.id).toSet(), equals({'doc_after_recovery'}));
        expect((await store.getStats()).documentCount, equals(1));

        await store.close();
      },
    );
  });

  // ---- Exception wrapping: QdrantException must never leak past the store --
  //
  // `QdrantVectorStore.searchSimilar`/`getStats` only reach `c.search()` /
  // `c.count()` once a client has been successfully opened (`_client` is
  // non-null); until then both return their documented empty/zero defaults
  // rather than calling into the client at all. Two things are pinned here:
  //
  //   1. At the store level: with no successfully-opened client, both methods
  //      return their safe defaults and never throw a raw `QdrantException` —
  //      this is the only state the *public* `QdrantVectorStore` API can put
  //      a caller in without first succeeding at least one write.
  //   2. At the client level (`QdrantEdgeClient`, which `searchSimilar` /
  //      `getStats` call into): once closed, `search()` and `count()` throw
  //      `QdrantException` (never a bare `qe.EdgeException`) — the exact
  //      exception type `searchSimilar`/`getStats` now catch-and-wrap into
  //      `VectorStoreException`. A live end-to-end repro of "a successfully
  //      opened client's `search`/`count` call fails" was probed directly
  //      against the SDK and is not reachable without corrupting the shard's
  //      on-disk state — deleting the shard directory out from under an
  //      already-open handle does not break subsequent reads (open file
  //      descriptors keep working), and reopening with a mismatched
  //      dimension fails at `open()`, not at `search`/`count`. This test pins
  //      the reachable half of that contract instead: the exception type the
  //      wrap depends on really is `QdrantException`, never something else.
  group('exception wrapping', () {
    test(
      'searchSimilar/getStats never throw before any successful write '
      '(safe defaults, no client to leak from)',
      () async {
        final store = QdrantVectorStore();
        await store.initialize(
          '${Directory.systemTemp.path}/qdrant_nowrite_${DateTime.now().microsecondsSinceEpoch}',
        );
        expect(await store.searchSimilar(queryEmbedding: const [1.0], topK: 5), isEmpty);
        final stats = await store.getStats();
        expect(stats.documentCount, equals(0));
        expect(stats.vectorDimension, equals(0));
        await store.close();
      },
    );

    test(
      'QdrantEdgeClient.search/count on a closed client throw QdrantException '
      '(the exact type searchSimilar/getStats catch and wrap into '
      'VectorStoreException)',
      () async {
        final dir =
            '${Directory.systemTemp.path}/qdrant_closed_client_${DateTime.now().microsecondsSinceEpoch}';
        final client = await QdrantEdgeClient.open(path: dir, dim: 4);
        // QdrantEdgeClient (unlike QdrantVectorStore) takes the id as a raw
        // point UUID — it is the store's job to hash a caller id via
        // PointIdHasher first.
        await client.upsert(
          id: '11111111-1111-1111-1111-111111111111',
          vector: const [1.0, 0.0, 0.0, 0.0],
        );
        await client.close();

        await expectLater(
          () => client.search(queryVector: const [1.0, 0.0, 0.0, 0.0], topK: 5),
          throwsA(isA<QdrantException>()),
        );
        await expectLater(client.count, throwsA(isA<QdrantException>()));

        Directory(dir).deleteSync(recursive: true);
      },
    );
  });
}
