// Cross-platform embedding score comparison test.
// Downloads model from network, runs same texts, prints scores.
// Run on Android: flutter test integration_test/embedding_score_comparison_test.dart -d emulator-5554 --dart-define=HF_TOKEN=...
// Run on macOS:   flutter test integration_test/embedding_score_comparison_test.dart -d macos --dart-define=HF_TOKEN=...

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// EmbeddingGemma 300M seq256 — gated model, requires HF token
const _modelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
const _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Embedding score comparison', (WidgetTester tester) async {
    final hfToken = const String.fromEnvironment('HF_TOKEN');

    await FlutterGemma.initialize();

    await FlutterGemma.installEmbedder()
        .modelFromNetwork(_modelUrl,
            token: hfToken.isNotEmpty ? hfToken : null)
        .tokenizerFromNetwork(_tokenizerUrl,
            token: hfToken.isNotEmpty ? hfToken : null)
        .withModelProgress(
            (progress) => print('[model] $progress%'))
        .install();

    final model = await FlutterGemma.getActiveEmbedder();

    try {
      // Same texts as desktop_embedding_test
      final queryEmb = await model
          .generateEmbedding('Which planet is known as the Red Planet');
      final similarEmb = await model
          .generateEmbedding('Mars is famous for its reddish appearance');
      final diffEmb = await model
          .generateEmbedding('The stock market closed higher today');

      final simScore = _cosineSimilarity(queryEmb, similarEmb);
      final diffScore = _cosineSimilarity(queryEmb, diffEmb);

      print('=== SCORES ===');
      print('Similar score: $simScore');
      print('Different score: $diffScore');
      print('Gap: ${simScore - diffScore}');
      print('Dimension: ${queryEmb.length}');

      // Basic sanity
      expect(queryEmb.length, equals(768));
      expect(diffScore, lessThan(simScore));
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
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
