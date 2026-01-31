// Test that mimics EXACTLY how Flutter app calls gRPC
// Run with: dart run bin/test_flutter_like_grpc.dart
//
// This test uses enableVision=true, enableAudio=true just like Flutter app does

import 'dart:io';
import 'package:grpc/grpc.dart';

import 'package:flutter_gemma/desktop/generated/litertlm.pb.dart';
import 'package:flutter_gemma/desktop/generated/litertlm.pbgrpc.dart';

Future<void> main() async {
  print('=== Flutter-Like gRPC Test ===');
  print('This test mimics EXACTLY how Flutter app calls the gRPC server\n');

  // Find model and paths
  final homeDir = Platform.environment['HOME'] ?? '/Users/sashadenisov';
  final modelPath = '$homeDir/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';
  final jarPath = '/Users/sashadenisov/Work/1/flutter_gemma/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar';
  final nativesPath = '/Users/sashadenisov/Work/1/flutter_gemma/example/build/macos/Build/Products/Debug/flutter_gemma_example.app/Contents/Frameworks/litertlm';

  // Verify files exist
  if (!await File(modelPath).exists()) {
    print('ERROR: Model not found: $modelPath');
    exit(1);
  }
  if (!await File(jarPath).exists()) {
    print('ERROR: JAR not found: $jarPath');
    print('Build with: cd litertlm-server && ./gradlew fatJar');
    exit(1);
  }
  print('✓ Model found: $modelPath');
  print('✓ JAR found: $jarPath\n');

  // Start server
  print('Starting gRPC server on port 50099...');
  final serverProcess = await Process.start(
    'java',
    ['-Djava.library.path=$nativesPath', '-jar', jarPath, '50099'],
    environment: Platform.environment,
  );

  // Capture server output
  final serverOutput = StringBuffer();
  serverProcess.stdout.transform(const SystemEncoding().decoder).listen((data) {
    serverOutput.write(data);
    print('[SERVER] $data');
  });
  serverProcess.stderr.transform(const SystemEncoding().decoder).listen((data) {
    serverOutput.write(data);
    print('[SERVER ERR] $data');
  });

  // Wait for server startup
  print('Waiting 5s for server to start...\n');
  await Future.delayed(const Duration(seconds: 5));

  // Create gRPC client
  final channel = ClientChannel(
    'localhost',
    port: 50099,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final client = LiteRtLmServiceClient(channel);

  try {
    // ============================================
    // TEST 1: Initialize with enableVision=TRUE, enableAudio=TRUE
    // This is EXACTLY what Flutter app does!
    // ============================================
    print('=' * 60);
    print('TEST 1: Initialize with enableVision=TRUE, enableAudio=TRUE');
    print('=' * 60);

    final initRequest = InitializeRequest()
      ..modelPath = modelPath
      ..backend = 'gpu'
      ..maxTokens = 512
      ..enableVision = false   // <-- DISABLED - LiteRT-LM bug #684
      ..enableAudio = true     // <-- Flutter app uses TRUE
      ..maxNumImages = 1;

    print('Sending InitializeRequest:');
    print('  modelPath: $modelPath');
    print('  backend: gpu');
    print('  maxTokens: 512');
    print('  enableVision: FALSE (bug #684)');
    print('  enableAudio: TRUE');

    final initResponse = await client.initialize(initRequest);
    print('\nInitialize response:');
    print('  success: ${initResponse.success}');
    print('  error: "${initResponse.error}"');
    print('  modelInfo: "${initResponse.modelInfo}"');

    if (!initResponse.success) {
      print('\n❌ FAILED: Initialize failed with enableVision=true, enableAudio=true');
      print('Error: ${initResponse.error}');
      serverProcess.kill();
      exit(1);
    }
    print('✓ Initialize succeeded\n');

    // ============================================
    // TEST 2: Create conversation
    // ============================================
    print('=' * 60);
    print('TEST 2: Create conversation');
    print('=' * 60);

    final convResponse = await client.createConversation(CreateConversationRequest());
    if (convResponse.hasError() && convResponse.error.isNotEmpty) {
      print('❌ FAILED: ${convResponse.error}');
      serverProcess.kill();
      exit(1);
    }
    final conversationId = convResponse.conversationId;
    print('✓ Conversation created: $conversationId\n');

    // ============================================
    // TEST 3: Send TEXT-ONLY chat (no audio, no image)
    // This is where Flutter app FAILS with jinja error
    // ============================================
    print('=' * 60);
    print('TEST 3: Send TEXT-ONLY chat "Hi"');
    print('(enableVision=true, enableAudio=true but sending plain text)');
    print('=' * 60);

    final chatRequest = ChatRequest()
      ..conversationId = conversationId
      ..text = 'Hi';

    print('Sending ChatRequest:');
    print('  conversationId: $conversationId');
    print('  text: "Hi"');
    print('\nStreaming response:');

    final responseBuffer = StringBuffer();
    var gotError = false;

    await for (final response in client.chat(chatRequest)) {
      if (response.hasError() && response.error.isNotEmpty) {
        print('\n❌ ERROR from server: ${response.error}');
        gotError = true;
        break;
      }
      if (response.hasText()) {
        responseBuffer.write(response.text);
        stdout.write(response.text);
      }
      if (response.done) {
        print('\n[DONE]');
        break;
      }
    }

    if (gotError) {
      print('\n❌ FAILED: Text-only chat failed with enableVision/enableAudio=true');
      print('\nThis is the bug! Server initialized with multimodal=true but');
      print('text-only chat fails. Check server logs above for jinja error.');
    } else if (responseBuffer.isEmpty) {
      print('\n❌ FAILED: Got empty response');
    } else {
      print('\n✓ SUCCESS! Got response: "${responseBuffer.toString().substring(0, responseBuffer.length > 100 ? 100 : responseBuffer.length)}..."');
      print('Response length: ${responseBuffer.length} chars');
    }

    // ============================================
    // TEST 4: Close conversation and shutdown
    // ============================================
    print('\n' + '=' * 60);
    print('TEST 4: Cleanup');
    print('=' * 60);

    await client.closeConversation(CloseConversationRequest()..conversationId = conversationId);
    print('✓ Conversation closed');

    await client.shutdown(ShutdownRequest());
    print('✓ Engine shutdown');

  } catch (e, st) {
    print('\n❌ EXCEPTION: $e');
    print(st);
  } finally {
    await channel.shutdown();
    serverProcess.kill();
    print('\n=== Test complete ===');
  }
}
