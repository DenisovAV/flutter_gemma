import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlutterGemma platform = FlutterGemma();
  const MethodChannel channel = MethodChannel('flutter_gemma');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return 'response';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    final model = await platform.createModel(modelType: ModelType.general);
    final session = await model.createSession();
    expect(await session.getResponse(), 'response');
  });
}
