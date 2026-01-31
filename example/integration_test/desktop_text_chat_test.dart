// Integration test for Desktop text chat
// Run with: flutter test integration_test/desktop_text_chat_test.dart -d macos
//
// This test runs inside real Flutter environment and tests:
// 1. Server startup (via ServerProcessManager)
// 2. LiteRtLmClient connection and initialization
// 3. Text chat functionality

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_gemma/desktop/grpc_client.dart';
import 'package:flutter_gemma/desktop/server_process_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LiteRtLmClient client;
  String modelPath = '';

  setUpAll(() async {
    // Find model - try multiple possible locations
    final possiblePaths = [
      '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm',
      '${Platform.environment['HOME']}/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm',
    ];

    for (final path in possiblePaths) {
      if (await File(path).exists()) {
        modelPath = path;
        break;
      }
    }

    if (modelPath.isEmpty || !await File(modelPath).exists()) {
      fail('Model not found in any of: $possiblePaths');
    }

    // Start server
    final serverManager = ServerProcessManager.instance;
    if (!serverManager.isRunning) {
      await serverManager.start();
    }

    // Wait for server
    await Future.delayed(const Duration(seconds: 5));

    // Connect client
    client = LiteRtLmClient();
    await client.connect();
  });

  tearDownAll(() async {
    try {
      await client.shutdown();
      await client.disconnect();
    } catch (_) {}

    try {
      await ServerProcessManager.instance.stop();
    } catch (_) {}
  });

  testWidgets('Initialize model with enableVision=false (bug #684 fix)', (tester) async {
    // This tests the FIXED behavior - enableVision must be false on Desktop
    await client.initialize(
      modelPath: modelPath,
      backend: 'gpu',
      maxTokens: 512,
      enableVision: false,  // FIX for LiteRT-LM bug #684
      enableAudio: true,
      maxNumImages: 1,
    );

    expect(client.isInitialized, isTrue);
  });

  testWidgets('Create conversation', (tester) async {
    final convId = await client.createConversation(
      temperature: 0.8,
      topK: 40,
    );

    expect(convId, isNotEmpty);
    expect(client.conversationId, equals(convId));
  });

  testWidgets('Text chat returns response', (tester) async {
    final buffer = StringBuffer();

    await tester.runAsync(() async {
      await for (final chunk in client.chat('Hi')) {
        buffer.write(chunk);
      }
    });

    expect(buffer.toString(), isNotEmpty);
    expect(buffer.length, greaterThan(10));
  });

  testWidgets('Follow-up message works', (tester) async {
    final buffer = StringBuffer();

    await tester.runAsync(() async {
      await for (final chunk in client.chat('What is 2+2?')) {
        buffer.write(chunk);
      }
    });

    expect(buffer.toString(), isNotEmpty);
    expect(buffer.toString().toLowerCase(), contains('4'));
  });

  testWidgets('Close conversation', (tester) async {
    await client.closeConversation();
    expect(client.conversationId, isNull);
  });
}
