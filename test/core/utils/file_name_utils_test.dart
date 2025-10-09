import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';

void main() {
  group('FileNameUtils', () {
    group('getBaseName', () {
      test('removes .task extension', () {
        expect(FileNameUtils.getBaseName('gemma-2b.task'), 'gemma-2b');
      });

      test('removes .bin extension', () {
        expect(FileNameUtils.getBaseName('model.bin'), 'model');
      });

      test('removes .tflite extension', () {
        expect(FileNameUtils.getBaseName('embedding.tflite'), 'embedding');
      });

      test('removes .json extension', () {
        expect(FileNameUtils.getBaseName('config.json'), 'config');
      });

      test('removes .model extension', () {
        expect(FileNameUtils.getBaseName('tokenizer.model'), 'tokenizer');
      });

      test('removes .litertlm extension', () {
        expect(FileNameUtils.getBaseName('model.litertlm'), 'model');
      });

      test('removes multiple extensions', () {
        expect(FileNameUtils.getBaseName('model.bin.task'), 'model');
      });

      test('handles no extension', () {
        expect(FileNameUtils.getBaseName('model'), 'model');
      });

      test('handles complex filenames', () {
        expect(
          FileNameUtils.getBaseName('gemma-3-2b-it-gpu-int8.bin'),
          'gemma-3-2b-it-gpu-int8',
        );
      });

      test('handles filename with path', () {
        expect(
          FileNameUtils.getBaseName('assets/models/gemma.task'),
          'assets/models/gemma',
        );
      });
    });

    group('supportedExtensions', () {
      test('contains all expected types', () {
        expect(FileNameUtils.supportedExtensions, contains('.task'));
        expect(FileNameUtils.supportedExtensions, contains('.bin'));
        expect(FileNameUtils.supportedExtensions, contains('.tflite'));
        expect(FileNameUtils.supportedExtensions, contains('.json'));
        expect(FileNameUtils.supportedExtensions, contains('.model'));
        expect(FileNameUtils.supportedExtensions, contains('.litertlm'));
      });

      test('has correct count', () {
        expect(FileNameUtils.supportedExtensions.length, 6);
      });
    });

    group('extensionRegexPattern', () {
      test('generates correct pattern', () {
        final pattern = FileNameUtils.extensionRegexPattern;
        expect(pattern, contains('task'));
        expect(pattern, contains('bin'));
        expect(pattern, contains('tflite'));
        expect(pattern, contains('json'));
        expect(pattern, contains('model'));
        expect(pattern, contains('litertlm'));
      });

      test('pattern matches valid extensions', () {
        final regex = RegExp(FileNameUtils.extensionRegexPattern);
        expect(regex.hasMatch('model.task'), true);
        expect(regex.hasMatch('file.bin'), true);
        expect(regex.hasMatch('embed.tflite'), true);
        expect(regex.hasMatch('config.json'), true);
        expect(regex.hasMatch('tokenizer.model'), true);
        expect(regex.hasMatch('file.litertlm'), true);
      });

      test('pattern rejects invalid extensions', () {
        final regex = RegExp(FileNameUtils.extensionRegexPattern);
        expect(regex.hasMatch('model.txt'), false);
        expect(regex.hasMatch('file.pdf'), false);
        expect(regex.hasMatch('noextension'), false);
      });
    });

    group('isSmallFile', () {
      test('identifies json files as small', () {
        expect(FileNameUtils.isSmallFile('.json'), true);
      });

      test('identifies model files as small', () {
        expect(FileNameUtils.isSmallFile('.model'), true);
      });

      test('identifies bin files as not small', () {
        expect(FileNameUtils.isSmallFile('.bin'), false);
      });

      test('identifies task files as not small', () {
        expect(FileNameUtils.isSmallFile('.task'), false);
      });

      test('identifies tflite files as not small', () {
        expect(FileNameUtils.isSmallFile('.tflite'), false);
      });

      test('identifies litertlm files as not small', () {
        expect(FileNameUtils.isSmallFile('.litertlm'), false);
      });
    });

    group('getMinimumSize', () {
      test('returns 1KB for json files', () {
        expect(FileNameUtils.getMinimumSize('.json'), 1024);
      });

      test('returns 1KB for model files', () {
        expect(FileNameUtils.getMinimumSize('.model'), 1024);
      });

      test('returns 1MB for bin files', () {
        expect(FileNameUtils.getMinimumSize('.bin'), 1024 * 1024);
      });

      test('returns 1MB for task files', () {
        expect(FileNameUtils.getMinimumSize('.task'), 1024 * 1024);
      });

      test('returns 1MB for tflite files', () {
        expect(FileNameUtils.getMinimumSize('.tflite'), 1024 * 1024);
      });

      test('returns 1MB for litertlm files', () {
        expect(FileNameUtils.getMinimumSize('.litertlm'), 1024 * 1024);
      });
    });

    group('getExtension', () {
      test('extracts .task extension', () {
        expect(FileNameUtils.getExtension('model.task'), '.task');
      });

      test('extracts .bin extension', () {
        expect(FileNameUtils.getExtension('file.bin'), '.bin');
      });

      test('extracts last extension from multiple', () {
        expect(FileNameUtils.getExtension('file.bin.task'), '.task');
      });

      test('returns empty string for no extension', () {
        expect(FileNameUtils.getExtension('noextension'), '');
      });

      test('returns empty string for trailing dot', () {
        expect(FileNameUtils.getExtension('file.'), '');
      });

      test('handles complex filenames', () {
        expect(
          FileNameUtils.getExtension('gemma-3-2b-it-gpu-int8.bin'),
          '.bin',
        );
      });
    });

    group('hasValidExtension', () {
      test('returns true for .task files', () {
        expect(FileNameUtils.hasValidExtension('model.task'), true);
      });

      test('returns true for .bin files', () {
        expect(FileNameUtils.hasValidExtension('file.bin'), true);
      });

      test('returns true for .tflite files', () {
        expect(FileNameUtils.hasValidExtension('embed.tflite'), true);
      });

      test('returns true for .json files', () {
        expect(FileNameUtils.hasValidExtension('config.json'), true);
      });

      test('returns true for .model files', () {
        expect(FileNameUtils.hasValidExtension('tokenizer.model'), true);
      });

      test('returns true for .litertlm files', () {
        expect(FileNameUtils.hasValidExtension('file.litertlm'), true);
      });

      test('returns false for .txt files', () {
        expect(FileNameUtils.hasValidExtension('file.txt'), false);
      });

      test('returns false for files with no extension', () {
        expect(FileNameUtils.hasValidExtension('noextension'), false);
      });
    });

    group('isFileValid', () {
      test('returns true for large model files', () {
        expect(
          FileNameUtils.isFileValid('model.bin', 2 * 1024 * 1024),
          true,
        );
      });

      test('returns false for small model files', () {
        expect(FileNameUtils.isFileValid('model.bin', 512 * 1024), false);
      });

      test('returns true for small json files', () {
        expect(FileNameUtils.isFileValid('config.json', 2048), true);
      });

      test('returns false for tiny json files', () {
        expect(FileNameUtils.isFileValid('config.json', 512), false);
      });

      test('returns true for small tokenizer files', () {
        expect(FileNameUtils.isFileValid('tokenizer.model', 5120), true);
      });

      test('returns false for tiny tokenizer files', () {
        expect(FileNameUtils.isFileValid('tokenizer.model', 512), false);
      });

      test('handles exact minimum size for model files', () {
        expect(
          FileNameUtils.isFileValid('model.task', 1024 * 1024),
          true,
        );
      });

      test('handles exact minimum size for config files', () {
        expect(FileNameUtils.isFileValid('config.json', 1024), true);
      });

      test('handles one byte below minimum for model files', () {
        expect(
          FileNameUtils.isFileValid('model.bin', 1024 * 1024 - 1),
          false,
        );
      });

      test('handles one byte below minimum for config files', () {
        expect(FileNameUtils.isFileValid('config.json', 1023), false);
      });
    });
  });
}
