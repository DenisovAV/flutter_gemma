// Minimal repro: how many sequential EmbeddingGemma calls can a Windows
// integration_test runner survive before "did not complete" kills it?
//
// Run:
//   cd example && flutter test integration_test/embedding_loop_repro_test.dart -d windows

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelPath =
    'assets/models/embeddinggemma-300M_seq256_mixed-precision.tflite';
const _tokenizerPath = 'assets/models/sentencepiece.model';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultTestTimeout = const Timeout(Duration(minutes: 30));

  testWidgets('embed 100 times', (WidgetTester tester) async {
    await FlutterGemma.initialize();
    await FlutterGemma.installEmbedder()
        .modelFromAsset(_modelPath)
        .tokenizerFromAsset(_tokenizerPath)
        .install();
    final embedder = await FlutterGemma.getActiveEmbedder();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      final v = await embedder.generateEmbedding('test text $i');
      // ignore: avoid_print
      print(
          '[repro] embedded ${i + 1}/10 (${sw.elapsed.inMilliseconds}ms, dim=${v.length})');
    }
    sw.stop();
    // ignore: avoid_print
    print('[repro] total: ${sw.elapsed.inSeconds}s');
  });
}
