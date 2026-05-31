import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS device: FFI engine create + chat', (tester) async {
    await FlutterGemma.initialize();

    // Install model from network (Gemma 3 1B, smallest)
    print('Installing model...');
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
      token: const String.fromEnvironment('HUGGINGFACE_TOKEN'),
    ).install();
    print('Model installed');

    // Create model via plugin
    final model = await FlutterGemma.getActiveModel(
      maxTokens: 512,
      preferredBackend: PreferredBackend.cpu,
    );
    print('Model created');

    // Create session
    final session = await model.createSession(temperature: 0.8, topK: 1);
    print('Session created');

    // Chat
    await session.addQueryChunk(const Message(text: 'Say hi', isUser: true));
    final response = await session.getResponse();
    print('Response: $response');
    expect(response, isNotEmpty);

    await session.close();
    await model.close();
    print('iOS DEVICE TEST PASSED');
  });
}
