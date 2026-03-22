// Integration test: model download, caching, and basic inference.
// Run: flutter test integration_test/inference_download_test.dart -d <device>

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'inference_test_helpers.dart';

void main() {
  initIntegrationTest();

  for (final (:config, :label) in TestModelConfig.allForCurrentPlatform()) {
    _runDownloadTest(config, label);
  }
}

void _runDownloadTest(TestModelConfig config, String label) {
  testWidgets('Inference: model download and cache ($label)', (tester) async {
    // 1. Initialize
    await FlutterGemma.initialize();

    // 2. Download model
    await FlutterGemma.installModel(
      modelType: ModelType.functionGemma,
      fileType: config.fileType,
    )
        .fromNetwork(config.url)
        .withProgress((progress) => print('[Download/$label] Progress: $progress%'))
        .install();

    // 3. Verify active model
    expect(FlutterGemma.hasActiveModel(), isTrue,
        reason: 'Active model should be set after install');

    // 4. Verify model installed on disk
    final isInstalled = await FlutterGemma.isModelInstalled(config.filename);
    expect(isInstalled, isTrue, reason: 'Model file should exist on disk');

    // 5. Cache check — second install should be instant (no re-download)
    final stopwatch = Stopwatch()..start();
    await ensureModelInstalled(config);
    stopwatch.stop();
    print('[Cache/$label] Second install took ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsedMilliseconds, lessThan(5000),
        reason: 'Cached model should not trigger re-download');

    // 6. Quick inference sanity check
    final model = await createTestModel();
    try {
      final chat = await createTestChat(model);
      await chat.addQueryChunk(
          const Message(text: 'Say hi', isUser: true));
      final response = await chat.generateChatResponse();
      expect(response, isA<TextResponse>());
      final text = (response as TextResponse).token;
      print(
          '[Inference/$label] Response: "${text.length > 100 ? text.substring(0, 100) : text}"');
      expect(text, isNotEmpty,
          reason: 'Model should produce non-empty response');
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
