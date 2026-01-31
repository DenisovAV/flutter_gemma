// Integration test for Desktop LiteRT-LM chat
// Run with: flutter test integration_test/desktop_chat_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model_response.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Desktop LiteRT-LM Chat Test', () {
    late InferenceModel model;
    late InferenceChat chat;

    setUpAll(() async {
      print('=== Setting up Desktop Chat Test ===');

      // Initialize FlutterGemma
      await FlutterGemma.initialize();
      print('FlutterGemma initialized');

      // Check if model is installed
      final hasModel = FlutterGemma.hasActiveModel();
      print('Has active model: $hasModel');

      if (!hasModel) {
        fail('No active model set. Install gemma-3n-E2B-it-int4 first via the example app.');
      }

      // Create model with supportAudio=FALSE, supportImage=FALSE
      // to test pure text chat
      print('Creating model with supportAudio=false, supportImage=false');
      model = await FlutterGemma.getActiveModel(
        maxTokens: 512,
        preferredBackend: PreferredBackend.gpu,
        supportAudio: false,
        supportImage: false,
      );
      print('Model created: ${model.runtimeType}');

      // Create chat
      chat = await model.createChat();
      print('Chat created: ${chat.runtimeType}');
    });

    tearDownAll(() async {
      print('=== Tearing down ===');
      await model.close();
    });

    testWidgets('Simple text chat should work', (tester) async {
      print('\n=== Test: Simple text chat ===');

      // Add a simple query
      const query = 'Hi';
      print('Sending query: "$query"');

      await chat.addQueryChunk(const Message(text: query, isUser: true));
      print('Query added to chat');

      // Get response via streaming
      print('Getting streaming response...');
      final chunks = <String>[];
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          chunks.add(response.token);
          if (chunks.length <= 10) {
            print('Chunk ${chunks.length}: "${response.token}"');
          }
        }
      }

      final responseText = chunks.join();
      print('Full response: "${responseText.take(100)}"');
      print('Response length: ${responseText.length} chars');

      expect(responseText, isNotEmpty);
      expect(responseText.length, greaterThan(1));
      print('✓ Test passed!');
    });
  });
}

extension StringTake on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
