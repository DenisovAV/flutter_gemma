// Integration test: embedding model download, caching, and basic inference.
// Run: flutter test integration_test/desktop_embedding_test.dart -d macos

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// Gecko 64 — smallest embedding model, 110MB, no auth required
const _modelUrl =
    'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_64_quant.tflite';
const _tokenizerUrl =
    'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model';
const _modelFilename = 'Gecko_64_quant.tflite';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Embedding: model download, cache, and inference',
      (WidgetTester tester) async {
    // 1. Initialize
    await FlutterGemma.initialize();

    // 2. Download model + tokenizer
    await FlutterGemma.installEmbedder()
        .modelFromNetwork(_modelUrl)
        .tokenizerFromNetwork(_tokenizerUrl)
        .withModelProgress(
            (progress) => print('[Download/model] Progress: $progress%'))
        .withTokenizerProgress(
            (progress) => print('[Download/tokenizer] Progress: $progress%'))
        .install();

    // 3. Verify active model
    expect(FlutterGemma.hasActiveEmbedder(), isTrue,
        reason: 'Active embedding model should be set after install');

    // 4. Verify model installed on disk
    final isInstalled = await FlutterGemma.isModelInstalled(_modelFilename);
    expect(isInstalled, isTrue, reason: 'Model file should exist on disk');

    // 5. Cache check — second install should be instant
    final stopwatch = Stopwatch()..start();
    await FlutterGemma.installEmbedder()
        .modelFromNetwork(_modelUrl)
        .tokenizerFromNetwork(_tokenizerUrl)
        .install();
    stopwatch.stop();
    print('[Cache] Second install took ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsedMilliseconds, lessThan(5000),
        reason: 'Cached model should not trigger re-download');

    // 6. Create embedder and run inference
    final model = await FlutterGemma.getActiveEmbedder();

    try {
      // 6a. Generate embedding — should be 768D, non-zero
      final emb = await model.generateEmbedding('test text');
      print('Embedding dimension: ${emb.length}');
      expect(emb.length, equals(768));
      expect(emb.any((v) => v != 0), isTrue);

      // 6b. getDimension()
      final dim = await model.getDimension();
      expect(dim, equals(768));

      // 6c. Repeatability — same text produces identical embeddings
      final emb2 = await model.generateEmbedding('test text');
      expect(emb.length, equals(emb2.length));
      for (int i = 0; i < emb.length; i++) {
        expect(emb[i], closeTo(emb2[i], 1e-6));
      }

      // 6d. Semantic similarity — similar texts should be closer
      final queryEmb = await model
          .generateEmbedding('Which planet is known as the Red Planet');
      final similarEmb = await model
          .generateEmbedding('Mars is famous for its reddish appearance');
      final diffEmb = await model
          .generateEmbedding('The stock market closed higher today');

      final simScore = _cosineSimilarity(queryEmb, similarEmb);
      final diffScore = _cosineSimilarity(queryEmb, diffEmb);
      print('Similar score: $simScore');
      print('Different score: $diffScore');

      expect(simScore, greaterThan(0.5));
      expect(diffScore, lessThan(simScore));

      // 6e. Batch embeddings
      final batch = await model.generateEmbeddings(['hello', 'world']);
      expect(batch.length, equals(2));
      expect(batch[0].length, equals(768));
      expect(batch[1].length, equals(768));

      print('All embedding tests passed!');
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

double _cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length);
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
