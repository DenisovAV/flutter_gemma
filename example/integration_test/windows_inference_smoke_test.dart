// Quick inference smoke on Windows: install gemma-4-E2B-it.litertlm
// from a known local path, generate a short response. Used to confirm
// LiteRT-LM still works after the qdrant integration changes.

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelPath = r'C:\Users\devcloud\models\gemma-4-E2B-it.litertlm';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows inference smoke', (tester) async {
    await FlutterGemma.initialize();
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(_modelPath).install();

    final model = await FlutterGemma.getActiveModel(maxTokens: 128);
    final session = await model.createSession(temperature: 0.8, topK: 1);
    await session
        .addQueryChunk(const Message(text: 'Say hi in one word', isUser: true));
    final r = await session.getResponse();
    // ignore: avoid_print
    print('[win-inf] response: "$r"');
    expect(r, isNotEmpty);
    await session.close();
    await model.close();
  });
}
