// Direct gRPC test for Desktop LiteRT-LM server
// Run with: dart run bin/test_grpc_chat.dart

import 'dart:io';
import 'package:grpc/grpc.dart';

// Import generated proto files
import 'package:flutter_gemma/desktop/generated/litertlm.pb.dart';
import 'package:flutter_gemma/desktop/generated/litertlm.pbgrpc.dart';

Future<void> main() async {
  print('=== Direct gRPC Test for Desktop LiteRT-LM ===\n');

  // Find the model path
  final homeDir = Platform.environment['HOME'] ?? '/Users/sashadenisov';
  final modelPath = '$homeDir/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';

  final modelFile = File(modelPath);
  if (!await modelFile.exists()) {
    print('ERROR: Model file not found at: $modelPath');
    print('Please install the model first via the example app.');
    exit(1);
  }
  print('Model found: $modelPath\n');

  // Start the server process
  print('Starting gRPC server...');
  final jarPath = '/Users/sashadenisov/Work/1/flutter_gemma/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar';
  final nativesPath = '/Users/sashadenisov/Work/1/flutter_gemma/example/build/macos/Build/Products/Debug/flutter_gemma_example.app/Contents/Frameworks/litertlm';

  final jarFile = File(jarPath);
  if (!await jarFile.exists()) {
    print('ERROR: JAR file not found at: $jarPath');
    print('Build it with: cd litertlm-server && ./gradlew shadowJar');
    exit(1);
  }

  final serverProcess = await Process.start(
    'java',
    [
      '-Djava.library.path=$nativesPath',
      '-jar', jarPath,
      '50099', // Use a specific port for testing
    ],
    environment: Platform.environment,
  );

  // Forward server output
  serverProcess.stdout.transform(const SystemEncoding().decoder).listen((data) {
    print('[SERVER] $data');
  });
  serverProcess.stderr.transform(const SystemEncoding().decoder).listen((data) {
    print('[SERVER ERROR] $data');
  });

  // Wait for server to start
  print('Waiting for server to start...');
  await Future.delayed(const Duration(seconds: 5));

  // Create gRPC client
  final channel = ClientChannel(
    'localhost',
    port: 50099,
    options: const ChannelOptions(
      credentials: ChannelCredentials.insecure(),
    ),
  );

  final client = LiteRtLmServiceClient(channel);

  try {
    // Initialize the engine
    print('\n=== Step 1: Initialize engine ===');
    final initRequest = InitializeRequest()
      ..modelPath = modelPath
      ..backend = 'gpu'
      ..maxTokens = 512
      ..enableVision = false
      ..enableAudio = false;

    final initResponse = await client.initialize(initRequest);
    print('Initialize response: success=${initResponse.success}, error=${initResponse.error}');

    if (!initResponse.success) {
      print('ERROR: Failed to initialize engine');
      serverProcess.kill();
      exit(1);
    }

    // Create conversation
    print('\n=== Step 2: Create conversation ===');
    final convRequest = CreateConversationRequest();
    final convResponse = await client.createConversation(convRequest);
    print('Conversation created: ${convResponse.conversationId}');

    final conversationId = convResponse.conversationId;

    // Send simple text chat
    print('\n=== Step 3: Send "Hi" ===');
    final chatRequest = ChatRequest()
      ..conversationId = conversationId
      ..text = 'Hi';

    final chatResponseStream = client.chat(chatRequest);
    final responseBuffer = StringBuffer();

    await for (final response in chatResponseStream) {
      if (response.hasError() && response.error.isNotEmpty) {
        print('ERROR: ${response.error}');
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

    print('\nFull response: ${responseBuffer.toString()}');
    print('Response length: ${responseBuffer.length}');

    // Close conversation
    print('\n=== Step 4: Close conversation ===');
    final closeRequest = CloseConversationRequest()
      ..conversationId = conversationId;
    await client.closeConversation(closeRequest);
    print('Conversation closed');

    // Shutdown
    print('\n=== Step 5: Shutdown ===');
    await client.shutdown(ShutdownRequest());
    print('Shutdown complete');

  } catch (e, st) {
    print('ERROR: $e');
    print(st);
  } finally {
    await channel.shutdown();
    serverProcess.kill();
    print('\nTest complete.');
  }
}
