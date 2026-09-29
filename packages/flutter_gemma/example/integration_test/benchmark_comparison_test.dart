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
import 'package:flutter_gemma_diagnostics/flutter_gemma_diagnostics.dart';

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
  final BenchmarkMemory memory;

  BenchmarkResult({
    required this.modelName,
    required this.testCategory,
    required this.testName,
    required this.question,
    required this.response,
    required this.durationMs,
    required this.firstTokenMs,
    required this.timestamp,
    required this.memory,
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
    'memory': memory.toJson(),
  };
}

// --- Memory ---

/// Anonymous bytes around one model load; null where unreadable.
typedef LoadMemory = ({int? before, int? after});

/// What the OS charged this app around one prompt, from
/// `flutter_gemma_diagnostics`.
///
/// Read these as samples at the boundaries, not as a high-water mark: a peak
/// inside a long generation can be missed, and Android keeps no
/// anonymous-only peak to read instead.
///
/// `anonymous_bytes` is memory the OS cannot reclaim by dropping file pages.
/// It excludes weights read from an mmapped file, and on Android it excludes
/// GPU memory (KGSL, Mali, dmabuf sit outside smaps), so with
/// `PreferredBackend.gpu` the load delta understates what the model costs.
/// `before_prompt` - `after_load` is everything since the load: creating the
/// chat, plus any earlier prompts in the same phase.
class BenchmarkMemory {
  const BenchmarkMemory({
    this.beforeLoad,
    this.afterLoad,
    this.beforePrompt,
    this.afterPrompt,
    this.availableAfterPrompt,
  });

  final int? beforeLoad;
  final int? afterLoad;
  final int? beforePrompt;
  final int? afterPrompt;

  /// Device-wide `MemAvailable` on Android: an optimistic upper bound, since
  /// lmkd kills well before it reaches zero.
  final int? availableAfterPrompt;

  Map<String, dynamic> toJson() => {
    'anonymous_bytes': {
      'before_load': beforeLoad,
      'after_load': afterLoad,
      'before_prompt': beforePrompt,
      'after_prompt': afterPrompt,
    },
    'available_bytes_after_prompt': availableAfterPrompt,
  };

  /// One line for the live log: `load +812.3 MiB, prompt +4.1 MiB`.
  String describe() =>
      'load ${_signedMiB(beforeLoad, afterLoad)}, '
      'prompt ${_signedMiB(beforePrompt, afterPrompt)} (anonymous)';
}

String _signedMiB(int? before, int? after) {
  if (before == null || after == null) return 'n/a';
  final mib = (after - before) / (1024 * 1024);
  return '${mib >= 0 ? '+' : ''}${mib.toStringAsFixed(1)} MiB';
}

// --- Test data ---

const _textQuestions = <(String name, String question)>[
  ('simple_fact', 'What is the capital of France?'),
  ('explanation', 'Explain quantum entanglement in simple terms'),
  ('creative', 'Write a short poem about the sea'),
  ('technical', 'What are the main differences between TCP and UDP?'),
  (
    'multilingual',
    "Translate 'Hello, how are you?' to Spanish, French, and German",
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

/// Reads this process's memory from the OS. Null where the package does not
/// run, or where a read fails: the failure is logged and recorded as missing
/// numbers rather than thrown, because it must not abort a 60-minute run. The
/// package itself still throws; that a benchmark outlives a failed read is
/// this consumer's call.
Future<MemorySnapshot?> _sampleMemory() async {
  if (!FlutterGemmaDiagnostics.isSupported) return null;
  try {
    return await FlutterGemmaDiagnostics.memorySnapshot();
  } on MemoryReadException catch (e) {
    print('[Benchmark] memory read failed: $e');
    return null;
  }
}

/// Loads a model and reports the anonymous memory before and after: what
/// holding it costs before any prompt runs.
Future<(InferenceModel, LoadMemory)> _measuredLoad(
  Future<InferenceModel> Function() load,
) async {
  final before = (await _sampleMemory())?.anonymousBytes;
  final model = await load();
  final after = (await _sampleMemory())?.anonymousBytes;
  return (model, (before: before, after: after));
}

BenchmarkMemory _promptMemory(
  LoadMemory load,
  MemorySnapshot? before,
  MemorySnapshot? after,
) => BenchmarkMemory(
  beforeLoad: load.before,
  afterLoad: load.after,
  beforePrompt: before?.anonymousBytes,
  afterPrompt: after?.anonymousBytes,
  availableAfterPrompt: after?.availableBytes,
);

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
  required LoadMemory load,
}) async {
  final memoryBefore = await _sampleMemory();
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
  final memoryAfter = await _sampleMemory();

  final result = BenchmarkResult(
    modelName: modelName,
    testCategory: category,
    testName: testName,
    question: question,
    response: buffer.toString(),
    durationMs: sw.elapsedMilliseconds,
    firstTokenMs: firstTokenMs,
    timestamp: DateTime.now(),
    memory: _promptMemory(load, memoryBefore, memoryAfter),
  );

  print('[Benchmark] $modelName / $category / $testName');
  print(
    '  First token: ${result.firstTokenMs}ms, Total: ${result.durationMs}ms',
  );
  print('  Memory: ${result.memory.describe()}');
  print(
    '  Response: "${result.response.length > 100 ? result.response.substring(0, 100) : result.response}..."',
  );

  return result;
}

/// Run a vision query via streaming and measure timing.
Future<BenchmarkResult> _runVisionBenchmark({
  required String modelName,
  required InferenceModel model,
  required String testName,
  required String question,
  required Uint8List imageBytes,
  required LoadMemory load,
}) async {
  final chat = await model.createChat(
    modelType: ModelType.gemmaIt,
    supportImage: true,
  );

  try {
    final memoryBefore = await _sampleMemory();
    final sw = Stopwatch()..start();
    int firstTokenMs = -1;

    await chat.addQueryChunk(
      Message.withImage(text: question, imageBytes: imageBytes, isUser: true),
    );

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
    final memoryAfter = await _sampleMemory();

    final result = BenchmarkResult(
      modelName: modelName,
      testCategory: 'vision',
      testName: testName,
      question: question,
      response: buffer.toString(),
      durationMs: sw.elapsedMilliseconds,
      firstTokenMs: firstTokenMs,
      timestamp: DateTime.now(),
      memory: _promptMemory(load, memoryBefore, memoryAfter),
    );

    print('[Benchmark] $modelName / vision / $testName');
    print(
      '  First token: ${result.firstTokenMs}ms, Total: ${result.durationMs}ms',
    );
    print('  Memory: ${result.memory.describe()}');
    print(
      '  Response: "${result.response.length > 100 ? result.response.substring(0, 100) : result.response}..."',
    );

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
  required LoadMemory load,
}) async {
  final chat = await model.createChat(
    modelType: ModelType.gemmaIt,
    supportAudio: true,
  );

  try {
    final memoryBefore = await _sampleMemory();
    final sw = Stopwatch()..start();
    int firstTokenMs = -1;

    await chat.addQueryChunk(
      Message.withAudio(text: question, audioBytes: audioBytes, isUser: true),
    );

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
    final memoryAfter = await _sampleMemory();

    final result = BenchmarkResult(
      modelName: modelName,
      testCategory: 'audio',
      testName: testName,
      question: question,
      response: buffer.toString(),
      durationMs: sw.elapsedMilliseconds,
      firstTokenMs: firstTokenMs,
      timestamp: DateTime.now(),
      memory: _promptMemory(load, memoryBefore, memoryAfter),
    );

    print('[Benchmark] $modelName / audio / $testName');
    print(
      '  First token: ${result.firstTokenMs}ms, Total: ${result.durationMs}ms',
    );
    print('  Memory: ${result.memory.describe()}');
    print(
      '  Response: "${result.response.length > 100 ? result.response.substring(0, 100) : result.response}..."',
    );

    return result;
  } finally {
    await chat.close();
  }
}

Future<void> _saveResults() async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final path = '/sdcard/Download/benchmark_results_$timestamp.json';
  final json = const JsonEncoder.withIndent(
    '  ',
  ).convert(_allResults.map((r) => r.toJson()).toList());
  final file = File(path);
  await file.writeAsString(json);
  print('[Benchmark] Results saved to $path');
  print('[Benchmark] Total results: ${_allResults.length}');
}

// --- Main test ---

void main() {
  initIntegrationTest();

  testWidgets(
    'Benchmark: Gemma 3 Nano E2B vs Gemma 4 E2B',
    (tester) async {
      if (!Platform.isAndroid) {
        markTestSkipped(
          'Benchmark only runs on Android (requires /data/local/tmp models)',
        );
        return;
      }

      await registerTestEngines();

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
          final (model, load) = await _measuredLoad(
            () => FlutterGemma.getActiveModel(
              maxTokens: 4096,
              preferredBackend: PreferredBackend.gpu,
            ),
          );
          try {
            for (final (name, question) in _textQuestions) {
              final chat = await model.createChat(modelType: ModelType.gemmaIt);
              final result = await _runTextBenchmark(
                modelName: modelConfig.name,
                load: load,
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
          final (model, load) = await _measuredLoad(
            () => FlutterGemma.getActiveModel(
              maxTokens: 4096,
              preferredBackend: PreferredBackend.gpu,
            ),
          );
          try {
            final chat = await model.createChat(modelType: ModelType.gemmaIt);

            for (var i = 0; i < _chatSteps.length; i++) {
              final result = await _runTextBenchmark(
                modelName: modelConfig.name,
                load: load,
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
          final (model, load) = await _measuredLoad(
            () => FlutterGemma.getActiveModel(
              maxTokens: 4096,
              preferredBackend: PreferredBackend.gpu,
              supportImage: true,
              maxNumImages: 1,
            ),
          );
          try {
            final r1 = await _runVisionBenchmark(
              modelName: modelConfig.name,
              load: load,
              model: model,
              testName: 'describe_object',
              question: 'What do you see in this image? Describe it briefly.',
              imageBytes: imageBytes,
            );
            _allResults.add(r1);

            final r2 = await _runVisionBenchmark(
              modelName: modelConfig.name,
              load: load,
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
          final (model, load) = await _measuredLoad(
            () => FlutterGemma.getActiveModel(
              maxTokens: 4096,
              preferredBackend: PreferredBackend.gpu,
              supportAudio: true,
            ),
          );
          try {
            final r1 = await _runAudioBenchmark(
              modelName: modelConfig.name,
              load: load,
              model: model,
              testName: 'transcribe_short',
              question: 'What was said in this audio?',
              audioBytes: audioBytes,
            );
            _allResults.add(r1);

            final r2 = await _runAudioBenchmark(
              modelName: modelConfig.name,
              load: load,
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

        print(
          '\n[Benchmark] ${modelConfig.name} complete. '
          'Results so far: ${_allResults.length}',
        );
      }

      // --- Save all results ---
      await _saveResults();
    },
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
