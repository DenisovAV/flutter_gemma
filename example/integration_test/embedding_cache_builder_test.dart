// Generate 5000 EmbeddingGemma vectors (768D) from deterministic lorem
// chunks (seed=42, same word distribution as the bench) and cache them
// to disk so the parallel bench can read them back without spending
// 20-25 minutes on embedding inference each run.
//
// Splits the work into chunks of 500 with embedder.close() + reopen
// between chunks to avoid whatever resource-accumulation issue on the
// Windows desktop runner kills a single 5000-call loop at ~03:23.
//
// Run:
//   cd example && flutter test integration_test/embedding_cache_builder_test.dart -d windows
//
// Output: <ApplicationSupportDirectory>/embeddings_cache_5000_768d.json
// Read by vector_store_benchmark_cached_test.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath =
    'assets/models/embeddinggemma-300M_seq256_mixed-precision.tflite';
const _tokenizerPath = 'assets/models/sentencepiece.model';

const _totalDocs = 5000;
const _chunkSize = 500;

const _loremWords = [
  'lorem',
  'ipsum',
  'dolor',
  'sit',
  'amet',
  'consectetur',
  'adipiscing',
  'elit',
  'sed',
  'do',
  'eiusmod',
  'tempor',
  'incididunt',
  'ut',
  'labore',
  'magna',
  'aliqua',
  'enim',
  'ad',
  'minim',
  'veniam',
  'quis',
  'nostrud',
  'exercitation',
  'ullamco',
  'laboris',
  'nisi',
  'aliquip',
  'ex',
  'ea',
  'commodo',
  'consequat',
  'duis',
  'aute',
  'irure',
  'in',
  'reprehenderit',
  'voluptate',
  'velit',
  'esse',
  'cillum',
  'dolore',
  'eu',
  'fugiat',
  'nulla',
  'pariatur',
  'excepteur',
  'sint',
  'occaecat',
  'cupidatat',
  'non',
  'proident',
  'sunt',
  'culpa',
  'qui',
  'officia',
  'deserunt',
  'mollit',
  'anim',
  'id',
  'laborum',
  'curabitur',
  'pretium',
  'tincidunt',
  'lacus',
  'gravida',
  'orci',
  'a',
  'odio',
  'nullam',
  'varius',
  'turpis',
  'et',
];

String _chunk(math.Random rng, int wordCount) {
  final words = List.generate(
      wordCount, (_) => _loremWords[rng.nextInt(_loremWords.length)]);
  return words.join(' ');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultTestTimeout = const Timeout(Duration(hours: 2));

  testWidgets('build embedding cache (5000 × 768D)',
      (WidgetTester tester) async {
    await tester.runAsync(() async {
      await FlutterGemma.initialize();
      await FlutterGemma.installEmbedder()
          .modelFromAsset(_modelPath)
          .tokenizerFromAsset(_tokenizerPath)
          .install();

      final rng = math.Random(42);
      final texts =
          List.generate(_totalDocs, (_) => _chunk(rng, 30 + rng.nextInt(50)));
      // ignore: avoid_print
      print('[cache] generated $_totalDocs lorem chunks');

      final allVectors = <List<double>>[];
      final overallSw = Stopwatch()..start();

      for (var chunkStart = 0;
          chunkStart < _totalDocs;
          chunkStart += _chunkSize) {
        final chunkEnd = math.min(chunkStart + _chunkSize, _totalDocs);
        final chunkSw = Stopwatch()..start();

        // Fresh embedder per chunk.
        final embedder = await FlutterGemma.getActiveEmbedder();

        for (var i = chunkStart; i < chunkEnd; i++) {
          allVectors.add(await embedder.generateEmbedding(texts[i]));
        }
        chunkSw.stop();

        // Release native resources before the next chunk.
        await embedder.close();
        await Future.delayed(const Duration(seconds: 1));

        // ignore: avoid_print
        print('[cache] chunk ${chunkStart ~/ _chunkSize + 1}/'
            '${_totalDocs ~/ _chunkSize}: '
            'embedded ${chunkEnd - chunkStart} in ${chunkSw.elapsed.inSeconds}s '
            '(total ${allVectors.length}/$_totalDocs, '
            '${overallSw.elapsed.inSeconds}s elapsed)');
      }

      overallSw.stop();
      // ignore: avoid_print
      print('[cache] all $_totalDocs vectors generated in '
          '${overallSw.elapsed.inSeconds}s');

      final dim = allVectors.first.length;
      final out = File(
          '${(await getApplicationSupportDirectory()).path}/embeddings_cache_${_totalDocs}_${dim}d.json');
      out.writeAsStringSync(jsonEncode({
        'count': _totalDocs,
        'dim': dim,
        'seed': 42,
        'corpus_chars_per_doc_avg':
            (texts.fold<int>(0, (s, t) => s + t.length) / texts.length).round(),
        'vectors': allVectors,
      }));
      // ignore: avoid_print
      print('[cache] written: ${out.path}');
    });
  });
}
