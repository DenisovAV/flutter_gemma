import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';

void main() {
  group('ModelSpec Tests', () {
    group('InferenceModelSpec', () {
      test('creates valid inference model spec', () {
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test_model',
          modelUrl: 'https://example.com/model.bin',
        );

        expect(spec.type, ModelManagementType.inference);
        expect(spec.name, 'test_model');
        expect(spec.files.length, 1);
        expect(spec.files.first.filename, 'model.bin');
        expect(spec.files.first.isRequired, true);
        expect(spec.isValid, true);
      });

      test('creates inference model spec with LoRA', () {
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test_model',
          modelUrl: 'https://example.com/model.bin',
          loraUrl: 'https://example.com/lora.bin',
        );

        expect(spec.files.length, 2);
        expect(spec.files[0].filename, 'model.bin');
        expect(spec.files[1].filename, 'lora.bin');
        expect(spec.files[0].isRequired, true);
        expect(spec.files[1].isRequired, false);
      });

      test('extracts filename from URL correctly', () {
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: 'test_model',
          modelUrl: 'https://huggingface.co/models/complex-path/model.bin?token=abc',
        );

        // Test via files list instead of deprecated getter
        expect(spec.files.first.filename, 'model.bin');
      });
    });

    group('EmbeddingModelSpec', () {
      test('creates valid embedding model spec', () {
        final spec = EmbeddingModelSpec.fromLegacyUrl(
          name: 'test_embedding',
          modelUrl: 'https://example.com/model.tflite',
          tokenizerUrl: 'https://example.com/tokenizer.json',
        );

        expect(spec.type, ModelManagementType.embedding);
        expect(spec.name, 'test_embedding');
        expect(spec.files.length, 2);
        expect(spec.files[0].filename, 'model.tflite');
        expect(spec.files[1].filename, 'tokenizer.json');
        expect(spec.files[0].isRequired, true);
        expect(spec.files[1].isRequired, true);
        expect(spec.isValid, true);
      });

      test('uses correct SharedPrefs keys', () {
        final spec = EmbeddingModelSpec.fromLegacyUrl(
          name: 'test_embedding',
          modelUrl: 'https://example.com/model.tflite',
          tokenizerUrl: 'https://example.com/tokenizer.json',
        );

        expect(spec.files[0].prefsKey, 'embedding_model_file');
        expect(spec.files[1].prefsKey, 'embedding_tokenizer_file');
      });
    });

    group('DownloadProgress', () {
      test('calculates overall progress correctly', () {
        // First file, 50% complete
        var progress = const DownloadProgress(
          currentFileIndex: 0,
          totalFiles: 2,
          currentFileProgress: 50,
          currentFileName: 'model.bin',
        );
        expect(progress.overallProgress, 25); // (0 + 0.5) / 2 * 100 = 25

        // Second file, 100% complete
        progress = const DownloadProgress(
          currentFileIndex: 1,
          totalFiles: 2,
          currentFileProgress: 100,
          currentFileName: 'tokenizer.json',
        );
        expect(progress.overallProgress, 100); // (1 + 1.0) / 2 * 100 = 100

        // All files complete
        progress = const DownloadProgress(
          currentFileIndex: 2,
          totalFiles: 2,
          currentFileProgress: 100,
          currentFileName: 'Complete',
        );
        expect(progress.overallProgress, 100);
      });

      test('handles edge cases', () {
        // No files
        var progress = const DownloadProgress(
          currentFileIndex: 0,
          totalFiles: 0,
          currentFileProgress: 0,
          currentFileName: 'none',
        );
        expect(progress.overallProgress, 0);

        // Progress over 100%
        progress = const DownloadProgress(
          currentFileIndex: 0,
          totalFiles: 1,
          currentFileProgress: 150,
          currentFileName: 'test',
        );
        expect(progress.overallProgress, 100); // Should be clamped
      });
    });
  });
}