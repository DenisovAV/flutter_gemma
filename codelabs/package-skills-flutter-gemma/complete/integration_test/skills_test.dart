// End-to-end check of the finished app's own API path: install Gemma 4 E2B,
// open a chat with the colour tool, and ask for a colour change.
//
// Not part of CI — it downloads ~2.6 GB and needs a real device or desktop:
//   flutter test integration_test/skills_test.dart -d <device-id>
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_skills/color_tool.dart';
import 'package:gemma_skills/model.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('install, then let the model call the colour tool', (
    tester,
  ) async {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

    const model = Models.gemma4;

    // Unconditionally: install() skips bytes it already has and re-activates
    // the model, so a previous run cannot leave a different model active.
    var last = -1;
    await FlutterGemma.installModel(
      modelType: model.modelType,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(model.url).withProgress((p) {
      if (p >= last + 25) {
        last = p;
        debugPrint('[skills] download $p%');
      }
    }).install();

    expect(await FlutterGemma.isModelInstalled(model.fileName), isTrue);

    final inference = await FlutterGemma.getActiveModel(maxTokens: 1024);
    final chat = await inference.createChat(
      tools: const [ColorTool.declaration],
      supportsFunctionCalls: true,
      modelType: model.modelType,
      maxOutputTokens: 256,
    );

    await chat.addQueryChunk(
      Message.text(text: 'Make the app green.', isUser: true),
    );

    final calls = <FunctionCallResponse>[];
    final reply = StringBuffer();
    await for (final chunk in chat.generateChatResponseWithTools(
      onToolCall: (call) {
        calls.add(call);
        return ColorTool.run(call.name, call.args).result;
      },
    )) {
      if (chunk is TextResponse) reply.write(chunk.token);
    }

    debugPrint('[skills] calls: ${calls.map((c) => '${c.name}${c.args}')}');
    debugPrint('[skills] reply: ${reply.toString().trim()}');

    expect(calls, isNotEmpty, reason: 'the model never called the tool');
    expect(calls.first.name, ColorTool.name);
    expect('${calls.first.args['color']}'.toLowerCase(), contains('green'));
    expect(
      reply.toString(),
      isNot(contains('tool_call')),
      reason: 'raw tool-call JSON leaked into the reply text',
    );

    await chat.close();
    await inference.close();
  }, timeout: const Timeout(Duration(minutes: 30)));
}
