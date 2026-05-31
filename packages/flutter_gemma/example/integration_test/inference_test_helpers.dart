// Shared helpers for inference integration tests.
// Not a test file — imported by inference_*_test.dart files.
//
// Prerequisites: push models to device before running tests:
//   ./scripts/prepare_test_models.sh [device_id]
//
// Models are loaded from /data/local/tmp/flutter_gemma_test/ on device.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:integration_test/integration_test.dart';

/// Call once in main() of each test file.
void initIntegrationTest() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

/// Device path where models are pushed via adb.
const _deviceModelDir = '/data/local/tmp/flutter_gemma_test';

/// Platform-aware model configuration for inference tests.
/// Models loaded from device filesystem (pushed via adb).
class TestModelConfig {
  final String filePath;
  final String filename;
  final ModelFileType fileType;

  const TestModelConfig({
    required this.filePath,
    required this.filename,
    required this.fileType,
  });

  /// Default config for current platform.
  static TestModelConfig forCurrentPlatform() {
    return mediapipeConfig;
  }

  /// MediaPipe engine (.task)
  static const mediapipeConfig = TestModelConfig(
    filePath: '$_deviceModelDir/functiongemma-270M-it.task',
    filename: 'functiongemma-270M-it.task',
    fileType: ModelFileType.task,
  );

  /// All engine configs to test on current platform.
  static List<({TestModelConfig config, String label})>
      allForCurrentPlatform() {
    return [
      (config: forCurrentPlatform(), label: 'default engine'),
    ];
  }
}

/// Idempotent model installation — skips if already active.
Future<void> ensureModelInstalled([TestModelConfig? config]) async {
  config ??= TestModelConfig.forCurrentPlatform();

  if (FlutterGemma.hasActiveModel()) {
    debugPrint('[Test] Active model found, skipping install');
    return;
  }

  await forceInstallModel(config);
}

/// Force install a specific model config from device file.
Future<void> forceInstallModel(TestModelConfig config) async {
  debugPrint('[Test] Installing model from file: ${config.filePath}');

  await FlutterGemma.installModel(
    modelType: ModelType.functionGemma,
    fileType: config.fileType,
  ).fromFile(config.filePath).install();

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
