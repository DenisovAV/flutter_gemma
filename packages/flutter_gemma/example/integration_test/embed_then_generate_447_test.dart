// #447 as a USER sees it: embed something, then generate.
//
// The companion loader_order tests measure symbol visibility from Dart. That is
// a proxy. The failure reported in #447 is a stream that delivers ZERO chunks,
// synthesises `Exception: Stream error: <U+FFFD>` out of unread registers, and
// then aborts the process with SIGABRT when the closed NativeCallable is
// invoked again. This file reproduces THAT, or shows that it cannot be
// reproduced this way — which would mean the load-order explanation is not the
// one behind #447 and the fix has to be the native one.
//
// Order is the whole point. Our canonical suite (litertlm_ffi_test.dart) runs
// the embedding group LAST, so the failing permutation is not expressible in
// it and never has been.
//
// Needs both models pushed to the device:
//   adb push gemma-4-E2B-it.litertlm  /data/local/tmp/flutter_gemma_test/
//   adb push embeddinggemma-300M_seq256_mixed-precision.tflite  ...
//   adb push sentencepiece.model  ...
//
//   flutter test integration_test/embed_then_generate_447_test.dart -d <android>
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'inference_test_helpers.dart' show registerTestEngines;

String _p(String name) => '/data/local/tmp/flutter_gemma_test/$name';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'generation still streams after embeddings loaded first',
    (t) async {
      if (!Platform.isAndroid) {
        fail(
          'Android only — the linker property under test is Android-specific',
        );
      }
      await registerTestEngines();

      // ── STEP 1: embeddings FIRST. This is the step that used to decide, for
      // the whole process, whether the LLM path's stream-ABI probe could see
      // anything.
      await FlutterGemma.installEmbedder()
          .modelFromFile(
            _p('embeddinggemma-300M_seq256_mixed-precision.tflite'),
          )
          .tokenizerFromFile(_p('sentencepiece.model'))
          .install();
      final embedder = await FlutterGemma.getActiveEmbedder();
      final vector = await embedder.generateEmbedding('warm up the embedder');
      expect(vector, isNotEmpty, reason: 'the embedding path itself must work');
      print('[#447] embedded first: ${vector.length} dims');

      // ── STEP 2: generate. On an affected process this yields zero chunks and
      // an error synthesised from registers the caller never wrote, then aborts.
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_p('gemma-4-E2B-it.litertlm')).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.cpu,
      );
      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(const Message(text: 'Say hi', isUser: true));

      final chunks = <String>[];
      await for (final c in session.getResponseAsync()) {
        chunks.add(c);
      }
      print('[#447] chunks=${chunks.length} text="${chunks.join()}"');

      // Zero chunks is the reported signature, and it is what a 4-arg callback
      // driven by a 2-arg caller produces: `chunk` is a struct pointer read as a
      // C string.
      expect(
        chunks,
        isNotEmpty,
        reason:
            'zero chunks after embedding first — the legacy callback shape was '
            'selected, which is #447',
      );
      expect(chunks.join().trim(), isNotEmpty);

      await session.close();
      await model.close();
      await embedder.close();
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
