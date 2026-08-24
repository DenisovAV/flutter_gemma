// Lifecycle and on-disk-format regressions for the 2.0 UniFFI migration.
//
// Every test here pins a failure that the 82-test suite next door could not
// see, because all of those live inside one process against a `setUp`-fresh
// directory: they never open a store a different session — or a different
// package version — wrote, and never run two operations at once.
//
// Each case below was observed failing on the migration commit before the fix.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
import 'package:flutter_gemma_rag_qdrant/src/point_id_hasher.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
// The barrel export goes through the conditional stub, which hides the
// @visibleForTesting seam; reach the implementation directly for that one test.
import 'package:flutter_gemma_rag_qdrant/src/qdrant_vector_store.dart'
    as native;
import 'package:flutter_test/flutter_test.dart';

List<double> vec(int dim, double seed) => List<double>.filled(dim, seed);

/// Lays out the three entries a 1.x (crate 0.7.x) shard wrote directly at the
/// caller's databasePath, before this package owned a versioned subdirectory.
void writeLegacyStore(String databasePath) {
  File('$databasePath/edge_config.json').writeAsStringSync('{}');
  Directory('$databasePath/wal').createSync(recursive: true);
  Directory('$databasePath/segments').createSync(recursive: true);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('qdrant_lifecycle'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('concurrent open', () {
    test('parallel addDocument calls share one open instead of racing', () async {
      // Before: both callers saw `_client == null`, both opened the shard, and
      // qdrant's exclusive WAL lock failed the loser with
      // `Can't init WAL: Kind(WouldBlock)` — losing that document.
      // `Future.wait(docs.map(store.addDocument))` is how you index a corpus.
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      await Future.wait([
        for (var i = 0; i < 8; i++)
          store.addDocument(
            id: 'doc$i',
            content: 'content $i',
            embedding: vec(4, i + 1.0),
          ),
      ]);
      expect((await store.getStats()).documentCount, 8);
      await store.close();
    });

    test('close() during an in-flight open does not resurrect the store', () async {
      // Before: the in-flight open re-installed its client AFTER close(), so
      // `isInitialized` was false while the store still answered reads, the
      // shard was never unloaded, and its WAL lock was held until the process
      // exited — every later initialize() on that path failed permanently.
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      final write = store.addDocument(
        id: 'a',
        content: 'a',
        embedding: vec(4, 1),
      );
      await store.close();
      try {
        await write;
      } catch (_) {
        // Either outcome is fine; what must NOT happen is a live client.
      }
      expect(store.isInitialized, isFalse);

      // The decisive part: the lock must be gone, so a fresh store can open.
      final second = QdrantVectorStore();
      await second.initialize(tmp.path);
      await second.addDocument(id: 'b', content: 'b', embedding: vec(4, 2));
      expect((await second.getStats()).documentCount, greaterThan(0));
      await second.close();
    });
  });

  group('reopening an existing store', () {
    test('reports its contents before anything writes to it', () async {
      // Before: the client opened lazily on the first addDocument, so a store
      // re-opened after an app restart reported 0 documents and 0 hits until
      // something happened to write — retrieval silently returned nothing.
      final first = QdrantVectorStore();
      await first.initialize(tmp.path);
      for (var i = 0; i < 5; i++) {
        await first.addDocument(
          id: 'doc$i',
          content: 'content $i',
          embedding: vec(4, i + 1.0),
        );
      }
      await first.close();

      final reopened = QdrantVectorStore();
      await reopened.initialize(tmp.path);
      expect((await reopened.getStats()).documentCount, 5);
      expect(
        await reopened.searchSimilar(queryEmbedding: vec(4, 1), topK: 10),
        isNotEmpty,
      );
      await reopened.close();
    });

    test('a delete issued before the first write is not dropped', () async {
      // Before: removeDocument() returned early with only a log line when the
      // client had not been opened yet, and the document survived.
      final first = QdrantVectorStore();
      await first.initialize(tmp.path);
      await first.addDocument(id: 'keep', content: 'k', embedding: vec(4, 1));
      await first.addDocument(id: 'drop', content: 'd', embedding: vec(4, 2));
      await first.close();

      final reopened = QdrantVectorStore();
      await reopened.initialize(tmp.path);
      await reopened.removeDocument(id: 'drop');
      expect((await reopened.getStats()).documentCount, 1);
      await reopened.close();
    });
  });

  group('a store written by 1.x', () {
    test('is refused loudly rather than coming up empty', () async {
      // Before: 2.0 only ever looks under its owned subdir, so a 1.x shard was
      // invisible — no error, no log, an empty index, and the old corpus still
      // occupying disk.
      writeLegacyStore(tmp.path);
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      await expectLater(
        store.addDocument(id: 'x', content: 'y', embedding: vec(4, 1)),
        throwsA(
          isA<VectorStoreException>().having(
            (e) => e.toString(),
            'message',
            contains('1.x'),
          ),
        ),
      );
    });

    test('clear() removes it — the remedy the CHANGELOG points at', () async {
      // Before: clear() returned early because the owned subdir did not exist,
      // so "clear it and re-index" was inoperative and 100% of the 1.x bytes
      // stayed on disk with no API able to remove them.
      writeLegacyStore(tmp.path);
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      await store.clear();

      expect(File('${tmp.path}/edge_config.json').existsSync(), isFalse);
      expect(Directory('${tmp.path}/wal').existsSync(), isFalse);
      expect(Directory('${tmp.path}/segments').existsSync(), isFalse);

      // And re-indexing now works.
      await store.addDocument(id: 'a', content: 'b', embedding: vec(4, 1));
      expect((await store.getStats()).documentCount, 1);
      await store.close();
    });

    test('clear() leaves unrelated files at the same path alone', () async {
      // The sweep targets only the three entries a 1.x shard owns. Callers are
      // allowed to keep their own files next to the store.
      writeLegacyStore(tmp.path);
      File('${tmp.path}/user_notes.txt').writeAsStringSync('keep me');
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      await store.clear();
      expect(File('${tmp.path}/user_notes.txt').existsSync(), isTrue);
      await store.close();
    });
  });

  group('clear() failure ordering', () {
    test('a failed delete does not report an empty store', () async {
      // Before: `_client`/`_dim` were nulled BEFORE the delete, so a delete
      // failure left getStats() answering 0 over data still on disk — and the
      // documents reappeared on the next write.
      final store = native.QdrantVectorStore();
      await store.initialize(tmp.path);
      await store.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
      await store.addDocument(id: 'b', content: 'y', embedding: vec(4, 2));

      store.debugDeleteDirOverride =
          (_) => throw const FileSystemException('injected delete failure');

      await expectLater(store.clear(), throwsA(isA<VectorStoreException>()));
      // The shard is still there — the store must not have claimed otherwise.
      expect(Directory('${tmp.path}/qdrant_edge_v1').existsSync(), isTrue);
    });
  });

  group('reserved payload keys', () {
    test('configure() rejects a filter field that would overwrite one', () {
      // Declared fields are promoted to TOP-LEVEL payload keys — the same map
      // that carries the id, content and metadata. Before: a String collision
      // silently swapped the id/body of every hit; a non-String one escaped
      // searchSimilar as a raw _TypeError.
      final store = QdrantVectorStore();
      for (final reserved in const [
        '__flutter_gemma_id',
        '__flutter_gemma_content',
        '__flutter_gemma_metadata',
      ]) {
        expect(
          () => store.configure(
            FilterSchema(
              fields: [
                FilterField(name: reserved, type: FilterFieldType.string),
              ],
            ),
          ),
          throwsArgumentError,
          reason: '$reserved must not be accepted as a filter field',
        );
      }
    });

    test('the stored key names are pinned — they ARE the on-disk format', () async {
      // Renaming any of these silently orphans every shard written by an
      // earlier build: searchSimilar falls back to `?? hit.id` / `?? ''`, so
      // hits come back with a UUID for an id and empty content, with no error.
      // The sibling constant (the UUIDv5 namespace) already has a golden test;
      // this is the same instinct applied to the keys next to it.
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      await store.addDocument(
        id: 'doc-1',
        content: 'the body',
        embedding: vec(4, 1),
        metadata: jsonEncode({'k': 'v'}),
      );
      await store.close();

      // Read the payload back through a raw client, bypassing the store's own
      // constants — otherwise a rename is invisible, because writes and reads
      // would both use the renamed key.
      final client = await QdrantEdgeClient.open(
        path: '${tmp.path}/qdrant_edge_v1',
        dim: 4,
      );
      final hits = await client.search(queryVector: vec(4, 1), topK: 1);
      expect(hits, hasLength(1));
      final payload = hits.single.payload!;
      expect(payload['__flutter_gemma_id'], 'doc-1');
      expect(payload['__flutter_gemma_content'], 'the body');
      expect(
        jsonDecode(payload['__flutter_gemma_metadata'] as String),
        {'k': 'v'},
      );
      // The point id is the UUIDv5 of the caller's id, not the id itself.
      expect(hits.single.id, PointIdHasher.hash('doc-1'));
      await client.close();
    });
  });
}
