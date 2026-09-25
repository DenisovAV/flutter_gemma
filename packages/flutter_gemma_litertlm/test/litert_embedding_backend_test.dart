// Moved from flutter_gemma_embeddings/test/litert_embedding_backend_test.dart
// (embedder decoupling plan Task 4/5 — LiteRtEmbeddingBackend now lives in
// this package).

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma.dart'
    show FileSource, PreferredBackend;
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LiteRtEmbeddingBackend identity', () {
    const b = LiteRtEmbeddingBackend();
    expect(b.name, 'LiteRT Embedding');
    expect(b.priority, 0);
  });

  // One test rather than three: the "say it once" flag is process-global, so
  // the three cases only mean anything in this order, in one isolate.
  test('a requested backend is refused out loud, once', () async {
    const backend = LiteRtEmbeddingBackend();
    final spec = EmbeddingModelSpec(
      name: 'test',
      modelSource: FileSource('/tmp/model.tflite'),
      tokenizerSource: FileSource('/tmp/tokenizer.json'),
    );
    RuntimeConfig configFor(PreferredBackend? backend) => RuntimeConfig(
      maxTokens: 512,
      modelPath: '/tmp/model.tflite',
      preferredBackend: backend,
    );

    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    addTearDown(() => debugPrint = original);

    // The warning fires before the tokenizerPath check, so every call below
    // throws. That is not what this test is about — the log line is.
    Future<void> build(PreferredBackend? b) async {
      await expectLater(
        backend.createModel(spec, configFor(b)),
        throwsStateError,
      );
    }

    await build(PreferredBackend.cpu);
    expect(
      printed.join('\n'),
      isNot(contains('preferredBackend')),
      reason: 'CPU is what this path does; asking for it is not worth a line',
    );

    await build(PreferredBackend.gpu);
    final firstWarning = printed.where((l) => l.contains('preferredBackend'));
    expect(firstWarning, hasLength(1));
    expect(firstWarning.single, contains('gpu'));
    expect(
      firstWarning.single,
      contains('all-zero'),
      reason: 'the line has to say why CPU is correct, not just that it won',
    );

    await build(PreferredBackend.gpu);
    expect(
      printed.where((l) => l.contains('preferredBackend')),
      hasLength(1),
      reason: 'once per process — a per-embedder line would drown the console',
    );
  });
}
