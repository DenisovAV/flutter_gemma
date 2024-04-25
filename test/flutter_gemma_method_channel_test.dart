import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlutterGemma platform = FlutterGemma();
  const MethodChannel channel = MethodChannel('flutter_gemma');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
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
    expect(await platform.getResponse(prompt: 'prompt'), 'response');
  });
}
