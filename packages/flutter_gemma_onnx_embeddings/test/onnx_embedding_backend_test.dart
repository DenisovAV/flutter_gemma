import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma_onnx_embeddings/flutter_gemma_onnx_embeddings.dart';

EmbeddingModelSpec _specWith(ModelSource modelSource) => EmbeddingModelSpec(
      name: 'test',
      modelSource: modelSource,
      tokenizerSource: AssetSource('assets/tokenizer.json'),
    );

void main() {
  const backend = OnnxEmbeddingBackend();

  test('OnnxEmbeddingBackend has stable identity', () {
    expect(backend.name, 'ONNX Embedding');
    expect(backend.priority, 0);
  });

  group('canHandle', () {
    test('returns true for NetworkSource with query-string URL (.onnx)', () {
      final spec = _specWith(
        NetworkSource('https://example.com/model.onnx?token=abc'),
      );
      expect(backend.canHandle(spec), isTrue);
    });

    test('returns true for NetworkSource with clean URL (.ort)', () {
      final spec = _specWith(
        NetworkSource('https://example.com/model.ort'),
      );
      expect(backend.canHandle(spec), isTrue);
    });

    test('returns true for FileSource (.onnx)', () {
      final spec = _specWith(FileSource('/data/models/model.onnx'));
      expect(backend.canHandle(spec), isTrue);
    });

    test('returns true for AssetSource (.ort)', () {
      final spec = _specWith(AssetSource('assets/models/model.ort'));
      expect(backend.canHandle(spec), isTrue);
    });

    test('returns false for NetworkSource with .task extension', () {
      final spec = _specWith(NetworkSource('https://example.com/model.task'));
      expect(backend.canHandle(spec), isFalse);
    });

    test('returns false for FileSource with .bin extension', () {
      final spec = _specWith(FileSource('/data/models/model.bin'));
      expect(backend.canHandle(spec), isFalse);
    });
  });
}
