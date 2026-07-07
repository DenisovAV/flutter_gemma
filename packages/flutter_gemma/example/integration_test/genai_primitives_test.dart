import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/genai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sendMessage returns a model ChatMessage with text', (
    tester,
  ) async {
    final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
    final chat = await model.createChat();
    final reply = await chat.sendMessage(
      ChatMessage.user('Say hello in one word.'),
    );
    expect(reply.role, ChatMessageRole.model);
    expect(
      reply.parts.whereType<TextPart>().map((p) => p.text).join(),
      isNotEmpty,
    );
    await chat.session.close();
    await model.close();
  });

  testWidgets('sendMessageStream emits partial model ChatMessages', (
    tester,
  ) async {
    final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
    final chat = await model.createChat();
    final chunks = <ChatMessage>[];
    await for (final c in chat.sendMessageStream(
      ChatMessage.user('Count to three.'),
    )) {
      chunks.add(c);
    }
    expect(chunks, isNotEmpty);
    expect(chunks.every((c) => c.role == ChatMessageRole.model), isTrue);
    await chat.session.close();
    await model.close();
  });
}
