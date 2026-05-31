// Integration test for Desktop LiteRT-LM chat
// Run with: flutter test integration_test/desktop_chat_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Desktop LiteRT-LM simple text chat', (tester) async {
    await FlutterGemma.initialize();

    final hasModel = FlutterGemma.hasActiveModel();
    if (!hasModel) {
      fail('No active model set. Install gemma-3n-E2B-it-int4 first via the example app.');
    }

    final model = await FlutterGemma.getActiveModel(
      maxTokens: 512,
      preferredBackend: PreferredBackend.gpu,
      supportAudio: false,
      supportImage: false,
    );

    try {
      final chat = await model.createChat();

      await chat.addQueryChunk(const Message(text: 'Hi', isUser: true));

      final chunks = <String>[];
      await tester.runAsync(() async {
        await for (final response in chat.generateChatResponseAsync()) {
          if (response is TextResponse) {
            chunks.add(response.token);
          }
        }
      });

      final responseText = chunks.join();
      print('Response: "${responseText.length > 100 ? responseText.substring(0, 100) : responseText}"');

      expect(responseText, isNotEmpty);
      expect(responseText.length, greaterThan(1));
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
