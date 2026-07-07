import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late bool available;

  setUpAll(() async {
    await FlutterGemma.initialize(inferenceEngines: const [BuiltInAiEngine()]);
    final status = await BuiltInAi.availability();
    available = status == BuiltInAiAvailability.available;
    if (!available && status == BuiltInAiAvailability.downloadable) {
      try {
        await BuiltInAi.ensureReady(timeout: const Duration(minutes: 8));
        available = true;
      } catch (_) {/* stays skipped */}
    }
    if (available) {
      final spec = defaultTargetPlatform == TargetPlatform.android
          ? BuiltInAiModels.geminiNano
          : BuiltInAiModels.appleFoundationModels;
      await FlutterGemma.installModel(
        modelType: spec.modelType, fileType: spec.fileType,
      ).fromBundled(spec.name).install();
    }
  });

  test('single-shot generation', () async {
    if (!available) return markTestSkipped('BuiltInAI not available on this device');
    final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
    final session = await model.createSession();
    await session.addQueryChunk(const Message(text: 'Reply with exactly: PONG', isUser: true));
    final response = await session.getResponse();
    expect(response.toUpperCase(), contains('PONG'));
    await session.close();
    await model.close();
  });

  test('streaming yields incremental deltas then completes', () async {
    if (!available) return markTestSkipped('BuiltInAI not available on this device');
    final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
    final session = await model.createSession();
    await session.addQueryChunk(const Message(text: 'Count from 1 to 5.', isUser: true));
    final chunks = await session.getResponseAsync().toList();
    expect(chunks, isNotEmpty);
    expect(chunks.join(), isNotEmpty);
    await session.close();
    await model.close();
  });

  test('multi-turn chat keeps context', () async {
    if (!available) return markTestSkipped('BuiltInAI not available on this device');
    final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
    final chat = await model.createChat(supportImage: false);
    await chat.addQueryChunk(const Message(text: 'My name is Sasha. Say hi.', isUser: true));
    await chat.generateChatResponse();
    await chat.addQueryChunk(const Message(text: 'What is my name?', isUser: true));
    final answer = await chat.generateChatResponse();
    expect(answer.toString().toLowerCase(), contains('sasha'));
    await model.close();
  });

  test('sizeInTokens returns a positive count', () async {
    if (!available) return markTestSkipped('BuiltInAI not available on this device');
    final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
    final session = await model.createSession();
    expect(await session.sizeInTokens('Hello world, four words plus.'), greaterThan(0));
    await session.close();
    await model.close();
  });
}
