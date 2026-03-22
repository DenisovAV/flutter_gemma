// Shared helpers for inference integration tests.
// Not a test file — imported by inference_*_test.dart files.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:integration_test/integration_test.dart';

/// Call once in main() of each test file.
void initIntegrationTest() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

/// Model URLs for FunctionGemma 270M IT (284MB, no auth required)
const _taskUrl =
    'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task';
const _litertlmUrl =
    'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm';

/// Platform-aware model configuration for inference tests.
class TestModelConfig {
  final String url;
  final String filename;
  final ModelFileType fileType;

  const TestModelConfig({
    required this.url,
    required this.filename,
    required this.fileType,
  });

  /// Default config for current platform:
  /// - Web/iOS/Android → .task (MediaPipe)
  /// - Desktop (macOS/Windows/Linux) → .litertlm (LiteRT-LM)
  static TestModelConfig forCurrentPlatform() {
    if (kIsWeb) return mediapipeConfig;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return litertlmConfig;
    }
    return mediapipeConfig; // Android, iOS
  }

  /// MediaPipe engine (.task)
  static const mediapipeConfig = TestModelConfig(
    url: _taskUrl,
    filename: 'functiongemma-270M-it.task',
    fileType: ModelFileType.task,
  );

  /// LiteRT-LM engine (.litertlm)
  static const litertlmConfig = TestModelConfig(
    url: _litertlmUrl,
    filename: 'functiongemma-270M-it.litertlm',
    fileType: ModelFileType.task,
  );

  /// All engine configs to test on current platform.
  /// Android gets both engines, others get one.
  static List<({TestModelConfig config, String label})>
      allForCurrentPlatform() {
    final configs = [
      (config: forCurrentPlatform(), label: 'default engine'),
    ];
    if (!kIsWeb && Platform.isAndroid) {
      configs.add((config: litertlmConfig, label: 'LiteRT-LM'));
    }
    return configs;
  }
}

/// Idempotent model installation — skips download if already active.
Future<void> ensureModelInstalled([TestModelConfig? config]) async {
  config ??= TestModelConfig.forCurrentPlatform();

  if (FlutterGemma.hasActiveModel()) {
    debugPrint('[Test] Active model found, skipping download');
    return;
  }

  await forceInstallModel(config);
}

/// Force install a specific model config (always installs, even if another model is active).
Future<void> forceInstallModel(TestModelConfig config) async {
  debugPrint('[Test] Installing model: ${config.filename} from ${config.url}');

  await FlutterGemma.installModel(
    modelType: ModelType.functionGemma,
    fileType: config.fileType,
  )
      .fromNetwork(config.url)
      .withProgress(
          (progress) => debugPrint('[Test] Download progress: $progress%'))
      .install();

  debugPrint('[Test] Model installed successfully');
}

/// Create a test model with conservative settings.
Future<InferenceModel> createTestModel({int maxTokens = 512}) async {
  return await FlutterGemma.getActiveModel(
    maxTokens: maxTokens,
    preferredBackend: PreferredBackend.cpu,
  );
}

/// Create a chat from a model with FunctionGemma model type.
Future<InferenceChat> createTestChat(InferenceModel model) async {
  return await model.createChat(
    modelType: ModelType.functionGemma,
  );
}
