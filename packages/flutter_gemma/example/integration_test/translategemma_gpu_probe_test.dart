// Probe: does the freshly-converted int4 .litertlm run on GPU?
//
// The whole point of re-converting TranslateGemma 4B ourselves was to get a
// quantized EMBEDDING_LOOKUP so the LiteRT GPU partitioner can cluster it
// (the barakplasma community fork keeps embeddings float32 → CPU-only).
// This single-pair test on PreferredBackend.gpu verifies engine_create
// succeeds on GPU and produces a sane translation.

import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_gemma_example/translation/translate_gemma_xml_strategy.dart';
import 'package:flutter_gemma_example/translation/translate_runner.dart';

const _modelName = 'translategemma-4b-it-int4-generic.litertlm';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TranslateGemma 4B int4 — GPU engine_create + one translation',
      (_) async {
    await FlutterGemma.initialize();

    final docs = await getApplicationDocumentsDirectory();
    final modelPath = '${docs.path}/$_modelName';
    expect(File(modelPath).existsSync(), isTrue,
        reason: 'pre-stage $_modelName in $docs');

    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(modelPath).install();

    final model = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
    );

    try {
      final runner = TranslateRunner(
        model: model,
        strategy: const TranslateGemmaXmlPromptStrategy(),
      );

      final sw = Stopwatch()..start();
      final fr = await runner.translate(
        text: 'Hello world',
        src: 'en',
        dst: 'fr',
      );
      sw.stop();
      print('[GPU probe] en→fr in ${sw.elapsedMilliseconds}ms: "$fr"');
      expect(fr.trim(), isNotEmpty);
      expect(fr.toLowerCase(), contains('bonjour'));
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
