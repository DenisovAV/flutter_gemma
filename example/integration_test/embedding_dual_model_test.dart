import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Integration test verifying both tokenizer types via public API.
///
/// EmbeddingGemma uses BPE tokenizer, Gecko uses Unigram tokenizer.
/// On iOS, tokenizer.json is auto-detected by model.type field in EmbeddingModel.swift.
/// On Android, SentencePiece C++ handles both formats natively.
void main() {
  const queryText = 'Which planet is known as the Red Planet';
  const similarText = 'Mars is famous for its reddish appearance';
  const differentText = 'The stock market closed higher today';

  double cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length);
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  Future<void> verifyEmbeddings(EmbeddingModel model, String label,
      {double minSimThreshold = 0.5, double maxDiffThreshold = 0.3}) async {
    // 1. Non-zero embeddings
    final queryEmb = await model.generateEmbedding(queryText);
    expect(queryEmb, isNotEmpty, reason: '$label: empty embeddings');
    expect(queryEmb.any((v) => v != 0), isTrue, reason: '$label: all zeros');

    // 2. Repeatability — same text produces identical embeddings
    final queryEmb2 = await model.generateEmbedding(queryText);
    expect(queryEmb.length, equals(queryEmb2.length));
    for (int i = 0; i < queryEmb.length; i++) {
      expect(queryEmb[i], closeTo(queryEmb2[i], 1e-6),
          reason: '$label: not repeatable at index $i');
    }

    // 3. Similar texts — high cosine similarity
    final similarEmb = await model.generateEmbedding(similarText);
    final simScore = cosineSimilarity(queryEmb, similarEmb);
    print('$label simSimilarity: $simScore');
    expect(simScore, greaterThan(minSimThreshold),
        reason: '$label: similar texts too different ($simScore)');

    // 4. Different texts — low cosine similarity
    final diffEmb = await model.generateEmbedding(differentText);
    final diffScore = cosineSimilarity(queryEmb, diffEmb);
    print('$label diffSimilarity: $diffScore');
    expect(diffScore, lessThan(maxDiffThreshold),
        reason: '$label: different texts too similar ($diffScore)');
  }

  patrolTest('Embedding: EmbeddingGemma (BPE) + Gecko (Unigram)', ($) async {
    await FlutterGemma.initialize();

    // --- EmbeddingGemma (BPE tokenizer on iOS) ---
    await FlutterGemma.installEmbedder()
        .modelFromAsset(
            'assets/models/embeddinggemma-300M_seq256_mixed-precision.tflite')
        .tokenizerFromAsset('assets/models/sentencepiece.model',
            iosPath: 'assets/models/embeddinggemma_tokenizer.json')
        .install();

    var model = await FlutterGemma.getActiveEmbedder();
    try {
      await verifyEmbeddings(model, 'EmbeddingGemma-BPE');
    } finally {
      await model.close();
    }

    // --- Gecko 64 (Unigram tokenizer on iOS) ---
    await FlutterGemma.installEmbedder()
        .modelFromAsset('assets/models/Gecko_64_quant.tflite')
        .tokenizerFromAsset('assets/models/sentencepiece.model',
            iosPath: 'assets/models/gecko_tokenizer.json')
        .install();

    model = await FlutterGemma.getActiveEmbedder();
    try {
      await verifyEmbeddings(model, 'Gecko64-Unigram',
          minSimThreshold: 0.3, maxDiffThreshold: 0.7);
    } finally {
      await model.close();
    }
  });
}
