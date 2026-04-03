// Benchmark comparison: Gemma 3 Nano E2B vs Gemma 4 E2B on Android (LiteRT-LM)
//
// Prerequisites:
//   adb push /path/to/gemma-3n-E2B-it-int4.litertlm /data/local/tmp/flutter_gemma_test/
//   adb push /path/to/gemma-4-E2B-it.litertlm /data/local/tmp/flutter_gemma_test/
//
// Run:
//   cd example
//   flutter test integration_test/benchmark_comparison_test.dart -d <device>

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'inference_test_helpers.dart';

// --- Model configs ---

const _deviceDir = '/data/local/tmp/flutter_gemma_test';

const _models = <_BenchmarkModelConfig>[
  _BenchmarkModelConfig(
    name: 'Gemma 4 E2B',
    filePath: '$_deviceDir/gemma-4-E2B-it.litertlm',
    filename: 'gemma-4-E2B-it.litertlm',
  ),
  _BenchmarkModelConfig(
    name: 'Gemma 3 Nano E2B',
    filePath: '$_deviceDir/gemma-3n-E2B-it-int4.litertlm',
    filename: 'gemma-3n-E2B-it-int4.litertlm',
  ),
];

class _BenchmarkModelConfig {
  final String name;
  final String filePath;
  final String filename;

  const _BenchmarkModelConfig({
    required this.name,
    required this.filePath,
    required this.filename,
  });
}

// --- Benchmark result ---

class BenchmarkResult {
  final String modelName;
  final String testCategory;
  final String testName;
  final String question;
  final String response;
  final int durationMs;
  final int firstTokenMs;
  final DateTime timestamp;

  BenchmarkResult({
    required this.modelName,
    required this.testCategory,
    required this.testName,
    required this.question,
    required this.response,
    required this.durationMs,
    required this.firstTokenMs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'model': modelName,
        'category': testCategory,
        'test': testName,
        'question': question,
        'response': response,
        'duration_ms': durationMs,
        'first_token_ms': firstTokenMs,
        'timestamp': timestamp.toIso8601String(),
      };
}

// --- Test data ---

const _textQuestions = <(String name, String question)>[
  ('simple_fact', 'What is the capital of France?'),
  ('explanation', 'Explain quantum entanglement in simple terms'),
  ('creative', 'Write a short poem about the sea'),
  ('technical', 'What are the main differences between TCP and UDP?'),
  (
    'multilingual',
    "Translate 'Hello, how are you?' to Spanish, French, and German"
  ),
];

const _chatSteps = <String>[
  "My name is Alex and I'm a software developer",
  "I'm working on a Flutter project for a hospital",
  "What's my name and what am I working on?",
  'Can you suggest a good architecture pattern for my project?',
  'Summarize our entire conversation in 2 sentences',
];

// --- Helpers ---

final _allResults = <BenchmarkResult>[];

Future<Uint8List> _loadTestImage() async {
  final data = await rootBundle.load('assets/test/test_image.jpg');
  return data.buffer.asUint8List();
}

Future<Uint8List> _loadTestAudio() async {
  final data = await rootBundle.load('assets/test/test_audio.wav');
  return data.buffer.asUint8List();
}

Future<void> _installBenchmarkModel(_BenchmarkModelConfig config) async {
  print('[Benchmark] Installing ${config.name} from ${config.filePath}');
  await FlutterGemma.installModel(
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
  ).fromFile(config.filePath).install();
  print('[Benchmark] ${config.name} installed');
}

/// Run a single text query via streaming and measure timing.
Future<BenchmarkResult> _runTextBenchmark({
  required String modelName,
  required InferenceChat chat,
  required String category,
  required String testName,
  required String question,
}) async {
  final sw = Stopwatch()..start();
  int firstTokenMs = -1;

  await chat.addQueryChunk(Message.text(text: question, isUser: true));

  final buffer = StringBuffer();
  await for (final response in chat.generateChatResponseAsync()) {
    if (response is TextResponse) {
      if (firstTokenMs < 0) {
        firstTokenMs = sw.elapsedMilliseconds;
      }
      buffer.write(response.token);
    }
  }
  sw.stop();

  final result = BenchmarkResult(
    modelName: modelName,
    testCategory: category,
    testName: testName,
    question: question,
    response: buffer.toString(),
    durationMs: sw.elapsedMilliseconds,
    firstTokenMs: firstTokenMs,
    timestamp: DateTime.now(),
  );

  print('[Benchmark] $modelName / $category / $testName');
  print(
      '  First token: ${result.firstTokenMs}ms, Total: ${result.durationMs}ms');
  print(
      '  Response: "${result.response.length > 100 ? result.response.substring(0, 100) : result.response}..."');

  return result;
}

/// Run a vision query via streaming and measure timing.
Future<BenchmarkResult> _runVisionBenchmark({
  required String modelName,
  required InferenceModel model,
  required String testName,
  required String question,
  required Uint8List imageBytes,
}) async {
  final chat = await model.createChat(
    modelType: ModelType.gemmaIt,
    supportImage: true,
  );

  try {
    final sw = Stopwatch()..start();
    int firstTokenMs = -1;

    await chat.addQueryChunk(Message.withImage(
      text: question,
      imageBytes: imageBytes,
      isUser: true,
    ));

    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        if (firstTokenMs < 0) {
          firstTokenMs = sw.elapsedMilliseconds;
        }
        buffer.write(response.token);
      }
    }
    sw.stop();

    final result = BenchmarkResult(
      modelName: modelName,
      testCategory: 'vision',
      testName: testName,
      question: question,
      response: buffer.toString(),
      durationMs: sw.elapsedMilliseconds,
      firstTokenMs: firstTokenMs,
      timestamp: DateTime.now(),
    );

    print('[Benchmark] $modelName / vision / $testName');
    print(
        '  First token: ${result.firstTokenMs}ms, Total: ${result.durationMs}ms');
    print(
        '  Response: "${result.response.length > 100 ? result.response.substring(0, 100) : result.response}..."');

    return result;
  } finally {
    await chat.close();
  }
}

/// Run an audio query via streaming and measure timing.
Future<BenchmarkResult> _runAudioBenchmark({
  required String modelName,
  required InferenceModel model,
  required String testName,
  required String question,
  required Uint8List audioBytes,
}) async {
  final chat = await model.createChat(
    modelType: ModelType.gemmaIt,
    supportAudio: true,
  );

  try {
    final sw = Stopwatch()..start();
    int firstTokenMs = -1;

    await chat.addQueryChunk(Message.withAudio(
      text: question,
      audioBytes: audioBytes,
      isUser: true,
    ));

    final buffer = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        if (firstTokenMs < 0) {
          firstTokenMs = sw.elapsedMilliseconds;
        }
        buffer.write(response.token);
      }
    }
    sw.stop();

    final result = BenchmarkResult(
      modelName: modelName,
      testCategory: 'audio',
      testName: testName,
      question: question,
      response: buffer.toString(),
      durationMs: sw.elapsedMilliseconds,
      firstTokenMs: firstTokenMs,
      timestamp: DateTime.now(),
    );

    print('[Benchmark] $modelName / audio / $testName');
    print(
        '  First token: ${result.firstTokenMs}ms, Total: ${result.durationMs}ms');
    print(
        '  Response: "${result.response.length > 100 ? result.response.substring(0, 100) : result.response}..."');

    return result;
  } finally {
    await chat.close();
  }
}

Future<void> _saveResults() async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final path = '/sdcard/Download/benchmark_results_$timestamp.json';
  final json = const JsonEncoder.withIndent('  ').convert(
    _allResults.map((r) => r.toJson()).toList(),
  );
  final file = File(path);
  await file.writeAsString(json);
  print('[Benchmark] Results saved to $path');
  print('[Benchmark] Total results: ${_allResults.length}');
}

// --- Main test ---

void main() {
  initIntegrationTest();

  testWidgets('Benchmark: Gemma 3 Nano E2B vs Gemma 4 E2B', (tester) async {
    if (!Platform.isAndroid) {
      markTestSkipped(
          'Benchmark only runs on Android (requires /data/local/tmp models)');
      return;
    }

    await FlutterGemma.initialize();

    // Pre-load test assets
    final imageBytes = await _loadTestImage();
    final audioBytes = await _loadTestAudio();
    print('[Benchmark] Test image: ${imageBytes.length} bytes');
    print('[Benchmark] Test audio: ${audioBytes.length} bytes');

    for (final modelConfig in _models) {
      print('\n${'=' * 60}');
      print('BENCHMARKING: ${modelConfig.name}');
      print('${'=' * 60}\n');

      // --- Install model ---
      await _installBenchmarkModel(modelConfig);

      // --- Text benchmarks (single-turn, new chat per question) ---
      {
        final model = await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.gpu,
        );
        try {
          for (final (name, question) in _textQuestions) {
            final chat = await model.createChat(
              modelType: ModelType.gemmaIt,
            );
            final result = await _runTextBenchmark(
              modelName: modelConfig.name,
              chat: chat,
              category: 'text',
              testName: name,
              question: question,
            );
            _allResults.add(result);
          }
        } finally {
          await model.close();
        }
      }

      // --- Multi-turn chat benchmark (single chat, 5 steps) ---
      {
        final model = await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.gpu,
        );
        try {
          final chat = await model.createChat(
            modelType: ModelType.gemmaIt,
          );

          for (var i = 0; i < _chatSteps.length; i++) {
            final result = await _runTextBenchmark(
              modelName: modelConfig.name,
              chat: chat,
              category: 'multi_turn',
              testName: 'step_${i + 1}',
              question: _chatSteps[i],
            );
            _allResults.add(result);
          }
        } finally {
          await model.close();
        }
      }

      // --- Vision benchmarks ---
      {
        final model = await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.gpu,
          supportImage: true,
          maxNumImages: 1,
        );
        try {
          final r1 = await _runVisionBenchmark(
            modelName: modelConfig.name,
            model: model,
            testName: 'describe_object',
            question: 'What do you see in this image? Describe it briefly.',
            imageBytes: imageBytes,
          );
          _allResults.add(r1);

          final r2 = await _runVisionBenchmark(
            modelName: modelConfig.name,
            model: model,
            testName: 'describe_detail',
            question: 'Describe everything you see in this image in detail.',
            imageBytes: imageBytes,
          );
          _allResults.add(r2);
        } finally {
          await model.close();
        }
      }

      // --- Audio benchmarks ---
      {
        final model = await FlutterGemma.getActiveModel(
          maxTokens: 4096,
          preferredBackend: PreferredBackend.gpu,
          supportAudio: true,
        );
        try {
          final r1 = await _runAudioBenchmark(
            modelName: modelConfig.name,
            model: model,
            testName: 'transcribe_short',
            question: 'What was said in this audio?',
            audioBytes: audioBytes,
          );
          _allResults.add(r1);

          final r2 = await _runAudioBenchmark(
            modelName: modelConfig.name,
            model: model,
            testName: 'transcribe_summarize',
            question: 'Transcribe this audio and summarize what was said.',
            audioBytes: audioBytes,
          );
          _allResults.add(r2);
        } finally {
          await model.close();
        }
      }

      print('\n[Benchmark] ${modelConfig.name} complete. '
          'Results so far: ${_allResults.length}');
    }

    // --- Save all results ---
    await _saveResults();
  }, timeout: const Timeout(Duration(minutes: 60)));
}
