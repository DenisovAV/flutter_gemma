// Integration test for Desktop LiteRT-LM chat
// Run with: cd example && flutter test test/desktop_chat_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model_response.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

      // Create model with minimal config - NO audio/image support to test pure text
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

    test('Simple text chat should work', () async {
      print('\n=== Test: Simple text chat ===');

      // Add a simple query
      const query = 'Hi';
      print('Sending query: "$query"');

      await chat.addQueryChunk(const Message(text: query, isUser: true));
      print('Query added to chat');

      // Get response
      print('Getting response...');
      final response = await chat.generateChatResponse();

      String responseText = '';
      if (response is TextResponse) {
        responseText = response.token;
      }

      print('Response received: "${responseText.take(100)}"');
      print('Response length: ${responseText.length}');

      expect(responseText, isNotEmpty);
      expect(responseText.length, greaterThan(1));
    });

    test('Streaming response should work', () async {
      print('\n=== Test: Streaming response ===');

      await chat.addQueryChunk(const Message(text: 'Count from 1 to 3', isUser: true));

      final chunks = <String>[];
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          chunks.add(response.token);
          if (chunks.length <= 10) {
            print('Chunk ${chunks.length}: "${response.token}"');
          }
        }
      }

      final fullResponse = chunks.join();
      print('Total chunks: ${chunks.length}');
      print('Full response: "${fullResponse.take(100)}"');

      expect(chunks, isNotEmpty);
      expect(fullResponse, isNotEmpty);
    });
  });
}

extension StringTake on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
