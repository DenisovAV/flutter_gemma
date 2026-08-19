// Covers the FlutterGemma.rag.* namespace and removeDocument (interface →
// platform shell → vectorStoreRepository): add 2 docs, remove one, assert the
// store reports one left, and that removing an absent id is a no-op.
//
// Run: flutter test integration_test/rag_remove_document_test.dart -d macos
library;

import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String dbPath;

  setUpAll(() async {
    await FlutterGemma.initialize(
      vectorStore: SqliteVectorStore(),
      inferenceEngines: const [LiteRtLmEngine()],
      embeddingBackends: const [LiteRtEmbeddingBackend()],
    );
    dbPath = '${(await getTemporaryDirectory()).path}/e_removedoc.db';
  });

  testWidgets(
    'FlutterGemma.rag namespace + removeDocument',
    (t) async {
      await FlutterGemma.rag.initialize(dbPath);
      await FlutterGemma.rag.clear();

      await FlutterGemma.rag.addDocumentWithEmbedding(
        id: 'a',
        content: 'apple',
        embedding: [1.0, 0.0, 0.0],
      );
      await FlutterGemma.rag.addDocumentWithEmbedding(
        id: 'b',
        content: 'banana',
        embedding: [0.0, 1.0, 0.0],
      );

      var stats = await FlutterGemma.rag.stats();
      print('[E] after add: count=${stats.documentCount}');
      expect(stats.documentCount, 2);

      // The new plumbed path: rag.removeDocument → plugin → shell → repo.
      await FlutterGemma.rag.removeDocument(id: 'a');

      stats = await FlutterGemma.rag.stats();
      print('[E] after removeDocument(a): count=${stats.documentCount}');
      expect(stats.documentCount, 1, reason: 'exactly one doc removed');

      // removing an absent id is a no-op (must not throw)
      await FlutterGemma.rag.removeDocument(id: 'a');

      await FlutterGemma.rag.clear();
      try {
        await ServiceRegistry.instance.vectorStoreRepository.close();
      } catch (_) {}
      final f = File(dbPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
