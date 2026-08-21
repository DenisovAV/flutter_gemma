// Unit tests for `OnnxEmbeddingBackend` — provider identity, priority, and
// the `.onnx`/`.ort` extension-matrix `canHandle` (Phase 2 hardened plan
// Task 3). No native session, no dlopen.

import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma_onnx/src/embedding/onnx_embedding_backend.dart';
import 'package:flutter_test/flutter_test.dart';

EmbeddingModelSpec _spec(String modelFilename) => EmbeddingModelSpec(
  name: 'test-$modelFilename',
  modelSource: FileSource('/tmp/$modelFilename'),
  tokenizerSource: FileSource('/tmp/tokenizer.json'),
);

void main() {
  group('OnnxEmbeddingBackend identity', () {
    test('name is "ONNX Embedding", priority is 10 (above LiteRT\'s '
        'catch-all 0)', () {
      const backend = OnnxEmbeddingBackend();
      expect(backend.name, 'ONNX Embedding');
      expect(backend.priority, 10);
    });
  });

  group('OnnxEmbeddingBackend.canHandle extension matrix', () {
    const backend = OnnxEmbeddingBackend();

    test('handles .onnx (single-file export)', () {
      expect(backend.canHandle(_spec('model.onnx')), isTrue);
    });

    test('handles .ort (ORT-optimized format)', () {
      expect(backend.canHandle(_spec('model.ort')), isTrue);
    });

    test('does not handle .tflite (LiteRT\'s territory)', () {
      expect(backend.canHandle(_spec('model.tflite')), isFalse);
    });

    test('does not handle an extensionless / unrecognized filename', () {
      expect(backend.canHandle(_spec('model')), isFalse);
      expect(backend.canHandle(_spec('model.bin')), isFalse);
    });
  });

  group('OnnxEmbeddingBackend.createModel guards', () {
    test('throws when config.tokenizerPath is null', () async {
      const backend = OnnxEmbeddingBackend();
      const config = RuntimeConfig(
        maxTokens: 1024,
        modelPath: '/tmp/model.onnx',
      );

      await expectLater(
        backend.createModel(_spec('model.onnx'), config),
        throwsA(isA<StateError>()),
      );
    });
  });

  group(
    'OnnxEmbeddingBackend platform gate (debugForceUnsupportedHost seam)',
    () {
      tearDown(() {
        OnnxEmbeddingBackend.debugForceUnsupportedHost = null;
      });

      test('canHandle stays true on an unsupported host (must NOT gate — '
          'gating here would let the LiteRT catch-all silently claim the '
          'file instead)', () {
        OnnxEmbeddingBackend.debugForceUnsupportedHost = true;
        const backend = OnnxEmbeddingBackend();

        expect(backend.canHandle(_spec('model.onnx')), isTrue);
      });

      test('createModel throws a StateError naming the platform when the '
          'host is unsupported', () async {
        OnnxEmbeddingBackend.debugForceUnsupportedHost = true;
        const backend = OnnxEmbeddingBackend();
        const config = RuntimeConfig(
          maxTokens: 1024,
          modelPath: '/tmp/model.onnx',
          tokenizerPath: '/tmp/tokenizer.json',
        );

        await expectLater(
          backend.createModel(_spec('model.onnx'), config),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('unsupported host'), contains('macOS-arm64')),
            ),
          ),
        );
      });
    },
  );
}
