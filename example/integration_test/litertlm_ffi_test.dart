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
String? _localPath(String filename) {
  if (Platform.isAndroid) return '$_androidDir/$filename';
  if (Platform.isMacOS) return '$_macosDir/$filename';
  if (Platform.isLinux) return '$_linuxDir/$filename';
  if (Platform.isWindows) return '$_windowsDir\\$filename';
  if (Platform.isIOS) {
    // iOS Simulator can read the host macOS filesystem directly even though
    // HOME is unset for sandboxed app. Use the absolute macOS Documents path
    // and probe; works on Sim, returns null on real device.
    const userMacDocs = '/Users/sashadenisov/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/Documents';
    final p = '$userMacDocs/$filename';
    if (File(p).existsSync()) return p;
    return null; // device path or network download
  }
  return null;
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
