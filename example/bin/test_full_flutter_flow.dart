// Full Flutter flow test - uses SAME classes as Flutter app
// Run with: dart run bin/test_full_flutter_flow.dart
//
// This mimics exactly how Flutter app works:
// 1. ServerProcessManager.start() - starts server using bundled JAR
// 2. LiteRtLmClient.connect() - connects to server
// 3. LiteRtLmClient.initialize() - initializes model with enableVision/enableAudio
// 4. LiteRtLmClient.createConversation() - creates conversation
// 5. LiteRtLmClient.chat() - sends text message

import 'dart:io';
import 'package:flutter_gemma/desktop/grpc_client.dart';
import 'package:flutter_gemma/desktop/server_process_manager.dart';

Future<void> main() async {
  print('=== Full Flutter Flow Test ===');
  print('Using SAME ServerProcessManager and LiteRtLmClient as Flutter app\n');

  // Find model path
  final homeDir = Platform.environment['HOME'] ?? '/Users/sashadenisov';
  final modelPath = '$homeDir/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';

  if (!await File(modelPath).exists()) {
    print('ERROR: Model not found: $modelPath');
    exit(1);
  }
  print('✓ Model found: $modelPath\n');

  final serverManager = ServerProcessManager.instance;
  LiteRtLmClient? client;

  try {
    // Step 1: Start server using ServerProcessManager (same as Flutter)
    print('=' * 60);
    print('Step 1: Start server via ServerProcessManager');
    print('=' * 60);

    await serverManager.start();
    print('✓ Server started on port ${serverManager.port}\n');

    // Step 2: Connect gRPC client
    print('=' * 60);
    print('Step 2: Connect LiteRtLmClient');
    print('=' * 60);

    client = LiteRtLmClient();
    await client.connect();
    print('✓ Client connected\n');

    // Step 3: Initialize with enableVision=true, enableAudio=true (like Flutter)
    print('=' * 60);
    print('Step 3: Initialize model');
    print('=' * 60);
    print('  modelPath: $modelPath');
    print('  backend: gpu');
    print('  maxTokens: 512');
    print('  enableVision: TRUE (like Flutter app)');
    print('  enableAudio: TRUE (like Flutter app)');

    await client.initialize(
      modelPath: modelPath,
      backend: 'gpu',
      maxTokens: 512,
      enableVision: true,
      enableAudio: true,
    );
    print('✓ Model initialized\n');

    // Step 4: Create conversation
    print('=' * 60);
    print('Step 4: Create conversation');
    print('=' * 60);

    final conversationId = await client.createConversation();
    print('✓ Conversation created: $conversationId\n');

    // Step 5: Send TEXT-ONLY chat
    print('=' * 60);
    print('Step 5: Send TEXT-ONLY chat "Hi"');
    print('=' * 60);

    final responseBuffer = StringBuffer();
    var gotError = false;

    await for (final token in client.chat('Hi')) {
      responseBuffer.write(token);
      stdout.write(token);
    }

    print('\n');

    if (responseBuffer.isEmpty) {
      print('❌ FAILED: Got empty response');
      gotError = true;
    } else {
      print('✓ SUCCESS!');
      print('Response: "${responseBuffer.toString()}"');
      print('Length: ${responseBuffer.length} chars');
    }

    // Step 6: Cleanup
    print('\n' + '=' * 60);
    print('Step 6: Cleanup');
    print('=' * 60);

    await client.closeConversation();
    print('✓ Conversation closed');

    await client.shutdown();
    print('✓ Engine shutdown');

    if (!gotError) {
      print('\n✅ ALL TESTS PASSED - Flutter flow works correctly!');
    }

  } catch (e, st) {
    print('\n❌ EXCEPTION: $e');
    print(st);
  } finally {
    await client?.disconnect();
    await serverManager.stop();
    print('\n=== Test complete ===');
  }
}
