/// Universal FFI integration test for all platforms (macOS, iOS, Android).
///
/// Prerequisites:
///   macOS:   models in ~/Library/Containers/.../Documents/
///   Android: adb push models to /data/local/tmp/flutter_gemma_test/
///   iOS:     models downloaded via FlutterGemma.installModel()
///
/// Run:
///   flutter test integration_test/litertlm_ffi_test.dart -d <device>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';

// ── Model URLs (for iOS download, macOS/Android use local files) ──
const _gemma3_1bUrl = 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';
const _qwenUrl = 'https://huggingface.co/nickmeinhold/Qwen3-0.6B-IT-litertlm/resolve/main/Qwen3-0.6B_multi-prefill-seq_q8_ekv4096.litertlm';
const _gemma3nUrl = 'https://huggingface.co/litert-community/Gemma3n-E2B-IT/resolve/main/gemma-3n-E2B-it-int4.litertlm';
const _gemma4Url = 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

const _token = String.fromEnvironment('HUGGINGFACE_TOKEN');

// ── Local paths ──
String get _androidDir => '/data/local/tmp/flutter_gemma_test';
String get _macosDir =>
    '${Platform.environment['HOME']}/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents';
String get _linuxDir => '${Platform.environment['HOME']}/models';
String get _windowsDir => '${Platform.environment['USERPROFILE']}\\models';

Uint8List _testImage = Uint8List(0);
Uint8List _testAudio = Uint8List(0);

/// Install model: from file on macOS/Android, from network on iOS.
Future<void> _install({
  required String? localPath,
  required String networkUrl,
}) async {
  if (localPath != null && File(localPath).existsSync()) {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(localPath).install();
  } else {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(networkUrl, token: _token).install();
  }
}

/// Get local path for a model filename (null on iOS — download instead).
///
/// iOS Simulator can read the host macOS filesystem; pass the host Documents
/// dir via `--dart-define=IOS_TEST_DOCS_DIR=...` to reuse host-cached models
/// instead of re-downloading on every test run.
String? _localPath(String filename) {
  if (Platform.isAndroid) return '$_androidDir/$filename';
  if (Platform.isMacOS) return '$_macosDir/$filename';
  if (Platform.isLinux) return '$_linuxDir/$filename';
  if (Platform.isWindows) return '$_windowsDir\\$filename';
  if (Platform.isIOS) {
    const iosDocs = String.fromEnvironment('IOS_TEST_DOCS_DIR');
    if (iosDocs.isNotEmpty) {
      final p = '$iosDocs/$filename';
      if (File(p).existsSync()) return p;
    }
    return null; // device path or network download
  }
  return null;
}

/// Group-scoped model instance. We create it once per test group (with full
/// vision+audio capabilities + the selected backend) and reuse it across all
/// tests in that group — destroying & recreating the engine between every
/// test would re-initialize the GPU adapter, which on Linux/Vulkan trips an
/// upstream LiteRT-LM bug `ALREADY_EXISTS: wgpu::Instance already set` and
/// also adds 2-3 s engine_create overhead per test.
///
/// This mirrors how a real Flutter app uses the plugin: create one
/// `InferenceModel` per chat surface, open many sessions on it.
InferenceModel? _sharedModel;
PreferredBackend? _sharedBackend;

Future<InferenceModel> _ensureModel(PreferredBackend backend, int maxTokens) async {
  if (_sharedModel != null && _sharedBackend == backend) return _sharedModel!;
  if (_sharedModel != null && _sharedBackend != backend) {
    await _sharedModel!.close();
    _sharedModel = null;
  }
  _sharedBackend = backend;
  _sharedModel = await FlutterGemma.getActiveModel(
    maxTokens: maxTokens,
    preferredBackend: backend,
    supportImage: true,
    maxNumImages: 1,
    supportAudio: true,
  );
  return _sharedModel!;
}

Future<void> _closeSharedModel() async {
  if (_sharedModel != null) {
    await _sharedModel!.close();
    _sharedModel = null;
    _sharedBackend = null;
  }
}

/// Helper: open a session on the shared model, send a single prompt, return
/// the streamed response.
Future<String> _chat(
  PreferredBackend backend,
  int maxTokens,
  String prompt, {
  bool supportImage = false,
  bool supportAudio = false,
  bool enableThinking = false,
  Uint8List? image,
  Uint8List? audio,
}) async {
  final model = await _ensureModel(backend, maxTokens);
  final session = await model.createSession(
    temperature: 0.8,
    topK: 1,
    enableVisionModality: supportImage,
    enableAudioModality: supportAudio,
    enableThinking: enableThinking,
  );
  await session.addQueryChunk(Message(
    text: prompt,
    isUser: true,
    imageBytes: image,
    audioBytes: audio,
  ));

  // Collect streaming response
  final chunks = <String>[];
  await for (final chunk in session.getResponseAsync()) {
    chunks.add(chunk);
  }
  final response = chunks.join();

  await session.close();
  // Don't close the model — it's shared across tests in this group and
  // closed once in tearDownAll via _closeSharedModel().
  return response;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();

    // Load test assets — try filesystem first (host paths on macOS/Linux/Windows
    // and Android adb-pushed paths), then fall back to bundled Flutter assets
    // (works on iOS device + simulator + any platform where assets/test/ ships).
    for (final path in [
      '$_androidDir/test_image.jpg',
      '$_macosDir/test_image.png',
      if (Platform.isLinux) '$_linuxDir/test_image.png',
      if (Platform.isLinux) '$_linuxDir/test_image.jpg',
      if (Platform.isWindows) '$_windowsDir\\test_image.png',
      if (Platform.isWindows) '$_windowsDir\\test_image.jpg',
      '${Platform.environment['HOME']}/Downloads/test_image.jpg',
    ]) {
      if (File(path).existsSync()) {
        _testImage = File(path).readAsBytesSync();
        break;
      }
    }
    if (_testImage.isEmpty) {
      try {
        final data = await rootBundle.load('assets/test/test_image.jpg');
        _testImage = data.buffer.asUint8List();
      } catch (_) {/* asset not bundled — leave empty */}
    }
    for (final path in [
      '$_androidDir/test_audio.wav',
      '$_macosDir/test_audio.wav',
      if (Platform.isLinux) '$_linuxDir/test_audio.wav',
      if (Platform.isWindows) '$_windowsDir\\test_audio.wav',
    ]) {
      if (File(path).existsSync()) {
        _testAudio = File(path).readAsBytesSync();
        break;
      }
    }
    if (_testAudio.isEmpty) {
      try {
        final data = await rootBundle.load('assets/test/test_audio.wav');
        _testAudio = data.buffer.asUint8List();
      } catch (_) {/* asset not bundled — leave empty */}
    }
    print('Platform: ${Platform.operatingSystem}');
    print('Assets: image=${_testImage.length}B, audio=${_testAudio.length}B');
  });

  // ══════════════════════════════════════════════════════════════════
  // Gemma 4 E2B — multimodal + thinking
  // ══════════════════════════════════════════════════════════════════
  group('Gemma4-E2B', () {
    setUpAll(() async {
      await _install(
        localPath: _localPath('gemma-4-E2B-it.litertlm'),
        networkUrl: _gemma4Url,
      );
    });

    tearDownAll(_closeSharedModel);

    testWidgets('CPU text', (t) async {
      final r = await _chat(PreferredBackend.cpu, 4096, 'Say hi');
      print('[Gemma4 CPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU text', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'What is 2+2?');
      print('[Gemma4 GPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU streaming', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'Say hello');
      print('[Gemma4 stream] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU vision', (t) async {
      if (_testImage.isEmpty) { print('[Gemma4 vision] SKIP: no image'); return; }
      final r = await _chat(PreferredBackend.gpu, 4096, 'Describe this image briefly',
          supportImage: true, image: _testImage);
      print('[Gemma4 vision] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU audio', (t) async {
      if (_testAudio.isEmpty) { print('[Gemma4 audio] SKIP: no audio'); return; }
      final r = await _chat(PreferredBackend.gpu, 4096, 'What did you hear?',
          supportAudio: true, audio: _testAudio);
      print('[Gemma4 audio] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU thinking', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'Why is the sky blue?',
          enableThinking: true);
      final hasThinking = r.contains('<|channel>thought');
      print('[Gemma4 thinking] ${r.length} chars, thinking=$hasThinking');
      expect(r, isNotEmpty);
    });

    // ══════════════════════════════════════════════════════════════════
    // InferenceChat surface — covers methods that session-level tests miss
    // ══════════════════════════════════════════════════════════════════

    testWidgets('chat generateChatResponse (sync)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);
      await chat.addQueryChunk(Message(text: 'Say hi', isUser: true));
      final r = await chat.generateChatResponse();
      print('[Gemma4 chat sync] ${r.runtimeType}: $r');
      expect(r.toString(), isNotEmpty);
      await chat.close();
    });

    testWidgets('chat generateChatResponseAsync (stream)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);
      await chat.addQueryChunk(Message(text: 'Say hi', isUser: true));
      final chunks = <String>[];
      await for (final r in chat.generateChatResponseAsync()) {
        chunks.add(r.toString());
      }
      print('[Gemma4 chat stream] ${chunks.length} chunks: ${chunks.join()}');
      expect(chunks, isNotEmpty);
      await chat.close();
    });

    testWidgets('chat multi-turn (history retained)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);

      await chat.addQueryChunk(
          Message(text: 'My favourite colour is purple.', isUser: true));
      final r1 = await chat.generateChatResponse();
      print('[Gemma4 chat turn 1] $r1');
      expect(r1.toString(), isNotEmpty);

      await chat.addQueryChunk(
          Message(text: 'What is my favourite colour?', isUser: true));
      final r2 = await chat.generateChatResponse();
      print('[Gemma4 chat turn 2] $r2');
      expect(r2.toString(), isNotEmpty);
      // Sanity: model should mention the colour from turn 1.
      expect(r2.toString().toLowerCase(), contains('purple'));

      await chat.close();
    });

    testWidgets('chat clearHistory resets conversation', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);

      await chat.addQueryChunk(
          Message(text: 'Remember the secret word: BANANA.', isUser: true));
      await chat.generateChatResponse();

      await chat.clearHistory();
      print('[Gemma4 chat clearHistory] OK');

      await chat.addQueryChunk(
          Message(text: 'What was the secret word?', isUser: true));
      final r = await chat.generateChatResponse();
      print('[Gemma4 chat after clear] $r');
      // After clearHistory the model should not remember "BANANA".
      expect(r.toString().toLowerCase(), isNot(contains('banana')));

      await chat.close();
    });

    testWidgets('chat stopGeneration interrupts stream', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final chat = await model.createChat(temperature: 0.8, topK: 1);
      await chat.addQueryChunk(Message(
          text: 'Write a 1000-word essay about Berlin.', isUser: true));

      final received = <String>[];
      var stopped = false;
      final sub = chat.generateChatResponseAsync().listen((r) async {
        received.add(r.toString());
        if (received.length == 5 && !stopped) {
          stopped = true;
          await chat.stopGeneration();
        }
      });
      await sub.asFuture<void>().timeout(const Duration(seconds: 30),
          onTimeout: () => sub.cancel());

      print('[Gemma4 chat stop] got ${received.length} chunks before stop');
      expect(received, isNotEmpty);
      // We asked for 1000 words but stopped after 5 chunks; total length should
      // be small relative to a full essay (sanity: nothing crazy).
      expect(received.length, lessThan(500));

      await chat.close();
    });

    testWidgets('session sizeInTokens', (t) async {
      // sizeInTokens is tokenizer-only, doesn't touch the backend — keep using
      // the shared GPU model to avoid destroying the engine (which on
      // Linux/Vulkan triggers the upstream wgpu::Instance singleton issue).
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final session = await model.createSession(temperature: 0.8, topK: 1);
      final n = await session.sizeInTokens('Hello, how many tokens am I?');
      print('[Gemma4 sizeInTokens] $n');
      expect(n, greaterThan(0));
      await session.close();
    });

    testWidgets('session stopGeneration (low-level)', (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(Message(
          text: 'Write a 1000-word essay about the Berlin Wall.',
          isUser: true));

      final received = <String>[];
      var stopped = false;
      final sub = session.getResponseAsync().listen((chunk) async {
        received.add(chunk);
        if (received.length == 5 && !stopped) {
          stopped = true;
          await session.stopGeneration();
        }
      });
      await sub.asFuture<void>().timeout(const Duration(seconds: 30),
          onTimeout: () => sub.cancel());

      print('[Gemma4 session stop] got ${received.length} chunks');
      expect(received, isNotEmpty);
      expect(received.length, lessThan(500));

      await session.close();
    });

    testWidgets('stream cancel via subscription.cancel (no stopGeneration)',
        (t) async {
      final model = await _ensureModel(PreferredBackend.gpu, 4096);
      final session = await model.createSession(temperature: 0.8, topK: 1);
      await session.addQueryChunk(Message(
          text: 'Write a 1000-word essay about Paris.', isUser: true));

      final received = <String>[];
      final completer = Completer<void>();
      final sub = session.getResponseAsync().listen(
        (chunk) {
          received.add(chunk);
          if (received.length == 3 && !completer.isCompleted) {
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(const Duration(seconds: 30));
      await sub.cancel();

      print('[Gemma4 stream cancel] got ${received.length} chunks');
      expect(received, isNotEmpty);

      // Closing the session cleanly after stream cancel must not crash.
      await session.close();
    });

    testWidgets('multiple createSession on same model', (t) async {
      // FfiInferenceModel is single-session at a time — this test verifies
      // we can sequentially create + close sessions without leaking the engine.
      final model = await _ensureModel(PreferredBackend.gpu, 4096);

      for (var i = 0; i < 3; i++) {
        final session = await model.createSession(temperature: 0.8, topK: 1);
        await session
            .addQueryChunk(Message(text: 'Iteration $i: hi', isUser: true));
        final chunks = <String>[];
        await for (final c in session.getResponseAsync()) {
          chunks.add(c);
        }
        print('[Gemma4 multi-session $i] ${chunks.join().substring(0, 20)}...');
        expect(chunks, isNotEmpty);
        await session.close();
      }
    });
  });
}
