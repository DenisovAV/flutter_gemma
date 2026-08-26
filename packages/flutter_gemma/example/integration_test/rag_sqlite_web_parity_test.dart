/// The web arm of `sqlite-vec` must return the same rows as the native arm.
///
/// Run with:
///   chromedriver --port=4444 &          # must match your Chrome major version
///   cd packages/flutter_gemma/example
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/rag_sqlite_web_parity_test.dart \
///     -d web-server --browser-name=chrome --headless
///
/// WHY THIS FILE EXISTS
///
/// `flutter_gemma_rag_sqlite`'s README says both arms "speak the same `vec0` SQL
/// dialect, so KNN and `Filter` behave identically across all six platforms".
/// Until this file that was an assertion nobody checked: the package's 103 tests
/// all ran on the VM, and the web arm — a separate implementation of table
/// creation, metadata encoding and row mapping — had none.
///
/// It is not a hypothetical drift. 1.2.0 shipped a fix for "the web arm
/// rejecting integer metadata the native arm accepts", found by reading rather
/// than by testing. 1.3.0 then found three more web-only defects the same way.
///
/// The `Filter` -> SQL codec IS shared (`filter_to_vec0.dart`, imported by both
/// arms), so this suite deliberately does NOT assert generated SQL — that would
/// be a restatement of one implementation. It asserts ROWS, over the corpus in
/// `parity_cases.dart`, which is the same table the native suite runs. A case
/// added there is automatically checked on both arms; a case that passes here
/// and fails natively (or the reverse) is exactly the drift this exists for.
///
/// The fixture lives in the package's `lib/src/testing/` and is `.pubignore`d,
/// because the two suites are in different packages and dart2js will not follow
/// a relative import that escapes its own package — the analyzer accepts one and
/// the web build then fails with "Undefined name".
@TestOn('chrome')
library;

import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_gemma_rag_sqlite/src/testing/parity_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // NO setUp. A setUp that throws inside a group under `flutter drive` on web
  // is reported as "All tests passed" — not as an error, not as a skip. This
  // suite went green twice over a corpus it had failed to insert before that
  // was noticed, and only a mutation of the shared expectations exposed it.
  // Building the store inside each test makes an ingest failure a test failure.
  Future<WebSqliteVectorStore> seededStore(WidgetTester tester) async {
    final store = WebSqliteVectorStore();
    // configure BEFORE initialize, exactly as the native suite does — the
    // declared columns are what the vec0 table is built from.
    store.configure(schema);
    // A fresh IndexedDB name per test keeps one case's corpus out of another's.
    await store.initialize('parity_${DateTime.now().microsecondsSinceEpoch}');
    addTearDown(() => store.close().catchError((Object _) {}));
    for (final d in docs) {
      await store.addDocument(
        id: d.id,
        content: d.id,
        embedding: embedding,
        metadata: d.metadata,
      );
    }
    return store;
  }

  group('web filter parity', () {
    for (final c in cases) {
      testWidgets(c.name, (tester) async {
        final store = await seededStore(tester);
        final rows = await store.searchSimilar(
          queryEmbedding: embedding,
          topK: docs.length,
          filter: c.filter,
        );
        final got = rows.map((h) => h.id).toList()..sort();
        expect(
          got,
          [...c.expected]..sort(),
          reason:
              'web returned ${got.join(", ")} where the shared table says '
              '${c.expected.join(", ")} — the two arms disagree on "${c.name}"',
        );
      });
    }

    testWidgets('the web store was actually exercised', (tester) async {
      // Every case above compares two lists, and two empty lists compare equal,
      // so a store that ingested nothing would let the whole group pass green.
      final store = await seededStore(tester);
      final stats = await store.getStats();
      expect(
        stats.documentCount,
        docs.length,
        reason:
            'the corpus did not land, so every filter case above was comparing '
            'one empty list against another',
      );
      final all = await store.searchSimilar(
        queryEmbedding: embedding,
        topK: docs.length,
      );
      expect(all, hasLength(docs.length));
    });
  });
}
