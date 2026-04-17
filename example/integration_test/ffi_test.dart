import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/ffi/litert_lm_client.dart';
import 'package:flutter_gemma/core/ffi/litert_lm_bindings.dart';

// Use the model already in the app container (gemma-4-E2B, 2.4GB, already downloaded)
const _modelPath =
    '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-4-E2B-it.litertlm';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();
  });

  group('Desktop FFI - LiteRT-LM C API', () {
    testWidgets('Sync send_message works (bypassing streaming)', (tester) async {
      // This test uses the C API directly via LiteRtLmFfiClient
      // to verify engine + conversation + sync send_message work
      final client = LiteRtLmFfiClient();
      await client.initialize(
        modelPath: _modelPath,
        backend: 'cpu',
        maxTokens: 512,
        cacheDir: '/tmp/litert_lm_cache',
      );
      print('Engine initialized');

      // Use default config (nullptr) — known to work
      client.createConversation();
      print('Conversation created');

      // Use sync sendMessage (internally calls sendMessageStreamRaw)
      final msgJson = LiteRtLmFfiClient.buildMessageJson('What is 2+2?');
      print('Message JSON: $msgJson');

      final response = await client.sendMessage(msgJson);
      print('Response: $response');
      expect(response, isNotEmpty);

      client.shutdown();
      print('SYNC TEST PASSED');
    });

    testWidgets('Plugin flow: install → create → chat (CPU)', (tester) async {
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
        text: 'What is 2+2?',
        isUser: true,
      ));

      final response = await session.getResponse();
      print('Plugin CPU response: $response');
      expect(response, isNotEmpty);

      await session.close();
      await model.close();
      print('PLUGIN CPU TEST PASSED');
    });
  });
}
