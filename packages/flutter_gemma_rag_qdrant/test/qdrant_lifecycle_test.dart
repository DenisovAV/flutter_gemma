// Lifecycle and on-disk-format regressions for the 2.0 UniFFI migration.
//
// Every test here pins a failure that the 82-test suite next door could not
// see, because all of those live inside one process against a `setUp`-fresh
// directory: they never open a store a different session — or a different
// package version — wrote, and never run two operations at once.
//
// Most cases below were observed failing on the migration commit before the
// fix. Two are not regression pins and say so at their own site: one guards a
// fix against OVER-correcting (the cold-store case, which the pre-fix code also
// passed — for the wrong reason), and one pins an outcome that more than one
// mechanism delivers. Both were checked by mutation; the distinction is written
// down because "every test here failed before" is the kind of blanket claim
// that quietly stops being true.
import 'dart:async';
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
import 'package:qdrant_edge/qdrant_edge.dart' as qe;

/// The owned, format-scoped subdirectory this release keeps its shard in.
const storeDirName = 'qdrant_edge_v1';

List<double> vec(int dim, double seed) => List<double>.filled(dim, seed);

/// Lays out the three entries a 1.x (crate 0.7.x) shard wrote directly at the
/// caller's databasePath, before this package owned a versioned subdirectory.
void writeLegacyStore(String databasePath) {
  // The real shard config, not a placeholder. `{}` used to be enough to be
  // classified as our store — which is exactly how a caller's own
  // `edge_config.json` got their `wal/` and `segments/` deleted. The unnamed
  // "" vector field is the part that says "this package wrote it".
  // `on_disk_payload` is false here because that is what the 1.x Rust shim
  // wrote (build_edge_config in the deleted native/qdrant_edge). The probe does
  // not read that key — the proof of ownership is the unnamed "" vector field —
  // but a fixture that claims to be what 1.x wrote should be it.
  File('$databasePath/edge_config.json').writeAsStringSync(
    '{"on_disk_payload":false,'
    '"vectors":{"":{"size":4,"distance":"Cosine","on_disk":false}},'
    '"sparse_vectors":{}}',
  );
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
    test(
      'parallel addDocument calls share one open instead of racing',
      () async {
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
      },
    );

    test(
      'close() during an in-flight open does not resurrect the store',
      () async {
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
      },
    );
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
    test('initialize() itself refuses, not just the first write', () async {
      // Before: 2.0 only ever looks under its owned subdir, so a 1.x shard was
      // invisible — no error, no log, an empty index, and the old corpus still
      // occupying disk.
      //
      // The check has to be HERE and not on the write path. A read-only
      // session — open the app, ask a question — never writes, so a write-path
      // check let initialize() succeed, searchSimilar return nothing, and the
      // model answer without the corpus that was on disk the whole time.
      writeLegacyStore(tmp.path);
      final store = QdrantVectorStore();
      await expectLater(
        store.initialize(tmp.path),
        throwsA(
          isA<VectorStoreException>().having(
            (e) => e.toString(),
            'message',
            contains('1.x'),
          ),
        ),
      );
    });

    test(
      'a failed initialize() does not leave the store reading as empty',
      () async {
        // The hole the first version of this fix left open. initialize() arms
        // `_databasePath` BEFORE it throws, so that clear() stays reachable —
        // but it set no latch, so `_assertUsable` saw a perfectly healthy store.
        // A caller that logged the exception and carried on, or any other code
        // path that read, got 0 documents and no hits over an intact 1.x corpus:
        // the exact defect this release removes, in the one case it is about.
        writeLegacyStore(tmp.path);
        final store = QdrantVectorStore();
        await expectLater(
          store.initialize(tmp.path),
          throwsA(isA<VectorStoreException>()),
        );

        expect(
          store.isInitialized,
          isFalse,
          reason: 'a store whose initialize() threw reported itself ready',
        );
        await expectLater(
          store.getStats(),
          throwsA(isA<VectorStoreException>()),
          reason: 'reported 0 documents over a 1.x corpus still on disk',
        );
        await expectLater(
          store.searchSimilar(queryEmbedding: vec(4, 1), topK: 5),
          throwsA(isA<VectorStoreException>()),
          reason: 'answered with no hits over a 1.x corpus still on disk',
        );
        await expectLater(
          store.removeDocument(id: 'x'),
          throwsA(isA<VectorStoreException>()),
        );
      },
    );

    test('the refusal still leaves clear() reachable', () async {
      // The error tells the caller to call clear(). If initialize() threw
      // before arming `_databasePath`, clear() would return early and the
      // prescribed remedy would be inoperative — the store would refuse to
      // work AND refuse to be fixed.
      writeLegacyStore(tmp.path);
      final store = QdrantVectorStore();
      await expectLater(
        store.initialize(tmp.path),
        throwsA(isA<VectorStoreException>()),
      );
      await store.clear();
      expect(File('${tmp.path}/edge_config.json').existsSync(), isFalse);
      await store.close();
    });

    test('clear() removes it — the remedy the CHANGELOG points at', () async {
      // Before: clear() returned early because the owned subdir did not exist,
      // so "clear it and re-index" was inoperative and 100% of the 1.x bytes
      // stayed on disk with no API able to remove them.
      writeLegacyStore(tmp.path);
      final store = QdrantVectorStore();
      await expectLater(
        store.initialize(tmp.path),
        throwsA(isA<VectorStoreException>()),
      );
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
      await expectLater(
        store.initialize(tmp.path),
        throwsA(isA<VectorStoreException>()),
      );
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

      store.debugDeleteDirOverride = (_) =>
          throw const FileSystemException('injected delete failure');

      await expectLater(store.clear(), throwsA(isA<VectorStoreException>()));
      // The shard is still there — the store must not have claimed otherwise.
      expect(Directory('${tmp.path}/qdrant_edge_v1').existsSync(), isTrue);

      // THE assertion. Everything above this line also held BEFORE the fix:
      // clear() threw and the directory survived either way, so the test could
      // not fail on the defect it names. What actually changed is the state
      // left behind — the store must never answer "0 documents" over two
      // documents that are still on disk.
      await expectLater(
        store.getStats(),
        throwsA(isA<StateError>()),
        reason: 'a store that failed to clear reported itself empty',
      );
      await expectLater(
        store.searchSimilar(queryEmbedding: vec(4, 1), topK: 5),
        throwsA(isA<StateError>()),
        reason: 'a store that failed to clear answered with no hits',
      );

      // And the data really is intact: re-initializing finds both documents,
      // which is why reporting zero would have been a lie rather than a
      // harmless default.
      store.debugDeleteDirOverride = null;
      final reopened = native.QdrantVectorStore();
      await reopened.initialize(tmp.path);
      expect((await reopened.getStats()).documentCount, 2);
      await reopened.close();
    });
  });

  group('an unreadable shard is not an empty one', () {
    test('a held WAL is reported, not answered as zero documents', () async {
      // qdrant-edge holds the WAL exclusively. A second store on the same path
      // — a second isolate, a second app process, a store the caller forgot to
      // close — cannot adopt the shard. Before: adoption failure went to
      // gemmaLog, which is `if (!kDebugMode) return;`, so a RELEASE build told
      // nobody and every read answered "empty" over an intact corpus.
      final holder = QdrantVectorStore();
      await holder.initialize(tmp.path);
      await holder.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
      addTearDown(holder.close);

      final second = QdrantVectorStore();
      addTearDown(second.close);
      // The contract says initialize() throws when initialization fails, and
      // this failed: a shard is on disk and the WAL is held elsewhere.
      await expectLater(
        second.initialize(tmp.path),
        throwsA(isA<VectorStoreException>()),
      );

      await expectLater(
        second.getStats(),
        throwsA(isA<VectorStoreException>()),
        reason: 'a shard it could not open was reported as 0 documents',
      );
      await expectLater(
        second.searchSimilar(queryEmbedding: vec(4, 1), topK: 5),
        throwsA(isA<VectorStoreException>()),
        reason: 'a shard it could not open was reported as no hits',
      );
    });

    test('a genuinely cold store stays quiet', () async {
      // NOT a regression pin: the pre-fix code passes this too, because back
      // then adoption threw, was swallowed into gemmaLog, and getStats()
      // returned 0 — which is what this asserts. What it actually guards is
      // the fix OVER-correcting. qdrant-edge raises the same error for
      // "nothing here" as for "here but unreadable", so a latch that keyed on
      // "adoption threw" would make every read on an empty store refuse.
      // Removing the openExisting gate kills this test, at the second half;
      // the first half (a fresh store) asserts nothing and is kept only as the
      // baseline the second half is read against.
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      expect((await store.getStats()).documentCount, 0);
      expect(
        await store.searchSimilar(queryEmbedding: vec(4, 1), topK: 5),
        isEmpty,
      );
      await store.close();

      Directory('${tmp.path}/qdrant_edge_v1').createSync(recursive: true);
      final overLeftover = QdrantVectorStore();
      await overLeftover.initialize(tmp.path);
      expect(
        (await overLeftover.getStats()).documentCount,
        0,
        reason: 'an abandoned empty shard directory was treated as unreadable',
      );
      await overLeftover.close();
    });
  });

  group('an unreadable shard is not an empty one (review round 2)', () {
    test('a shard whose edge_config.json is gone is still adopted', () async {
      // The marker gate this fix originally shipped required `edge_config.json`
      // and returned "no shard" without it. Measured: the engine loads that
      // directory FINE — `wal/` and `segments/` are the data, the config is
      // not — so a store with a full corpus reported zero documents until an
      // unrelated write made it reappear. `clear()` dying after unlinking the
      // marker but before `segments/` reaches exactly this state, and the
      // re-initialize its own fail-closed path prescribes laundered it into a
      // confident zero.
      final seed = QdrantVectorStore();
      await seed.initialize(tmp.path);
      await seed.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
      await seed.addDocument(id: 'b', content: 'y', embedding: vec(4, 2));
      await seed.close();

      File('${tmp.path}/$storeDirName/edge_config.json').deleteSync();

      final reopened = QdrantVectorStore();
      await reopened.initialize(tmp.path);
      expect(
        (await reopened.getStats()).documentCount,
        2,
        reason: 'a readable shard was reported as an empty store',
      );
      await reopened.close();
    });

    test('addDocument refuses over a shard it could not read', () async {
      // Before: the write path never consulted the latch, and any successful
      // open cleared it — so the one signal a user gets that their corpus is
      // unreadable was erasable by an ordinary addDocument, which then merged
      // into the very shard just reported as empty.
      final holder = QdrantVectorStore();
      await holder.initialize(tmp.path);
      await holder.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
      addTearDown(holder.close);

      final second = QdrantVectorStore();
      addTearDown(second.close);
      await expectLater(
        second.initialize(tmp.path), // WAL held by holder
        throwsA(isA<VectorStoreException>()),
      );

      await expectLater(
        second.addDocument(id: 'b', content: 'y', embedding: vec(4, 2)),
        throwsA(
          isA<VectorStoreException>().having(
            (e) => e.toString(),
            'message',
            // The type alone is not enough: without the latch this write still
            // throws, because the WAL is held — a different failure a bare
            // isA<VectorStoreException>() cannot tell apart. Only _assertUsable
            // says "addDocument refused"; a failed open says "Failed to open
            // qdrant shard at". Verified by mutation: dropping the assertion
            // changes the message, not the throw.
            contains('addDocument refused'),
          ),
        ),
      );
      await expectLater(
        second.getStats(),
        throwsA(isA<VectorStoreException>()),
        reason: 'a write cleared the latch and the store reported itself fine',
      );
    });

    test(
      'a failure for one path does not latch a store armed at another',
      () async {
        // An outcome test, deliberately: it does not care WHICH mechanism
        // keeps the latch from leaking. Today it is the lifecycle lane — the
        // second initialize() cannot start until the first has finished, and
        // it clears the latch as it arms the new path. Removing the generation
        // check in initialize()'s catch leaves this passing, and that is the
        // truth about the check rather than a gap here.
        final other = Directory.systemTemp.createTempSync('qdrant_other');
        addTearDown(() {
          try {
            other.deleteSync(recursive: true);
          } catch (_) {}
        });
        final holder = QdrantVectorStore();
        await holder.initialize(tmp.path);
        await holder.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
        addTearDown(holder.close);

        final store = QdrantVectorStore();
        addTearDown(store.close);
        final toLocked = store.initialize(tmp.path); // fails: WAL held
        final toFresh = store.initialize(other.path); // succeeds
        await toLocked.catchError((_) {});
        await toFresh.catchError((_) {});

        expect(
          (await store.getStats()).documentCount,
          0,
          reason: 'the latch leaked from the path the store no longer uses',
        );
      },
    );

    test('two overlapping initialize() calls adopt the corpus', () async {
      // A provider rebuilt, an initState firing twice. Both calls raced
      // qdrant's exclusive WAL: one won, the other caught WouldBlock and
      // latched the store unreadable over an intact corpus — while BOTH
      // reported success.
      final seed = QdrantVectorStore();
      await seed.initialize(tmp.path);
      await seed.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
      await seed.addDocument(id: 'b', content: 'y', embedding: vec(4, 2));
      await seed.close();

      final store = QdrantVectorStore();
      addTearDown(store.close);
      await Future.wait([
        store.initialize(tmp.path),
        store.initialize(tmp.path),
      ]);

      expect(store.isInitialized, isTrue);
      expect(
        (await store.getStats()).documentCount,
        2,
        reason: 'a double init left the store unreadable over its own corpus',
      );
    });
  });

  group('a partial 1.x sweep is reported, not reported as success', () {
    test(
      'clear() that cannot remove the 1.x store says so, and stays latched',
      () async {
        // ~30 lines exist so clear() never claims success over a partial delete.
        // None of them was reachable from a test: the delete seam covered only
        // the owned subdirectory, so every mutation to the sweep — including
        // dropping the failure report entirely — passed the whole suite.
        writeLegacyStore(tmp.path);
        final store = native.QdrantVectorStore();
        addTearDown(store.close);
        await expectLater(
          store.initialize(tmp.path),
          throwsA(isA<VectorStoreException>()),
        );

        // Fail ONLY the payload. A blanket throw also hits the marker, and
        // then the test cannot tell "the payload failure was reported" from
        // "the marker failure was reported" — swallowing the first still threw
        // via the second, and the mutation survived.
        store.debugDeleteDirOverride = (dir) {
          if (dir.path.endsWith('wal') || dir.path.endsWith('segments')) {
            throw const FileSystemException('injected sweep failure');
          }
          dir.deleteSync(recursive: true);
        };

        await expectLater(
          store.clear(),
          throwsA(
            isA<VectorStoreException>().having(
              (e) => e.toString(),
              'message',
              // Names what survived, so the caller can act. The old wording
              // claimed the leftovers "still hold indexed documents", which is
              // false when only the marker survives — the corpus is gone.
              allOf(contains('wal'), contains('segments')),
            ),
          ),
          reason: 'clear() reported success over a 1.x store still on disk',
        );

        expect(
          File('${tmp.path}/edge_config.json').existsSync(),
          isTrue,
          reason:
              'the fixture did not actually survive, so this proves nothing',
        );
        await expectLater(
          store.getStats(),
          throwsA(isA<VectorStoreException>()),
          reason: 'a failed sweep left the store reporting itself empty',
        );
      },
    );

    test(
      'the marker is deleted LAST, so a survivor stays detectable',
      () async {
        // If `edge_config.json` went first, any survivor of a partial delete
        // would be invisible to _hasLegacyStoreAt — unclearable by this API and
        // undetectable by initialize(). Fail the FIRST delete only, and the
        // marker must still be there.
        writeLegacyStore(tmp.path);
        final store = native.QdrantVectorStore();
        addTearDown(store.close);
        await store.initialize(tmp.path).catchError((_) {});

        var calls = 0;
        store.debugDeleteDirOverride = (dir) {
          if (calls++ == 0) throw const FileSystemException('first only');
          dir.deleteSync(recursive: true);
        };
        await store.clear().catchError((_) {});

        expect(
          File('${tmp.path}/edge_config.json').existsSync(),
          isTrue,
          reason: 'the marker went before the payload, hiding the survivor',
        );
      },
    );
  });

  group('the latch must lift as well as fall', () {
    test('a latch clears once the shard can actually be opened', () async {
      // A sticky latch is a WORSE failure than the silent zero it replaced:
      // every read refusing forever on a store that is now perfectly healthy.
      // Nothing pinned the clearing side at all before this.
      //
      // It pins an OUTCOME, not one line: two sites clear the latch — the
      // reset at the top of initialize() and the adoption-success path — and
      // removing either alone leaves this green. Removing BOTH kills it, which
      // is the honest statement of what it covers.
      final holder = QdrantVectorStore();
      await holder.initialize(tmp.path);
      await holder.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));

      final second = QdrantVectorStore();
      addTearDown(second.close);
      await expectLater(
        second.initialize(tmp.path), // WAL held
        throwsA(isA<VectorStoreException>()),
      );
      await expectLater(
        second.getStats(),
        throwsA(isA<VectorStoreException>()),
      );

      await holder.close(); // the cause goes away
      await second.initialize(tmp.path); // the message says to do this

      expect(second.isInitialized, isTrue);
      expect(
        (await second.getStats()).documentCount,
        1,
        reason: 'the latch outlived the condition that set it',
      );
    });

    test('a leftover wal/ alone is not evidence of a shard', () async {
      // The gate keys on `edge_config.json` OR `segments/`. `wal/` is
      // deliberately excluded: a first open that failed leaves it behind with
      // nothing committed, and counting it would refuse every read on a store
      // that never held data. A mutation adding `wal/` as evidence passed the
      // whole suite before this test existed.
      Directory('${tmp.path}/$storeDirName/wal').createSync(recursive: true);
      final store = QdrantVectorStore();
      addTearDown(store.close);
      await store.initialize(tmp.path);
      expect(
        (await store.getStats()).documentCount,
        0,
        reason: 'an abandoned wal/ was mistaken for an unreadable shard',
      );
    });
  });

  group('the 1.x probe reads the marker, not just its name', () {
    test(
      'a same-named file that is not our config is not a 1.x store',
      () async {
        // The probe is content-gated because a false positive is destructive:
        // the store refuses to run and clear() — the remedy its own error names
        // — deletes what it matched. Every existing test writes a valid '{}', so
        // dropping the content check passed the whole suite.
        File('${tmp.path}/edge_config.json').writeAsStringSync('not our file');
        final store = QdrantVectorStore();
        addTearDown(store.close);
        await store.initialize(tmp.path);
        await store.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
        expect((await store.getStats()).documentCount, 1);
        expect(
          File('${tmp.path}/edge_config.json').readAsStringSync(),
          'not our file',
          reason: "someone else's file was treated as our 1.x store",
        );
      },
    );

    test(
      'a marker we cannot READ counts as present, not as absent',
      () async {
        // The blanket `catch (_)` put "unreadable" in the same bucket as "not
        // ours", so a genuine 1.x store whose marker could not be read came up
        // as an empty index with no error — back in the silent bucket.
        writeLegacyStore(tmp.path);
        final marker = File('${tmp.path}/edge_config.json');
        Process.runSync('chmod', ['000', marker.path]);
        addTearDown(() => Process.runSync('chmod', ['600', marker.path]));

        final store = QdrantVectorStore();
        addTearDown(store.close);
        await expectLater(
          store.initialize(tmp.path),
          throwsA(isA<VectorStoreException>()),
          reason: 'an unreadable 1.x marker was read as "no legacy store"',
        );
      },
      skip: Platform.isWindows ? 'chmod semantics differ' : false,
    );
  });

  group('a shard we did not write', () {
    test('is reported, not treated as no shard at all', () async {
      // The one branch with POSITIVE proof a shard is present — it loaded, we
      // read its config — and it used to discard that and return null, so the
      // store came up empty over data it had just seen. Reachable from a shard
      // written by another tool, or by a future format of ours.
      final storeDir = Directory('${tmp.path}/$storeDirName')
        ..createSync(recursive: true);
      qe.EdgeShard.load(
        path: storeDir.path,
        config: qe.EdgeConfig(
          vectorData: {
            'text': qe.VectorDataConfig(size: 8, distance: qe.Distance.cosine),
          },
        ),
      ).unload();

      final store = QdrantVectorStore();
      addTearDown(store.close);
      await expectLater(
        store.initialize(tmp.path),
        throwsA(isA<VectorStoreException>()),
        reason: 'a shard it had just loaded was reported as an empty store',
      );
      await expectLater(store.getStats(), throwsA(isA<VectorStoreException>()));
    });
  });

  group('the documented no-ops', () {
    test(
      'removeDocument on an initialized, never-written store is a no-op',
      () async {
        // The contract says removing a document that does not exist does not
        // throw. Distinct from the two refusals around it — uninitialized is a
        // StateError, unreadable is a VectorStoreException — and nothing pinned
        // which of the three this is.
        final store = QdrantVectorStore();
        addTearDown(store.close);
        await store.initialize(tmp.path);
        await expectLater(store.removeDocument(id: 'never-added'), completes);
      },
    );
  });

  group('clear() cannot report a failure it has not settled for', () {
    test('a close that fails leaves no closed client installed', () async {
      // QdrantEdgeClient.close() marks itself closed BEFORE it unloads, so a
      // client whose close threw and stayed installed made every later call
      // die with "QdrantEdgeClient is closed" until initialize() ran again.
      // The un-bumped generation also let an in-flight open install itself
      // over the store we were asked to clear.
      final store = native.QdrantVectorStore();
      addTearDown(store.close);
      await store.initialize(tmp.path);
      await store.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));

      store.debugCloseFault = () => const FileSystemException('injected close');
      await expectLater(store.clear(), throwsA(isA<VectorStoreException>()));
      store.debugCloseFault = null;

      expect(
        store.isInitialized,
        isFalse,
        reason: 'a clear() that could not close reported itself ready',
      );
      // Fail-closed, and RECOVERABLE: re-initialize must give a working store,
      // not one wedged on the handle that would not close.
      await store.initialize(tmp.path);
      await store.addDocument(id: 'b', content: 'y', embedding: vec(4, 2));
      expect((await store.getStats()).documentCount, greaterThan(0));
    });
  });

  group('a write racing a lifecycle transition', () {
    test(
      'addDocument during clear() fails loudly and leaves a usable store',
      () async {
        // The lifecycle lane serializes initialize/clear/close against each
        // other, but NOT against the write path — _ensureClient stays outside it
        // so bulk indexing is not funnelled through one queue. That leaves a
        // window where a write can hold a client clear() is closing. The
        // requirement is not that the write succeed; it is that it never
        // succeed QUIETLY into a store being erased, and that what is left
        // behind is usable.
        final store = QdrantVectorStore();
        addTearDown(store.close);
        await store.initialize(tmp.path);
        await store.addDocument(id: 'seed', content: 's', embedding: vec(4, 1));

        final outcomes = await Future.wait([
          store.clear().then((_) => 'ok').catchError((Object e) => 'threw'),
          store
              .addDocument(id: 'a', content: 'x', embedding: vec(4, 2))
              .then((_) => 'ok')
              .catchError((Object e) => 'threw'),
        ]);

        expect(outcomes.first, 'ok');
        expect(store.isInitialized, isTrue);
        // Either the write landed before the erase or it was refused — never a
        // silent no-op, and never a wedged store.
        expect((await store.getStats()).documentCount, anyOf(0, 1));
        await store.addDocument(id: 'b', content: 'y', embedding: vec(4, 3));
        expect((await store.getStats()).documentCount, greaterThan(0));
      },
    );

    test('addDocument during close() does not leak the WAL lock', () async {
      // The worst outcome here is invisible: a store the caller closed keeps
      // qdrant's exclusive WAL for the process lifetime, and every later
      // store on that path fails WouldBlock — which this release now latches,
      // so it would present as "your corpus is unreadable" forever.
      final store = QdrantVectorStore();
      await store.initialize(tmp.path);
      await Future.wait([
        store.close().catchError((Object e) {}),
        store
            .addDocument(id: 'a', content: 'x', embedding: vec(4, 1))
            .catchError((Object e) {}),
      ]);

      final reopened = QdrantVectorStore();
      addTearDown(reopened.close);
      await reopened.initialize(tmp.path);
      await expectLater(
        reopened.getStats(),
        completes,
        reason: 'the closed store kept its WAL lock',
      );
    });
  });

  group('a lifecycle failure nobody awaited', () {
    test('still reaches the zone', () async {
      // `initState()` cannot await, so `store.initialize(dir);` is the ordinary
      // shape — and the one the lane's own comment cites. Advancing the lane
      // with `run.then((_) {}, onError: (_) {})` registered a listener on the
      // CALLER's future, which marks the error handled globally: no zone
      // error, no FlutterError.onError, no crash reporter, and gemmaLog is
      // debug-only. The release's headline error went nowhere at all, and the
      // same lane ate clear()'s partial-delete report — which throws instead
      // of logging for exactly that reason.
      final errors = <Object>[];
      await runZonedGuarded(() async {
        // Control: prove the zone is actually catching in this test.
        unawaited(Future<void>(() => throw StateError('control')));
        writeLegacyStore(tmp.path);
        QdrantVectorStore().initialize(tmp.path); // deliberately not awaited
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }, (e, _) => errors.add(e));

      expect(errors.whereType<StateError>(), hasLength(1), reason: 'control');
      expect(
        errors.whereType<VectorStoreException>(),
        hasLength(1),
        reason: 'an unawaited lifecycle failure was reported to nobody',
      );
    });

    test('an awaited failure is not reported twice', () async {
      // The other half: the lane must not ALSO push the error to the zone when
      // the caller handled it. Two of the three shapes I tried failed one side
      // or the other.
      final errors = <Object>[];
      await runZonedGuarded(() async {
        writeLegacyStore(tmp.path);
        final store = QdrantVectorStore();
        await expectLater(
          store.initialize(tmp.path),
          throwsA(isA<VectorStoreException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, (e, _) => errors.add(e));
      expect(errors, isEmpty, reason: 'a handled failure was double-reported');
    });
  });

  group('evidence good enough to refuse is not evidence good enough to delete', () {
    test(
      "an unreadable marker does not cost the caller its directories",
      () async {
        // Round 1 through a new door. A marker we cannot READ is either a real
        // 1.x store (refuse, or the app comes up empty over the corpus) or
        // someone else's file beside directories the caller happens to have
        // named `wal` and `segments`. We cannot tell — that is what "cannot
        // read" means — so it gets the safe half of each: refuse to start, never
        // delete. Answering a plain `true` deleted both of the caller's
        // directories and returned from clear() NORMALLY.
        final marker = File('${tmp.path}/edge_config.json')
          ..writeAsStringSync('not our file');
        Directory('${tmp.path}/wal').createSync();
        File('${tmp.path}/wal/caller.txt').writeAsStringSync('mine');
        Directory('${tmp.path}/segments').createSync();
        File('${tmp.path}/segments/caller.txt').writeAsStringSync('mine');
        Process.runSync('chmod', ['000', marker.path]);
        addTearDown(() => Process.runSync('chmod', ['600', marker.path]));

        final store = QdrantVectorStore();
        addTearDown(store.close);
        await expectLater(
          store.initialize(tmp.path),
          throwsA(isA<VectorStoreException>()),
        );
        await expectLater(
          store.clear(),
          throwsA(isA<VectorStoreException>()),
          reason: 'clear() reported success while deleting the caller\'s data',
        );
        expect(Directory('${tmp.path}/wal').existsSync(), isTrue);
        expect(Directory('${tmp.path}/segments').existsSync(), isTrue);
      },
      skip: Platform.isWindows ? 'chmod semantics differ' : false,
    );

    test(
      "a readable config we did not write is refused but never deleted",
      () async {
        // The destructive false positive, reopened a second time through the
        // door the previous fix left ajar. "It parses as a JSON object" was
        // treated as proof of ownership, so a caller whose own
        // `edge_config.json` held `{}` — beside their own `wal/` and
        // `segments/` — had both directories deleted by clear(), which then
        // returned normally.
        //
        // Refusing and deleting need different evidence. We still refuse (it
        // could be a 1.x layout whose config we do not recognise, and coming up
        // empty over a corpus is the defect this release removes), but the
        // destructive path needs the shard config this package actually writes.
        File('${tmp.path}/edge_config.json').writeAsStringSync('{}');
        Directory('${tmp.path}/wal').createSync();
        File('${tmp.path}/wal/caller.txt').writeAsStringSync('mine');
        Directory('${tmp.path}/segments').createSync();
        File('${tmp.path}/segments/caller.txt').writeAsStringSync('mine');

        final store = QdrantVectorStore();
        addTearDown(store.close);
        await expectLater(
          store.initialize(tmp.path),
          throwsA(isA<VectorStoreException>()),
        );
        await expectLater(
          store.clear(),
          throwsA(
            isA<VectorStoreException>().having(
              (e) => e.toString(),
              'message',
              contains('not a shard config this package wrote'),
            ),
          ),
          reason: "clear() deleted the caller's directories and said it worked",
        );
        expect(File('${tmp.path}/wal/caller.txt').existsSync(), isTrue);
        expect(File('${tmp.path}/segments/caller.txt').existsSync(), isTrue);
      },
    );

    test('a marker with no payload beside it is not a store', () async {
      // What a sweep leaves when it removes `wal/` and `segments/` and then
      // cannot unlink the marker. Treating that as a store made initialize()
      // refuse forever over nothing and clear() fail forever on the one file
      // it had already failed to remove — a loop whose only exit was the call
      // that was looping.
      File('${tmp.path}/edge_config.json').writeAsStringSync('{}');
      final store = QdrantVectorStore();
      addTearDown(store.close);
      await store.initialize(tmp.path);
      await store.addDocument(id: 'a', content: 'x', embedding: vec(4, 1));
      expect((await store.getStats()).documentCount, 1);
    });
  });

  group('uninitialized store', () {
    test(
      'reads throw StateError, as VectorStoreRepository documents',
      () async {
        // The interface documents `StateError` for all three, and the sibling
        // sqlite store throws it. This one returned empty results and dropped
        // removeDocument to a debug-only log line — so the same caller mistake
        // was loud in one implementation and invisible in the other.
        final store = QdrantVectorStore();
        await expectLater(store.getStats(), throwsStateError);
        await expectLater(
          store.searchSimilar(queryEmbedding: vec(4, 1), topK: 5),
          throwsStateError,
        );
        await expectLater(store.removeDocument(id: 'x'), throwsStateError);
      },
    );
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

    test(
      'the stored key names are pinned — they ARE the on-disk format',
      () async {
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
        expect(jsonDecode(payload['__flutter_gemma_metadata'] as String), {
          'k': 'v',
        });
        // The point id is the UUIDv5 of the caller's id, not the id itself.
        expect(hits.single.id, PointIdHasher.hash('doc-1'));
        await client.close();
      },
    );
  });
}
