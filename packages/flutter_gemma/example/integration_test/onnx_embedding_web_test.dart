// Integration test: ONNX embedding model on Chrome/web.
//
// @TestOn('chrome') — run only via flutter drive with chromedriver.
//
// Model: onnx-community/embeddinggemma-300m-ONNX / onnx/model_quantized.onnx
// Loaded from HuggingFace directly (no local file on web).
//
// Prerequisites:
//   1. Start chromedriver: chromedriver --port=4444 &
//   2. Wire onnxruntime-web WASM assets into example/web/ (see note below).
//
// Run:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/onnx_embedding_web_test.dart \
//     -d chrome
//
// NOTE — onnxruntime-web WASM assets:
//   flutter_onnxruntime 1.8.0 includes a pre-built onnxruntime-web JS/WASM
//   bundle. The WASM files must be served alongside the Flutter web app.
//   Depending on the flutter_onnxruntime version, the files are either:
//     - Bundled automatically via the Flutter web plugin (check if
//       `flutter build web` outputs them into build/web/).
//     - Needed as a manual copy into example/web/assets/ if not bundled.
//   If the test fails with "ORT WASM not found", run:
//     find ~/.pub-cache -path "*/flutter_onnxruntime*/web/*.wasm" | head -5
//   and copy any .wasm/.mjs files to example/web/.
//
// STATUS: Deferred from mandatory run in A5.
//   The native macOS test (onnx_embedding_test.dart) is the mandatory A5 proof.
//   This file sets up the web test structure for future CI wiring.
//   Known blocker: onnxruntime-web in flutter_onnxruntime 1.8.0 may require
//   CORS headers and the WASM worker scripts to be colocated with the app
//   bundle — wiring them requires additional investigation per platform.

@TestOn('chrome')
library;

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';

const _hfBase =
    'https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX/resolve/main';
const _modelUrl = '$_hfBase/onnx/model_quantized.onnx';
const _tokenizerUrl = '$_hfBase/tokenizer.model';

double _cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length, 'Embedding length mismatch');
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = math.sqrt(normA) * math.sqrt(normB);
  return denom == 0 ? 0 : dot / denom;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ONNX EmbeddingGemma web: cosine similarity ordering (similar > different)',
    (WidgetTester tester) async {
      await FlutterGemma.initialize(
        embeddingBackends: const [OnnxEmbeddingBackend()],
      );

      // Web: load model from network (no local file system).
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(_modelUrl)
          .tokenizerFromNetwork(_tokenizerUrl)
          .install();

      expect(FlutterGemma.hasActiveEmbedder(), isTrue);

      final model = await FlutterGemma.getActiveEmbedder();
      try {
        final dim = await model.getDimension();
        expect(dim, equals(768));

        const queryText = 'Which planet is known as the Red Planet';
        const similarText = 'Mars is famous for its reddish appearance';
        const differentText = 'The stock market closed higher today';

        final queryEmb = await model.generateEmbedding(queryText);
        final similarEmb = await model.generateEmbedding(similarText);
        final differentEmb = await model.generateEmbedding(differentText);

        final simScore = _cosineSimilarity(queryEmb, similarEmb);
        final diffScore = _cosineSimilarity(queryEmb, differentEmb);

        print('[onnx_embedding_web_test] cosine(similar): $simScore');
        print('[onnx_embedding_web_test] cosine(different): $diffScore');

        expect(simScore, greaterThan(0.3));
        expect(simScore, greaterThan(diffScore));
      } finally {
        await model.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
