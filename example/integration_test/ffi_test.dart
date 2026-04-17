import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';

const _modelPath =
    '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();
  });

  group('Plugin flow - Desktop FFI', () {
    testWidgets('CPU: install → create → session → chat', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_modelPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.cpu,
      );
      expect(model, isNotNull);
      print('Model created');

      final session = await model.createSession(
        temperature: 0.8,
        topK: 1,
      );
      expect(session, isNotNull);
      print('Session created');

      await session.addQueryChunk(const Message(
        text: 'What is 2+2? Answer with just the number.',
        isUser: true,
      ));

      final response = await session.getResponse();
      print('Response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('CPU TEST PASSED');
    });

    testWidgets('CPU: streaming response', (tester) async {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
      ).fromFile(_modelPath).install();

      final model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.cpu,
      );

      final session = await model.createSession(
        temperature: 0.8,
        topK: 1,
      );

      await session.addQueryChunk(const Message(
        text: 'Say hello in one word.',
        isUser: true,
      ));

      final chunks = <String>[];
      await for (final chunk in session.getResponseAsync()) {
        chunks.add(chunk);
        print('Chunk: $chunk');
      }

      expect(chunks, isNotEmpty);
      print('Streaming: ${chunks.length} chunks');

      await session.close();
      await model.close();
      print('STREAMING TEST PASSED');
    });
  });
}
