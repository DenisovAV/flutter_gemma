// End-to-end check that the quickstart's own API path works: install a model,
// open a chat, stream a reply. Uses the ungated Qwen3 build so it needs no
// Hugging Face token.
//
// Not part of CI — it downloads ~0.6 GB and needs a real device:
//   flutter test integration_test/quickstart_test.dart -d macos
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gemma_quickstart/model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('install, then stream a reply', (tester) async {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

    const model = Models.qwen3;

    if (!await FlutterGemma.isModelInstalled(model.fileName)) {
      var last = -1;
      await FlutterGemma.installModel(
        modelType: model.modelType,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(model.url).withProgress((p) {
        if (p >= last + 25) {
          last = p;
          debugPrint('[quickstart] download $p%');
        }
      }).install();
    }
    expect(await FlutterGemma.isModelInstalled(model.fileName), isTrue);

    final inference = await FlutterGemma.getActiveModel(maxTokens: 1024);
    final chat = await inference.createChat(
      modelType: model.modelType,
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

    debugPrint('[quickstart] reply: ${buffer.toString().trim()}');
    expect(buffer.toString().trim(), isNotEmpty);

    await inference.close();
  }, timeout: const Timeout(Duration(minutes: 30)));
}
