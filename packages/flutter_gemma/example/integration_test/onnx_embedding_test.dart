// Integration test: ONNX embedding model cosine-similarity validation.
//
// Verifies end-to-end: OnnxEmbeddingBackend → FlutterOrtClient → ONNX Runtime
// → EmbeddingGemma ONNX (int8 quantised) → cosine-similarity ordering.
//
// Model: onnx-community/embeddinggemma-300m-ONNX / onnx/model_quantized.onnx
//   Files: model_quantized.onnx       (~555 KB graph)
//          model_quantized.onnx_data  (~295 MB int8 weights)
//          tokenizer.model            (~4.5 MB SentencePiece vocab)
//
// Why model_quantized (int8) not model_q4f16:
//   The q4f16 variant uses MLFloat16 weights which trigger a SIGSEGV in
//   MlasConvertHalfToFloatBuffer on macOS arm64 with onnxruntime-objc 1.24.2
//   (flutter_onnxruntime 1.8.0). Use the standard int8 quantized model instead.
//
// Prerequisites — copy files to the platform path before running:
//   macOS:   ~/Library/Containers/dev.flutterberlin.flutterGemmaExample55/
//              Data/Library/Application Support/
//              dev.flutterberlin.flutterGemmaExample55/flutter_gemma/
//   Linux:   ~/models/
//   Windows: %LOCALAPPDATA%\flutter_gemma\
//   Android: /data/local/tmp/flutter_gemma_test/
//   iOS:     downloaded via FlutterGemma.installEmbedder().modelFromNetwork()
//            (Simulator can reuse IOS_TEST_DOCS_DIR=<host macOS path>)
//
// Run on macOS (mandatory):
//   flutter test integration_test/onnx_embedding_test.dart -d macos
//
// Run on Android:
//   adb push ~/models/onnx_embedding/model_quantized.onnx \
//             /data/local/tmp/flutter_gemma_test/
//   adb push ~/models/onnx_embedding/model_quantized.onnx_data \
//             /data/local/tmp/flutter_gemma_test/
//   adb push ~/models/onnx_embedding/tokenizer.model \
//             /data/local/tmp/flutter_gemma_test/
//   flutter test integration_test/onnx_embedding_test.dart -d <device_id>

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';

// ---------------------------------------------------------------------------
// Model filenames — these must exist in the platform directory.
// ---------------------------------------------------------------------------

const _modelFilename = 'model_quantized.onnx';
const _tokenizerFilename = 'tokenizer.model';

// HuggingFace fallback URL (used on iOS where local paths may be unavailable).
const _hfBase =
    'https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX/resolve/main';
const _modelUrl = '$_hfBase/onnx/model_quantized.onnx';
const _modelDataUrl = '$_hfBase/onnx/model_quantized.onnx_data';
const _tokenizerUrl = '$_hfBase/tokenizer.model';

// ---------------------------------------------------------------------------
// Platform-conditional model paths (mirrors litertlm_ffi_test convention).
// ---------------------------------------------------------------------------

/// macOS Application Support path where flutter_gemma stores models.
///
/// When the test runs inside the macOS sandbox, [Platform.environment['HOME']]
/// is already the container root
/// (`~/Library/Containers/dev.flutterberlin.flutterGemmaExample55/Data/`), so
/// the Application Support sub-path is just `$HOME/Library/Application Support/
/// <bundleId>/flutter_gemma`.  We derive the bundle ID from the last segment of
/// the sandboxed HOME (or fall back to the known example bundle ID).
String get _macosDir {
  final home = Platform.environment['HOME'] ?? '';
  // Inside the sandbox HOME ends with /Data; outside it ends with the username.
  // Use path_provider-equivalent: $HOME/Library/Application Support/<bundleId>/flutter_gemma.
  const bundleId = 'dev.flutterberlin.flutterGemmaExample55';
  return '$home/Library/Application Support/$bundleId/flutter_gemma';
}

String get _linuxDir => '${Platform.environment['HOME']}/models';
String get _windowsDir =>
    '${Platform.environment['LOCALAPPDATA'] ?? ''}/flutter_gemma';
const String _androidDir = '/data/local/tmp/flutter_gemma_test';

/// Returns the absolute path to [filename] on the current platform, or null
/// when the file should be downloaded (iOS device / unsupported platform).
String? _localPath(String filename) {
  if (Platform.isAndroid) return '$_androidDir/$filename';
  if (Platform.isMacOS) return '$_macosDir/$filename';
  if (Platform.isLinux) return '$_linuxDir/$filename';
  if (Platform.isWindows) return '$_windowsDir\\$filename';
  if (Platform.isIOS) {
    // iOS Simulator: reuse host macOS models via dart-define.
    const iosDocs = String.fromEnvironment('IOS_TEST_DOCS_DIR');
    if (iosDocs.isNotEmpty) {
      final p = '$iosDocs/$filename';
      if (File(p).existsSync()) return p;
    }
    return null; // device: fall through to network download
  }
  return null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double _cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length, 'Embedding length mismatch');
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = math.sqrt(normA) * math.sqrt(normB);
  return denom == 0 ? 0 : dot / denom;
}

// ---------------------------------------------------------------------------
// Test
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ONNX EmbeddingGemma: cosine similarity ordering (similar > different)',
    (WidgetTester tester) async {
      // 1. Register the ONNX embedding backend.
      await FlutterGemma.initialize(
        embeddingBackends: const [OnnxEmbeddingBackend()],
      );

      // 2. Install the ONNX model + tokenizer.
      //    Use modelFromFile on platforms with local files (macOS, Android,
      //    Linux, Windows); fall back to modelFromNetwork on iOS devices.
      final modelPath = _localPath(_modelFilename);
      final tokenizerPath = _localPath(_tokenizerFilename);

      final EmbeddingInstallationBuilder builder;
      if (modelPath != null && tokenizerPath != null) {
        // Verify that the companion .onnx_data file is present (ONNX External
        // Data format: graph + weights are split across two files).
        final dataFile = File('${modelPath}_data');
        expect(
          dataFile.existsSync(),
          isTrue,
          reason:
              'ONNX weights file missing: ${modelPath}_data\n'
              'Run: curl -L -o "${modelPath}_data" "$_modelDataUrl"',
        );

        builder = FlutterGemma.installEmbedder()
            .modelFromFile(modelPath)
            .tokenizerFromFile(tokenizerPath);
      } else {
        // iOS device (or unknown platform): download from HuggingFace.
        // Note: the .onnx_data companion is downloaded as part of the ORT
        // session initialisation if the model graph references it via an
        // external-data path, but here we provide the graph file URL only.
        // Real iOS CI should provision the files via IOS_TEST_DOCS_DIR.
        builder = FlutterGemma.installEmbedder()
            .modelFromNetwork(_modelUrl)
            .tokenizerFromNetwork(_tokenizerUrl);
      }

      await builder.install();

      expect(
        FlutterGemma.hasActiveEmbedder(),
        isTrue,
        reason: 'Active embedding model should be set after install',
      );

      // 3. Create the embedder.
      final model = await FlutterGemma.getActiveEmbedder();

      try {
        // 4a. Verify embedding dimension (EmbeddingGemma-300M → 768 dims).
        final dim = await model.getDimension();
        print('[onnx_embedding_test] Embedding dimension: $dim');
        expect(dim, equals(768));

        // 4b. Generate a non-zero embedding.
        final testEmb = await model.generateEmbedding('hello world');
        expect(testEmb.length, equals(768));
        expect(testEmb.any((v) => v != 0), isTrue, reason: 'Embedding is all zeros');

        // 4c. Repeatability — same input must produce bit-identical output.
        final testEmb2 = await model.generateEmbedding('hello world');
        expect(testEmb.length, equals(testEmb2.length));
        for (int i = 0; i < testEmb.length; i++) {
          expect(
            testEmb[i],
            closeTo(testEmb2[i], 1e-5),
            reason: 'Embedding not repeatable at index $i',
          );
        }

        // 4d. Semantic ordering: similar pair must score higher than
        //     dissimilar pair.
        const queryText = 'Which planet is known as the Red Planet';
        const similarText = 'Mars is famous for its reddish appearance';
        const differentText = 'The stock market closed higher today';

        final queryEmb = await model.generateEmbedding(queryText);
        final similarEmb = await model.generateEmbedding(similarText);
        final differentEmb = await model.generateEmbedding(differentText);

        final simScore = _cosineSimilarity(queryEmb, similarEmb);
        final diffScore = _cosineSimilarity(queryEmb, differentEmb);

        print('[onnx_embedding_test] cosine(similar): $simScore');
        print('[onnx_embedding_test] cosine(different): $diffScore');
        print('[onnx_embedding_test] gap: ${simScore - diffScore}');

        expect(
          simScore,
          greaterThan(0.3),
          reason: 'Similar texts cosine score too low: $simScore',
        );
        expect(
          simScore,
          greaterThan(diffScore),
          reason:
              'Similar score ($simScore) should be greater than different score ($diffScore)',
        );

        // 4e. Batch embeddings — returns one vector per input string.
        final batch = await model.generateEmbeddings([
          'machine learning',
          'neural networks',
          'pizza recipe',
        ]);
        expect(batch.length, equals(3));
        for (final emb in batch) {
          expect(emb.length, equals(768));
        }

        print('[onnx_embedding_test] All assertions passed.');
      } finally {
        await model.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
