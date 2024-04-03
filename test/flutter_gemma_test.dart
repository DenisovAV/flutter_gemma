import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/flutter_gemma_platform_interface.dart';
import 'package:flutter_gemma/flutter_gemma_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterGemmaPlatform
    with MockPlatformInterfaceMixin
    implements FlutterGemmaPlatform {

  @override
  Future<String?> getResponse(String prompt) => Future.value('response');
}

void main() {
  final FlutterGemmaPlatform initialPlatform = FlutterGemmaPlatform.instance;

  test('$MethodChannelFlutterGemma is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterGemma>());
  });

  test('getPlatformVersion', () async {
    FlutterGemma flutterGemmaPlugin = FlutterGemma();
    MockFlutterGemmaPlatform fakePlatform = MockFlutterGemmaPlatform();
    FlutterGemmaPlatform.instance = fakePlatform;

    expect(await flutterGemmaPlugin.getResponse('prompt'), 'response');
  });
}
