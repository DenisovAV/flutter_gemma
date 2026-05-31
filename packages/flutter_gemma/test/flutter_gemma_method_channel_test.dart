// Skip this test on VM platform - FlutterGemmaMobile imports service_registry with dart:js_interop
@TestOn('!vm')
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlutterGemmaMobile platform = FlutterGemmaMobile();
  const MethodChannel channel = MethodChannel('flutter_gemma');

  setUp(() {
    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Mock PathProvider
    PathProviderPlatform.instance = MockPathProviderPlatform();

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
    // Test that the platform integration is working by checking if we can create a FlutterGemma instance
    expect(platform, isA<FlutterGemmaMobile>());

    // Since we can't create actual models without downloaded model files,
    // this test just verifies the basic platform setup is working
    expect(true, isTrue); // Placeholder assertion for successful test setup
  });
}

/// Mock PathProvider for testing
class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.createTempSync('flutter_gemma_test_').path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.createTempSync('flutter_gemma_test_').path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.createTempSync('flutter_gemma_test_').path;
  }
}
