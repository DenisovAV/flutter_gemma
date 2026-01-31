// Test using REAL LiteRtLmClient from lib/desktop/grpc_client.dart
// This tests the actual production code, not a copy
//
// Run with: dart run bin/test_real_grpc_client.dart

import 'dart:io';

import 'package:flutter_gemma/desktop/grpc_client.dart';

const int kPort = 50052;
const int kServerStartupWaitSec = 8;

Future<void> main() async {
  print('=' * 70);
  print('TEST: Real LiteRtLmClient from lib/desktop/grpc_client.dart');
  print('=' * 70);
  print('');

  // Paths
  final homeDir = Platform.environment['HOME'] ?? '/Users/sashadenisov';
  final modelPath = '$homeDir/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';
  final jarPath = '/Users/sashadenisov/Work/1/flutter_gemma/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar';
  final nativesPath = '/Users/sashadenisov/Work/1/flutter_gemma/example/build/macos/Build/Products/Debug/flutter_gemma_example.app/Contents/Frameworks/litertlm';

  // Verify files
  if (!await File(modelPath).exists()) {
    print('❌ Model not found: $modelPath');
    exit(1);
  }
  if (!await File(jarPath).exists()) {
    print('❌ JAR not found. Build with: cd litertlm-server && ./gradlew fatJar');
    exit(1);
  }
  print('✓ Files found\n');

  // Kill existing servers
  await Process.run('pkill', ['-9', '-f', 'litertlm-server']);
  await Future.delayed(const Duration(seconds: 1));

  // Start server
  print('Starting server on port $kPort...');
  final server = await Process.start(
    'java',
    ['-Djava.library.path=$nativesPath', '-jar', jarPath, '$kPort'],
  );

  server.stdout.transform(const SystemEncoding().decoder).listen((d) {
    for (final l in d.split('\n').where((x) => x.trim().isNotEmpty)) {
      print('[SRV] $l');
    }
  });
  server.stderr.transform(const SystemEncoding().decoder).listen((d) {
    for (final l in d.split('\n').where((x) => x.trim().isNotEmpty)) {
      print('[SRV ERR] $l');
    }
  });

  print('Waiting ${kServerStartupWaitSec}s...\n');
  await Future.delayed(Duration(seconds: kServerStartupWaitSec));

  // Use REAL LiteRtLmClient
  final client = LiteRtLmClient();
  final results = <String, bool>{};

  try {
    // TEST 1: Connect
    print('TEST 1: Connect');
    await client.connect(port: kPort);
    results['1. Connect'] = true;
    print('✓ PASS: isInitialized=${client.isInitialized}\n');

    // TEST 2: Initialize (using same params as flutter_gemma_desktop.dart AFTER fix)
    // The fix sets enableVision=false regardless of supportImage
    print('TEST 2: Initialize (enableVision=false per bug #684 fix)');
    await client.initialize(
      modelPath: modelPath,
      backend: 'gpu',
      maxTokens: 512,
      enableVision: false,  // This is what the FIX does
      enableAudio: true,
      maxNumImages: 1,
    );
    results['2. Initialize'] = true;
    print('✓ PASS: isInitialized=${client.isInitialized}\n');

    // TEST 3: Create conversation
    print('TEST 3: CreateConversation');
    final convId = await client.createConversation(temperature: 0.8, topK: 40);
    results['3. CreateConversation'] = true;
    print('✓ PASS: conversationId=$convId\n');

    // TEST 4: Chat (text-only)
    print('TEST 4: Chat "Hi"');
    final buffer = StringBuffer();
    await for (final chunk in client.chat('Hi')) {
      buffer.write(chunk);
      stdout.write(chunk);
    }
    print('\n');
    if (buffer.isEmpty) throw Exception('Empty response');
    results['4. Chat'] = true;
    print('✓ PASS: ${buffer.length} chars\n');

    // TEST 5: Follow-up
    print('TEST 5: Follow-up "What is 2+2?"');
    final buffer2 = StringBuffer();
    await for (final chunk in client.chat('What is 2+2?')) {
      buffer2.write(chunk);
      stdout.write(chunk);
    }
    print('\n');
    if (buffer2.isEmpty) throw Exception('Empty response');
    results['5. Follow-up'] = true;
    print('✓ PASS: ${buffer2.length} chars\n');

    // Cleanup
    print('TEST 6: Cleanup');
    await client.closeConversation();
    await client.shutdown();
    await client.disconnect();
    results['6. Cleanup'] = true;
    print('✓ PASS\n');

  } catch (e, st) {
    print('\n❌ ERROR: $e');
    print(st);
  } finally {
    server.kill();
  }

  // Summary
  print('=' * 70);
  print('SUMMARY');
  print('=' * 70);
  for (final e in results.entries) {
    print('  ${e.value ? "✓" : "❌"} ${e.key}');
  }
  final passed = results.values.where((v) => v).length;
  print('\nResult: $passed/${results.length} passed');

  exit(results.values.every((v) => v) ? 0 : 1);
}
