// End-to-end check of the engine switch on a real device or emulator.
//
// Exercises both arms of the startup policy: the built-in model is probed and
// either used or — on a device without one, e.g. an emulator — reported as a
// typed BuiltInAiUnavailableException; the downloaded model then answers on
// LiteRT-LM. Uses the ungated Qwen3 build so it needs no Hugging Face token.
//
// Not part of CI (needs a device, may download ~0.6 GB):
//   flutter test integration_test/engines_test.dart -d <device-id>
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gemma_quickstart/download_page.dart';
import 'package:gemma_quickstart/model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe the OS model, fall back to LiteRT-LM, stream a reply', (
    tester,
  ) async {
    await FlutterGemma.initialize(
      inferenceEngines: [LiteRtLmEngine(), const BuiltInAiEngine()],
    );

    final status = await BuiltInAi.availability();
    debugPrint('[engines] built-in availability: $status');

    final builtInUsable = switch (status) {
      BuiltInAiAvailability.available ||
      BuiltInAiAvailability.downloadable ||
      BuiltInAiAvailability.downloading => true,
      _ => false,
    };

    if (!builtInUsable) {
      // The failure must be typed, not a generic platform error — that is
      // what lets the app pick a fallback instead of crashing.
      await expectLater(
        activate(Models.builtIn),
        throwsA(isA<BuiltInAiUnavailableException>()),
      );
      debugPrint(
        '[engines] built-in refused with a typed exception, as designed',
      );
    } else {
      await activate(Models.builtIn);
      debugPrint('[engines] built-in model activated');
    }

    // Whatever the OS said, the downloaded model must work on this device.
    const fallback = Models.qwen3;
    var last = -1;
    await activate(
      fallback,
      onProgress: (p) {
        if (p >= last + 25) {
          last = p;
          debugPrint('[engines] download $p%');
        }
      },
    );
    expect(await FlutterGemma.isModelInstalled(fallback.id), isTrue);

    final inference = await FlutterGemma.getActiveModel(maxTokens: 1024);
    final chat = await inference.createChat(
      modelType: fallback.modelType,
      maxOutputTokens: 64,
    );
    await chat.addQueryChunk(
      Message.text(
        text: 'Name one planet. Answer in three words.',
        isUser: true,
      ),
    );
    final buffer = StringBuffer();
    await for (final chunk in chat.generateChatResponseAsync()) {
      if (chunk is TextResponse) buffer.write(chunk.token);
    }
    debugPrint('[engines] reply via LiteRT-LM: ${buffer.toString().trim()}');
    expect(buffer.toString().trim(), isNotEmpty);

    await inference.close();
  }, timeout: const Timeout(Duration(minutes: 30)));
}
