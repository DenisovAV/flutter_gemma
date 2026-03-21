// Integration test: Android dual engine (MediaPipe + LiteRT-LM).
// Run: flutter test integration_test/inference_dual_engine_test.dart -d <android_device>
// Skipped on non-Android platforms.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'inference_test_helpers.dart';

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

void main() {
  initIntegrationTest();

  testWidgets(
    'Inference: Android dual engine MediaPipe + LiteRT-LM',
    skip: !_isAndroid,
    (tester) async {
      await FlutterGemma.initialize();

      // --- Engine 1: MediaPipe (.task) ---
      print('[DualEngine] Testing MediaPipe (.task)...');
      await ensureModelInstalled(TestModelConfig.mediapipeConfig);

      var model = await createTestModel();
      try {
        final chat1 = await createTestChat(model);
        await chat1.addQueryChunk(
            const Message(text: 'Say hello', isUser: true));
        final response1 = await chat1.generateChatResponse();
        expect(response1, isA<TextResponse>());
        final text1 = (response1 as TextResponse).token;
        print(
            '[DualEngine] MediaPipe response: "${text1.length > 80 ? text1.substring(0, 80) : text1}"');
        expect(text1, isNotEmpty);
      } finally {
        await model.close();
      }

      // --- Engine 2: LiteRT-LM (.litertlm) ---
      print('[DualEngine] Testing LiteRT-LM (.litertlm)...');

      // Install .litertlm model (different file, same weights)
      const litertlmConfig = TestModelConfig.litertlmConfig;
      await FlutterGemma.installModel(
        modelType: ModelType.functionGemma,
        fileType: litertlmConfig.fileType,
      )
          .fromNetwork(litertlmConfig.url)
          .withProgress((progress) =>
              print('[DualEngine] LiteRT-LM download: $progress%'))
          .install();

      model = await createTestModel();
      try {
        final chat2 = await createTestChat(model);
        await chat2.addQueryChunk(
            const Message(text: 'Say hello', isUser: true));
        final response2 = await chat2.generateChatResponse();
        expect(response2, isA<TextResponse>());
        final text2 = (response2 as TextResponse).token;
        print(
            '[DualEngine] LiteRT-LM response: "${text2.length > 80 ? text2.substring(0, 80) : text2}"');
        expect(text2, isNotEmpty);
      } finally {
        await model.close();
      }

      print('[DualEngine] Both engines work on Android!');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
