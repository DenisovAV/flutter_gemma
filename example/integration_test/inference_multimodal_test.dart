// Integration test: multimodal inference (vision + audio) with Gemma 3 Nano E2B.
// Run: flutter test integration_test/inference_multimodal_test.dart -d <device>
//
// Requires HuggingFace token (gated model).
// Vision: all platforms (Android, iOS, Web, Desktop)
// Audio: LiteRT-LM only (Android .litertlm, Desktop)

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'inference_test_helpers.dart';

/// HuggingFace token for gated Gemma 3n model.
/// Set via: HF_TOKEN=hf_... flutter test integration_test/inference_multimodal_test.dart
final _hfToken = Platform.environment['HF_TOKEN'] ??
    (throw StateError('HF_TOKEN env variable is required for gated model tests'));

/// Gemma 3 Nano E2B model URLs per platform.
const _gemma3nTaskUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task';
const _gemma3nWebUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4-Web.litertlm';
const _gemma3nLitertlmUrl =
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm';

/// Multimodal model config — platform-aware URL selection.
class _MultimodalConfig {
  final String url;
  final String filename;
  final String label;
  final bool supportsVision;
  final bool supportsAudio;

  const _MultimodalConfig({
    required this.url,
    required this.filename,
    required this.label,
    this.supportsVision = true,
    required this.supportsAudio,
  });

  /// All multimodal configs for current platform.
  /// Android: MediaPipe (.task) + LiteRT-LM (.litertlm)
  /// iOS: MediaPipe (.task) only
  /// Web: MediaPipe (.litertlm web) only
  /// Desktop: LiteRT-LM (.litertlm) only
  static List<_MultimodalConfig> allForCurrentPlatform() {
    if (kIsWeb) {
      return [
        const _MultimodalConfig(
          url: _gemma3nWebUrl,
          filename: 'gemma-3n-E2B-it-int4-Web.litertlm',
          label: 'Web MediaPipe',
          supportsAudio: false,
        ),
      ];
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return [
        _MultimodalConfig(
          url: _gemma3nLitertlmUrl,
          filename: 'gemma-3n-E2B-it-int4.litertlm',
          label: 'Desktop LiteRT-LM',
          // macOS vision broken (SDK bug #684) — max_num_images:0 in JVM SDK
          supportsVision: !Platform.isMacOS,
          supportsAudio: true,
        ),
      ];
    }
    if (Platform.isIOS) {
      return [
        const _MultimodalConfig(
          url: _gemma3nTaskUrl,
          filename: 'gemma-3n-E2B-it-int4.task',
          label: 'iOS MediaPipe',
          supportsAudio: false,
        ),
      ];
    }
    // Android — both engines
    return [
      const _MultimodalConfig(
        url: _gemma3nTaskUrl,
        filename: 'gemma-3n-E2B-it-int4.task',
        label: 'Android MediaPipe',
        supportsAudio: false,
      ),
      const _MultimodalConfig(
        url: _gemma3nLitertlmUrl,
        filename: 'gemma-3n-E2B-it-int4.litertlm',
        label: 'Android LiteRT-LM',
        supportsAudio: true,
      ),
    ];
  }
}

/// Load test image from bundled assets.
Future<Uint8List> _loadTestImage() async {
  final data = await rootBundle.load('assets/test/test_image.jpg');
  return data.buffer.asUint8List();
}

/// Load test audio from bundled assets as complete WAV bytes.
/// LiteRT-LM SDK uses miniaudio decoder which expects WAV format with header.
Future<Uint8List> _loadTestAudio() async {
  final data = await rootBundle.load('assets/test/test_audio.wav');
  final wavBytes = data.buffer.asUint8List();
  print('[Audio] WAV loaded: ${wavBytes.length} bytes');
  return wavBytes;
}

/// Install Gemma 3n model with HF auth token.
Future<void> _installMultimodalModel(_MultimodalConfig config) async {
  print('[Multimodal/${config.label}] Installing ${config.filename}...');

  await FlutterGemma.installModel(
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
  )
      .fromNetwork(config.url, token: _hfToken, foreground: true)
      .withProgress((progress) =>
          print('[Multimodal/${config.label}] Download: $progress%'))
      .install();

  print('[Multimodal/${config.label}] Model installed');
}

void main() {
  initIntegrationTest();

  for (final config in _MultimodalConfig.allForCurrentPlatform()) {
    if (config.supportsVision) {
      _runVisionTest(config);
    }
    if (config.supportsAudio) {
      _runAudioTest(config);
    }
  }
}

void _runVisionTest(_MultimodalConfig config) {
  testWidgets('Multimodal: vision (${config.label})', (tester) async {
    await FlutterGemma.initialize();
    await _installMultimodalModel(config);

    final imageBytes = await _loadTestImage();
    print('[Vision/${config.label}] Image loaded: ${imageBytes.length} bytes');

    final model = await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.gpu,
      supportImage: true,
      maxNumImages: 1,
    );
    try {
      final chat = await model.createChat(
        modelType: ModelType.gemmaIt,
        supportImage: true,
      );

      await chat.addQueryChunk(Message.withImage(
        text: 'What do you see in this image? Describe briefly.',
        imageBytes: imageBytes,
        isUser: true,
      ));

      final response = await chat.generateChatResponse();
      expect(response, isA<TextResponse>());
      final text = (response as TextResponse).token;
      print('[Vision/${config.label}] Response: '
          '"${text.length > 150 ? text.substring(0, 150) : text}"');
      expect(text, isNotEmpty,
          reason: 'Vision response should be non-empty');
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

void _runAudioTest(_MultimodalConfig config) {
  testWidgets('Multimodal: audio (${config.label})', (tester) async {
    await FlutterGemma.initialize();
    await _installMultimodalModel(config);

    final audioBytes = await _loadTestAudio();
    print('[Audio/${config.label}] Audio loaded: ${audioBytes.length} bytes PCM');

    final model = await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.gpu,
      supportAudio: true,
    );
    try {
      final chat = await model.createChat(
        modelType: ModelType.gemmaIt,
        supportAudio: true,
      );

      await chat.addQueryChunk(Message.withAudio(
        text: 'What is being said in this audio? Transcribe it.',
        audioBytes: audioBytes,
        isUser: true,
      ));

      final response = await chat.generateChatResponse();
      expect(response, isA<TextResponse>());
      final text = (response as TextResponse).token;
      print('[Audio/${config.label}] Response: '
          '"${text.length > 150 ? text.substring(0, 150) : text}"');
      expect(text, isNotEmpty,
          reason: 'Audio response should be non-empty');
    } finally {
      await model.close();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
