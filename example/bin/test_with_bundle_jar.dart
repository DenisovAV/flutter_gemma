// Test using JAR from app bundle - EXACTLY like Flutter app
// Run with: dart run bin/test_with_bundle_jar.dart

import 'dart:io';
import 'package:grpc/grpc.dart';

import 'package:flutter_gemma/desktop/generated/litertlm.pb.dart';
import 'package:flutter_gemma/desktop/generated/litertlm.pbgrpc.dart';

Future<void> main() async {
  print('=== Test with Bundle JAR (like Flutter app) ===\n');

  // Paths matching EXACTLY what Flutter app uses
  final homeDir = Platform.environment['HOME'] ?? '/Users/sashadenisov';
  final modelPath = '$homeDir/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';

  // Use JAR from bundle (same as ServerProcessManager uses)
  final jarPath = '/Users/sashadenisov/Work/1/flutter_gemma/example/build/macos/Build/Products/Debug/flutter_gemma_example.app/Contents/Resources/litertlm-server.jar';
  final nativesPath = '/Users/sashadenisov/Work/1/flutter_gemma/example/build/macos/Build/Products/Debug/flutter_gemma_example.app/Contents/Frameworks/litertlm';

  // Use system Java (bundled JRE has sandbox issues outside of Flutter)
  final javaPath = 'java';

  // Verify files exist
  for (final file in [modelPath, jarPath]) {
    if (!await File(file).exists()) {
      print('ERROR: File not found: $file');
      exit(1);
    }
  }
  if (!await Directory(nativesPath).exists()) {
    print('ERROR: Directory not found: $nativesPath');
    exit(1);
  }
  print('✓ All paths verified\n');

  print('Using:');
  print('  JAR: $jarPath');
  print('  Java: $javaPath');
  print('  Natives: $nativesPath');
  print('  Model: $modelPath\n');

  // Start server
  print('Starting gRPC server on port 50098...');
  final serverProcess = await Process.start(
    javaPath,
    [
      '-Djava.library.path=$nativesPath',
      '-Xmx2048m',
      '-jar', jarPath,
      '50098',
    ],
    environment: {
      'DYLD_LIBRARY_PATH': nativesPath,
    },
  );

  // Capture server output
  serverProcess.stdout.transform(const SystemEncoding().decoder).listen((data) {
    print('[SERVER] $data');
  });
  serverProcess.stderr.transform(const SystemEncoding().decoder).listen((data) {
    print('[SERVER ERR] $data');
  });

  print('Waiting 10s for server to start...\n');
  await Future.delayed(const Duration(seconds: 10));

  // Create gRPC client
  final channel = ClientChannel(
    'localhost',
    port: 50098,
    options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
  );
  final client = LiteRtLmServiceClient(channel);

  try {
    // Initialize with SAME params as Flutter app (gemma3n_2B model)
    print('=' * 60);
    print('Initialize with params from gemma3n_2B model:');
    print('  enableVision: TRUE');
    print('  enableAudio: TRUE');
    print('  backend: gpu');
    print('  maxTokens: 512');
    print('=' * 60);

    final initRequest = InitializeRequest()
      ..modelPath = modelPath
      ..backend = 'gpu'
      ..maxTokens = 512
      ..enableVision = true
      ..enableAudio = true
      ..maxNumImages = 1;

    final initResponse = await client.initialize(initRequest);
    print('Initialize: success=${initResponse.success}, error="${initResponse.error}"');

    if (!initResponse.success) {
      print('❌ FAILED to initialize');
      serverProcess.kill();
      exit(1);
    }
    print('✓ Initialize succeeded\n');

    // Create conversation
    print('Creating conversation...');
    final convResponse = await client.createConversation(CreateConversationRequest());
    final conversationId = convResponse.conversationId;
    print('✓ Conversation: $conversationId\n');

    // Send text-only chat
    print('=' * 60);
    print('Sending TEXT-ONLY chat: "Hi"');
    print('=' * 60);

    final chatRequest = ChatRequest()
      ..conversationId = conversationId
      ..text = 'Hi';

    final responseBuffer = StringBuffer();
    await for (final response in client.chat(chatRequest)) {
      if (response.hasError() && response.error.isNotEmpty) {
        print('\n❌ ERROR: ${response.error}');
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

    print('\n');
    if (responseBuffer.isEmpty) {
      print('❌ FAILED: Empty response');
    } else {
      print('✓ SUCCESS! Response (${responseBuffer.length} chars)');
    }

    // Cleanup
    await client.closeConversation(CloseConversationRequest()..conversationId = conversationId);
    await client.shutdown(ShutdownRequest());
    print('✓ Cleanup done');

  } catch (e, st) {
    print('\n❌ EXCEPTION: $e');
    print(st);
  } finally {
    await channel.shutdown();
    serverProcess.kill();
    print('\n=== Test complete ===');
  }
}
