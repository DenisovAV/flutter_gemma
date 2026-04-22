/// Universal FFI integration test for all platforms (macOS, iOS, Android).
///
/// Prerequisites:
///   macOS:   models in ~/Library/Containers/.../Documents/
///   Android: adb push models to /data/local/tmp/flutter_gemma_test/
///   iOS:     models downloaded via FlutterGemma.installModel()
///
/// Run:
///   flutter test integration_test/litertlm_ffi_test.dart -d <device>
import 'dart:io';
import 'dart:typed_data';
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
String? _localPath(String filename) {
  if (Platform.isAndroid) return '$_androidDir/$filename';
  if (Platform.isMacOS) return '$_macosDir/$filename';
  if (Platform.isLinux) return '$_linuxDir/$filename';
  return null; // iOS: use network download
}

/// Helper: create model, session, chat, close.
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
  final model = await FlutterGemma.getActiveModel(
    maxTokens: maxTokens,
    preferredBackend: backend,
    supportImage: supportImage,
    maxNumImages: supportImage ? 1 : null,
    supportAudio: supportAudio,
  );
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
  await model.close();
  return response;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FlutterGemma.initialize();

    // Load test assets
    for (final path in [
      '$_androidDir/test_image.jpg',
      '$_macosDir/test_image.png',
      '${Platform.environment['HOME']}/Downloads/test_image.jpg',
    ]) {
      if (File(path).existsSync()) {
        _testImage = File(path).readAsBytesSync();
        break;
      }
    }
    for (final path in [
      '$_androidDir/test_audio.wav',
      '$_macosDir/test_audio.wav',
    ]) {
      if (File(path).existsSync()) {
        _testAudio = File(path).readAsBytesSync();
        break;
      }
    }
    print('Platform: ${Platform.operatingSystem}');
    print('Assets: image=${_testImage.length}B, audio=${_testAudio.length}B');
  });

  // ══════════════════════════════════════════════════════════════════
  // Gemma 3 1B — text only, small model
  // ══════════════════════════════════════════════════════════════════
  group('Gemma3-1B', () {
    setUpAll(() async {
      await _install(
        localPath: _localPath('Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm'),
        networkUrl: _gemma3_1bUrl,
      );
    });

    testWidgets('CPU text', (t) async {
      final r = await _chat(PreferredBackend.cpu, 4096, 'Say hi');
      print('[Gemma3-1B CPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU text', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'What is 2+2?');
      print('[Gemma3-1B GPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU streaming', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'Say hello');
      print('[Gemma3-1B stream] $r');
      expect(r, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Qwen3 0.6B — text only (if available)
  // ══════════════════════════════════════════════════════════════════
  group('Qwen3-0.6B', () {
    setUpAll(() async {
      final path = _localPath('Qwen3-0.6B.litertlm');
      if (path != null && !File(path).existsSync()) {
        print('[Qwen] Model not found at $path, skipping');
        return;
      }
      await _install(localPath: path, networkUrl: _qwenUrl);
    });

    testWidgets('CPU text', (t) async {
      final r = await _chat(PreferredBackend.cpu, 4096, 'Say hi');
      print('[Qwen CPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU text', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'What is 2+2?');
      print('[Qwen GPU] $r');
      expect(r, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Gemma 3n E2B — multimodal (vision + audio)
  // ══════════════════════════════════════════════════════════════════
  group('Gemma3n-E2B', () {
    setUpAll(() async {
      await _install(
        localPath: _localPath('gemma-3n-E2B-it-int4.litertlm'),
        networkUrl: _gemma3nUrl,
      );
    });

    testWidgets('CPU text', (t) async {
      final r = await _chat(PreferredBackend.cpu, 4096, 'Say hi');
      print('[Gemma3n CPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU text', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'What is 2+2?');
      print('[Gemma3n GPU] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU streaming', (t) async {
      final r = await _chat(PreferredBackend.gpu, 4096, 'Say hello');
      print('[Gemma3n stream] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('GPU vision', (t) async {
      if (_testImage.isEmpty) { print('[Gemma3n vision] SKIP: no image'); return; }
      final r = await _chat(PreferredBackend.gpu, 4096, 'Describe this image',
          supportImage: true, image: _testImage);
      print('[Gemma3n vision] $r');
      expect(r, isNotEmpty);
    });

    testWidgets('CPU audio', (t) async {
      if (_testAudio.isEmpty) { print('[Gemma3n audio] SKIP: no audio'); return; }
      final r = await _chat(PreferredBackend.cpu, 4096, 'What did you hear?',
          supportAudio: true, audio: _testAudio);
      print('[Gemma3n audio] $r');
      expect(r, isNotEmpty);
    });
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
  });
}
