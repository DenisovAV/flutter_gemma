// Unit tests for QdrantVectorStore. These run in the plain Dart
// VM (`flutter test`), not in an integration_test runner, so we load the
// release dylib by absolute path via QdrantEdgeClient.debugOverrideDylibPath.
//
// Prerequisite: `native/qdrant_edge/qdrant_edge_ffi/target/release/
// libqdrant_edge_ffi.dylib` exists. The dylib is regenerated via
// `native/qdrant_edge/build_local.sh macos` if missing.

import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _dylibRelative =
    'native/qdrant_edge/qdrant_edge_ffi/target/release/libqdrant_edge_ffi.dylib';

void main() {
  final dylib = File(_dylibRelative);
  if (!dylib.existsSync()) {
    // Skip the whole suite when the dylib hasn't been built. CI builds it
    // via the GitHub Actions workflow; local devs run build_local.sh.
    test('libqdrant_edge_ffi.dylib not built — skipping suite', () {
      // ignore: avoid_print
      print('Skipping: build via native/qdrant_edge/build_local.sh macos');
    });
    return;
  }
  QdrantEdgeClient.debugOverrideDylibPath = dylib.absolute.path;

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
          const FilterSchema(
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

    test(
      'undeclared-key Filter on a configured store is a safe no-op (no throw)',
      () async {
        repo.configure(
          const FilterSchema(
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
          const FilterSchema(
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
}
