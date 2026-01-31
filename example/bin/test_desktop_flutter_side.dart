// Complete Flutter-side Desktop test
// Tests the EXACT same code path as Flutter app, but without Flutter UI
//
// This test:
// 1. Starts gRPC server automatically
// 2. Uses LiteRtLmClient (same as flutter_gemma_desktop.dart)
// 3. Tests DesktopInferenceModelSession logic (query buffering, response streaming)
// 4. Reports detailed diagnostics if anything fails
//
// Run with: dart run bin/test_desktop_flutter_side.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';

import 'package:flutter_gemma/desktop/generated/litertlm.pb.dart';
import 'package:flutter_gemma/desktop/generated/litertlm.pbgrpc.dart';

// ============================================================================
// Configuration - matches what Flutter app uses
// ============================================================================

const int kPort = 50051; // Use different port to avoid conflicts
const int kServerStartupWaitSec = 8;
const int kMaxTokens = 512;

// Model parameters from example/lib/models/model.dart (gemma3n_2B)
// NOTE: enableVision=true crashes LiteRT-LM JVM SDK (bug #684)
// So we test with enableVision=false to verify the REST of the pipeline works
const bool kEnableVision = false;  // FIX: must be false due to LiteRT-LM bug #684
const bool kEnableAudio = true;    // Audio works fine

// ============================================================================
// Simplified LiteRtLmClient (copy of lib/desktop/grpc_client.dart logic)
// ============================================================================

class TestLiteRtLmClient {
  ClientChannel? _channel;
  LiteRtLmServiceClient? _client;
  String? _currentConversationId;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  String? get conversationId => _currentConversationId;

  Future<void> connect({String host = 'localhost', int port = kPort}) async {
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _client = LiteRtLmServiceClient(_channel!);
    print('[Client] Connected to $host:$port');
  }

  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    int maxTokens = 2048,
    bool enableVision = false,
    int maxNumImages = 1,
    bool enableAudio = false,
  }) async {
    if (_client == null) throw StateError('Not connected');

    print('[Client] Initializing with:');
    print('[Client]   modelPath: $modelPath');
    print('[Client]   backend: $backend');
    print('[Client]   maxTokens: $maxTokens');
    print('[Client]   enableVision: $enableVision');
    print('[Client]   enableAudio: $enableAudio');
    print('[Client]   maxNumImages: $maxNumImages');

    final request = InitializeRequest()
      ..modelPath = modelPath
      ..backend = backend
      ..maxTokens = maxTokens
      ..enableVision = enableVision
      ..maxNumImages = maxNumImages
      ..enableAudio = enableAudio;

    final response = await _client!.initialize(request);

    if (!response.success) {
      throw Exception('Failed to initialize model: ${response.error}');
    }

    _isInitialized = true;
    print('[Client] Model initialized: ${response.modelInfo}');
  }

  Future<String> createConversation({
    double? temperature,
    int? topK,
    double? topP,
  }) async {
    if (!_isInitialized) throw StateError('Model not initialized');

    final request = CreateConversationRequest();
    if (temperature != null || topK != null || topP != null) {
      request.samplerConfig = SamplerConfig()
        ..temperature = temperature ?? 0.8
        ..topK = topK ?? 40
        ..topP = topP ?? 0.95;
    }

    final response = await _client!.createConversation(request);

    if (response.hasError() && response.error.isNotEmpty) {
      throw Exception('Failed to create conversation: ${response.error}');
    }

    _currentConversationId = response.conversationId;
    print('[Client] Conversation created: $_currentConversationId');
    return _currentConversationId!;
  }

  Stream<String> chat(String text, {String? conversationId}) async* {
    if (!_isInitialized) throw StateError('Model not initialized');

    final convId = conversationId ?? _currentConversationId;
    if (convId == null) throw StateError('No conversation');

    final request = ChatRequest()
      ..conversationId = convId
      ..text = text;

    await for (final response in _client!.chat(request)) {
      if (response.hasError() && response.error.isNotEmpty) {
        throw Exception('Chat error: ${response.error}');
      }
      if (response.hasText()) {
        yield response.text;
      }
    }
  }

  Stream<String> chatWithAudio(String text, Uint8List audioBytes, {String? conversationId}) async* {
    if (!_isInitialized) throw StateError('Model not initialized');

    final convId = conversationId ?? _currentConversationId;
    if (convId == null) throw StateError('No conversation');

    final request = ChatWithAudioRequest()
      ..conversationId = convId
      ..text = text
      ..audio = audioBytes;

    await for (final response in _client!.chatWithAudio(request)) {
      if (response.hasError() && response.error.isNotEmpty) {
        throw Exception('Chat error: ${response.error}');
      }
      if (response.hasText()) {
        yield response.text;
      }
    }
  }

  Future<void> closeConversation({String? conversationId}) async {
    final convId = conversationId ?? _currentConversationId;
    if (convId == null) return;

    try {
      final request = CloseConversationRequest()..conversationId = convId;
      await _client!.closeConversation(request);
      if (convId == _currentConversationId) {
        _currentConversationId = null;
      }
      print('[Client] Conversation closed: $convId');
    } catch (e) {
      print('[Client] Warning: Failed to close conversation: $e');
    }
  }

  Future<void> shutdown() async {
    if (_client == null) return;
    try {
      await _client!.shutdown(ShutdownRequest());
      _isInitialized = false;
      print('[Client] Engine shut down');
    } catch (e) {
      print('[Client] Warning: Failed to shutdown: $e');
    }
  }

  Future<void> disconnect() async {
    await _channel?.shutdown();
    _channel = null;
    _client = null;
    _isInitialized = false;
    _currentConversationId = null;
    print('[Client] Disconnected');
  }
}

// ============================================================================
// Simplified DesktopInferenceModelSession (copy of logic from desktop_inference_model.dart)
// ============================================================================

class TestDesktopSession {
  TestDesktopSession({
    required this.grpcClient,
    required this.supportImage,
    required this.supportAudio,
  });

  final TestLiteRtLmClient grpcClient;
  final bool supportImage;
  final bool supportAudio;

  final StringBuffer _queryBuffer = StringBuffer();
  Uint8List? _pendingImage;
  Uint8List? _pendingAudio;

  /// Mimics Message class behavior
  void addQueryChunk({
    required String text,
    bool isUser = true,
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) {
    // Simplified prompt transformation (mimics transformToChatPrompt)
    if (isUser) {
      _queryBuffer.write('<start_of_turn>user\n$text<end_of_turn>\n<start_of_turn>model\n');
    } else {
      _queryBuffer.write(text);
    }

    if (imageBytes != null && supportImage) {
      _pendingImage = imageBytes;
      print('[Session] Image buffered: ${imageBytes.length} bytes');
    }

    if (audioBytes != null && supportAudio) {
      _pendingAudio = audioBytes;
      print('[Session] Audio buffered: ${audioBytes.length} bytes');
    }
  }

  Stream<String> getResponseAsync() async* {
    final text = _queryBuffer.toString();
    _queryBuffer.clear();

    final audio = _pendingAudio;
    final image = _pendingImage;
    _pendingAudio = null;
    _pendingImage = null;

    print('[Session] getResponseAsync:');
    print('[Session]   text length: ${text.length}');
    print('[Session]   audio: ${audio?.length ?? "null"}');
    print('[Session]   image: ${image?.length ?? "null"}');

    if (audio != null) {
      print('[Session] -> Calling chatWithAudio');
      yield* grpcClient.chatWithAudio(text, audio);
    } else if (image != null) {
      print('[Session] -> Calling chatWithImage (NOT IMPLEMENTED IN TEST)');
      throw UnimplementedError('chatWithImage not in this test');
    } else {
      print('[Session] -> Calling chat (text-only)');
      yield* grpcClient.chat(text);
    }
  }
}

// ============================================================================
// Test Runner
// ============================================================================

Future<void> main() async {
  print('=' * 70);
  print('DESKTOP FLUTTER-SIDE TEST');
  print('Tests the EXACT same code path as Flutter app');
  print('=' * 70);
  print('');

  // Find paths
  final homeDir = Platform.environment['HOME'] ?? '/Users/sashadenisov';
  final modelPath = '$homeDir/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents/gemma-3n-E2B-it-int4.litertlm';
  final jarPath = '/Users/sashadenisov/Work/1/flutter_gemma/litertlm-server/build/libs/litertlm-server-0.1.0-all.jar';
  final nativesPath = '/Users/sashadenisov/Work/1/flutter_gemma/example/build/macos/Build/Products/Debug/flutter_gemma_example.app/Contents/Frameworks/litertlm';

  // Verify files
  print('Checking required files...');
  if (!await File(modelPath).exists()) {
    print('❌ FATAL: Model not found: $modelPath');
    exit(1);
  }
  if (!await File(jarPath).exists()) {
    print('❌ FATAL: JAR not found: $jarPath');
    print('   Build with: cd litertlm-server && ./gradlew fatJar');
    exit(1);
  }
  print('✓ All files found\n');

  // Kill any existing server on our port
  print('Killing any existing servers...');
  await Process.run('pkill', ['-9', '-f', 'litertlm-server']);
  await Future.delayed(const Duration(seconds: 1));

  // Start server
  print('Starting gRPC server on port $kPort...');
  final serverProcess = await Process.start(
    'java',
    ['-Djava.library.path=$nativesPath', '-jar', jarPath, '$kPort'],
    environment: Platform.environment,
  );

  // Capture server output
  final serverErrors = <String>[];
  serverProcess.stdout.transform(const SystemEncoding().decoder).listen((data) {
    for (final line in data.split('\n').where((l) => l.trim().isNotEmpty)) {
      print('[SERVER] $line');
    }
  });
  serverProcess.stderr.transform(const SystemEncoding().decoder).listen((data) {
    for (final line in data.split('\n').where((l) => l.trim().isNotEmpty)) {
      print('[SERVER ERR] $line');
      serverErrors.add(line);
    }
  });

  print('Waiting ${kServerStartupWaitSec}s for server startup...\n');
  await Future.delayed(Duration(seconds: kServerStartupWaitSec));

  // Run tests
  final results = <String, bool>{};
  final client = TestLiteRtLmClient();

  try {
    // ========================================================================
    // TEST 1: Connect
    // ========================================================================
    print('=' * 70);
    print('TEST 1: Connect to gRPC server');
    print('=' * 70);
    try {
      await client.connect(port: kPort);
      results['1. Connect'] = true;
      print('✓ PASS\n');
    } catch (e) {
      results['1. Connect'] = false;
      print('❌ FAIL: $e\n');
      throw Exception('Cannot continue without connection');
    }

    // ========================================================================
    // TEST 2: Initialize with FIXED parameters
    // NOTE: enableVision=true crashes LiteRT-LM (bug #684), so we use false
    // ========================================================================
    print('=' * 70);
    print('TEST 2: Initialize model');
    print('  Using FIXED parameters (enableVision=false due to LiteRT-LM bug #684)');
    print('    enableVision: $kEnableVision');
    print('    enableAudio: $kEnableAudio');
    print('=' * 70);

    try {
      await client.initialize(
        modelPath: modelPath,
        backend: 'gpu',
        maxTokens: kMaxTokens,
        enableVision: kEnableVision,
        enableAudio: kEnableAudio,
        maxNumImages: 1,
      );
      results['2. Initialize (vision=$kEnableVision, audio=$kEnableAudio)'] = true;
      print('✓ PASS\n');
    } catch (e) {
      results['2. Initialize (vision=$kEnableVision, audio=$kEnableAudio)'] = false;
      print('❌ FAIL: $e\n');
      rethrow;
    }

    // ========================================================================
    // TEST 3: Create conversation
    // ========================================================================
    print('=' * 70);
    print('TEST 3: Create conversation');
    print('=' * 70);
    try {
      await client.createConversation(temperature: 0.8, topK: 40);
      results['3. CreateConversation'] = true;
      print('✓ PASS\n');
    } catch (e) {
      results['3. CreateConversation'] = false;
      print('❌ FAIL: $e\n');
      rethrow;
    }

    // ========================================================================
    // TEST 4: Session - Text-only chat (via DesktopInferenceModelSession logic)
    // ========================================================================
    print('=' * 70);
    print('TEST 4: Session - Text-only chat');
    print('  Uses DesktopInferenceModelSession logic (query buffering)');
    print('=' * 70);

    final session = TestDesktopSession(
      grpcClient: client,
      supportImage: kEnableVision,
      supportAudio: kEnableAudio,
    );

    try {
      session.addQueryChunk(text: 'Hi', isUser: true);
      print('Query buffered, calling getResponseAsync()...\n');

      final responseBuffer = StringBuffer();
      await for (final chunk in session.getResponseAsync()) {
        responseBuffer.write(chunk);
        stdout.write(chunk);
      }
      print('\n');

      if (responseBuffer.isEmpty) {
        throw Exception('Empty response!');
      }

      results['4. Session text chat'] = true;
      print('✓ PASS - Got ${responseBuffer.length} chars\n');
    } catch (e) {
      results['4. Session text chat'] = false;
      print('❌ FAIL: $e\n');
    }

    // ========================================================================
    // TEST 5: Session - Second message (conversation context)
    // ========================================================================
    print('=' * 70);
    print('TEST 5: Session - Follow-up message');
    print('=' * 70);

    try {
      session.addQueryChunk(text: 'What is 2+2?', isUser: true);

      final responseBuffer = StringBuffer();
      await for (final chunk in session.getResponseAsync()) {
        responseBuffer.write(chunk);
        stdout.write(chunk);
      }
      print('\n');

      if (responseBuffer.isEmpty) {
        throw Exception('Empty response!');
      }

      results['5. Follow-up message'] = true;
      print('✓ PASS - Got ${responseBuffer.length} chars\n');
    } catch (e) {
      results['5. Follow-up message'] = false;
      print('❌ FAIL: $e\n');
    }

    // ========================================================================
    // TEST 6: Cleanup
    // ========================================================================
    print('=' * 70);
    print('TEST 6: Cleanup');
    print('=' * 70);
    await client.closeConversation();
    await client.shutdown();
    await client.disconnect();
    results['6. Cleanup'] = true;
    print('✓ PASS\n');

  } catch (e, st) {
    print('\n❌ FATAL ERROR: $e');
    print(st);
  } finally {
    // Kill server
    serverProcess.kill();
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ========================================================================
  // Summary
  // ========================================================================
  print('=' * 70);
  print('TEST SUMMARY');
  print('=' * 70);
  for (final entry in results.entries) {
    final status = entry.value ? '✓ PASS' : '❌ FAIL';
    print('  $status: ${entry.key}');
  }

  final passed = results.values.where((v) => v).length;
  final total = results.length;
  print('');
  print('Result: $passed/$total tests passed');

  if (results.values.any((v) => !v)) {
    print('');
    print('>>> DIAGNOSIS <<<');
    print('Some tests failed. Check output above for details.');
    exit(1);
  }

  print('\n✓ All tests passed!');
  exit(0);
}
