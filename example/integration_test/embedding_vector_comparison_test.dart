// Integration test: compare embedding vectors across platforms.
// Run on macOS:   flutter test integration_test/embedding_vector_comparison_test.dart -d macos
// Run on Android: flutter test integration_test/embedding_vector_comparison_test.dart -d <device_id>

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// EmbeddingGemma 300M seq256 — same model used in RAG example
const _modelUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite';
const _tokenizerUrl =
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Embedding vector comparison', (tester) async {
    final platform = Platform.operatingSystem;
    print('=== Platform: $platform ===');

    // 1. Initialize
    await FlutterGemma.initialize();

    // 2. Install embedding model
    final hfToken = const String.fromEnvironment('HF_TOKEN');
    await FlutterGemma.installEmbedder()
        .modelFromNetwork(_modelUrl, token: hfToken.isNotEmpty ? hfToken : null)
        .tokenizerFromNetwork(_tokenizerUrl, token: hfToken.isNotEmpty ? hfToken : null)
        .withModelProgress((p) => print('[Download] $p%'))
        .install();

    // 3. Create embedding model
    final embedder = await FlutterGemma.getActiveEmbedder();

    // 4. Generate embeddings for test phrases
    final testPhrases = [
      'Hello world',
      'The cat sat on the mat',
      'Machine learning is fascinating',
    ];

    for (final phrase in testPhrases) {
      final embedding = await embedder.generateEmbedding(phrase);
      final dim = embedding.length;

      // Log first 10 values
      final first10 = embedding.take(10).map((v) => v.toStringAsFixed(6)).join(', ');
      // Log last 5 values
      final last5 = embedding.skip(dim - 5).map((v) => v.toStringAsFixed(6)).join(', ');

      // Compute L2 norm
      double norm = 0;
      for (final v in embedding) {
        norm += v * v;
      }
      norm = norm > 0 ? norm : 0;

      print('');
      print('--- "$phrase" ---');
      print('[$platform] dim=$dim, norm=${norm.toStringAsFixed(6)}');
      print('[$platform] first10: [$first10]');
      print('[$platform] last5:  [$last5]');
    }

    // 5. Cosine similarity between phrases
    final emb1 = await embedder.generateEmbedding(testPhrases[0]);
    final emb2 = await embedder.generateEmbedding(testPhrases[1]);
    final emb3 = await embedder.generateEmbedding(testPhrases[2]);

    double cosine(List<double> a, List<double> b) {
      double dot = 0, na = 0, nb = 0;
      for (int i = 0; i < a.length; i++) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
      }
      if (na == 0 || nb == 0) return 0;
      return dot / (na * nb > 0 ? (na * nb) : 1);
    }

    print('');
    print('=== Cosine similarities ===');
    print('[$platform] "Hello world" vs "The cat sat on the mat": ${cosine(emb1, emb2).toStringAsFixed(6)}');
    print('[$platform] "Hello world" vs "Machine learning": ${cosine(emb1, emb3).toStringAsFixed(6)}');
    print('[$platform] "The cat" vs "Machine learning": ${cosine(emb2, emb3).toStringAsFixed(6)}');

    await embedder.close();
  });
}
