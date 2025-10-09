import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';

void main() {
  group('WebFileSystemService', () {
    late WebFileSystemService service;

    setUp(() {
      service = WebFileSystemService();
    });

    group('URL Registration', () {
      test('registerUrl stores URL correctly', () {
        // Arrange
        const filename = 'model.bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('registerUrl overwrites existing URL', () {
        // Arrange
        const filename = 'model.bin';
        const url1 = 'https://example.com/model1.bin';
        const url2 = 'https://example.com/model2.bin';

        // Act
        service.registerUrl(filename, url1);
        service.registerUrl(filename, url2);

        // Assert
        expect(service.getUrl(filename), url2);
      });

      test('getUrl returns null for unregistered filename', () {
        // Assert
        expect(service.getUrl('nonexistent.bin'), isNull);
      });

      test('registerUrl handles empty filename', () {
        // Arrange
        const filename = '';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('registerUrl handles empty URL', () {
        // Arrange
        const filename = 'model.bin';
        const url = '';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('registerUrl handles very long URLs (10000+ chars)', () {
        // Arrange
        const filename = 'model.bin';
        final url = 'https://example.com/${'a' * 10000}.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
        expect(service.getUrl(filename)!.length, 10024);
      });

      test('registerUrl handles special characters in filename', () {
        // Arrange
        const filename = 'model!@#\$%^&*().bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('registerUrl handles Unicode in filename', () {
        // Arrange
        const filename = 'модель_🤖_模型.bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('registerUrl handles Unicode in URL', () {
        // Arrange
        const filename = 'model.bin';
        const url = 'https://example.com/модель/🤖/模型.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });
    });

    group('File Existence', () {
      test('fileExists returns false for unregistered file', () async {
        // Assert
        expect(await service.fileExists('nonexistent.bin'), isFalse);
      });

      test('fileExists returns true after registration', () async {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');

        // Assert
        expect(await service.fileExists('model.bin'), isTrue);
      });

      test('fileExists returns false after deletion', () async {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');
        await service.deleteFile('model.bin');

        // Assert
        expect(await service.fileExists('model.bin'), isFalse);
      });

      test('fileExists handles empty filename', () async {
        // Assert
        expect(await service.fileExists(''), isFalse);
      });
    });

    group('File Operations', () {
      test('writeFile creates blob URL marker', () async {
        // Arrange
        const path = 'model.bin';
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);

        // Act
        await service.writeFile(path, data);

        // Assert
        expect(await service.fileExists(path), isTrue);
        expect(service.getUrl(path), 'blob:$path');
      });

      test('writeFile overwrites existing file', () async {
        // Arrange
        const path = 'model.bin';
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6, 7, 8]);

        // Act
        await service.writeFile(path, data1);
        await service.writeFile(path, data2);

        // Assert
        expect(await service.fileExists(path), isTrue);
      });

      test('writeFile handles empty data', () async {
        // Arrange
        const path = 'model.bin';
        final data = Uint8List.fromList([]);

        // Act
        await service.writeFile(path, data);

        // Assert
        expect(await service.fileExists(path), isTrue);
      });

      test('writeFile handles large data (1MB)', () async {
        // Arrange
        const path = 'model.bin';
        final data = Uint8List(1024 * 1024); // 1MB

        // Act
        await service.writeFile(path, data);

        // Assert
        expect(await service.fileExists(path), isTrue);
      });

      test('readFile throws UnsupportedError', () async {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');

        // Act & Assert
        expect(
          () => service.readFile('model.bin'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('deleteFile removes URL mapping', () async {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');

        // Act
        await service.deleteFile('model.bin');

        // Assert
        expect(service.getUrl('model.bin'), isNull);
        expect(await service.fileExists('model.bin'), isFalse);
      });

      test('deleteFile handles nonexistent file gracefully', () async {
        // Act & Assert - should not throw
        await service.deleteFile('nonexistent.bin');
      });
    });

    group('getFileSize', () {
      test('returns 0 for unregistered file', () async {
        // Assert
        expect(await service.getFileSize('nonexistent.bin'), 0);
      });

      test('returns -1 for registered file (unknown size)', () async {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');

        // Assert
        expect(await service.getFileSize('model.bin'), -1);
      });
    });

    group('getTargetPath', () {
      test('returns filename as-is', () async {
        // Arrange
        const filename = 'model.bin';

        // Act
        final path = await service.getTargetPath(filename);

        // Assert
        expect(path, filename);
      });

      test('handles empty filename', () async {
        // Act
        final path = await service.getTargetPath('');

        // Assert
        expect(path, '');
      });

      test('handles special characters', () async {
        // Arrange
        const filename = 'model!@#.bin';

        // Act
        final path = await service.getTargetPath(filename);

        // Assert
        expect(path, filename);
      });
    });

    group('getBundledResourcePath', () {
      test('returns correct asset path', () async {
        // Arrange
        const resourceName = 'gemma.task';

        // Act
        final path = await service.getBundledResourcePath(resourceName);

        // Assert
        expect(path, 'assets/models/gemma.task');
      });

      test('handles resource name with subdirectory', () async {
        // Arrange
        const resourceName = 'subdir/gemma.task';

        // Act
        final path = await service.getBundledResourcePath(resourceName);

        // Assert
        expect(path, 'assets/models/subdir/gemma.task');
      });

      test('handles empty resource name', () async {
        // Act
        final path = await service.getBundledResourcePath('');

        // Assert
        expect(path, 'assets/models/');
      });
    });

    group('registerExternalFile', () {
      test('registers external path as URL', () async {
        // Arrange
        const filename = 'model.bin';
        const externalPath = '/path/to/external/model.bin';

        // Act
        await service.registerExternalFile(filename, externalPath);

        // Assert
        expect(service.getUrl(filename), externalPath);
      });

      test('handles URL as external path', () async {
        // Arrange
        const filename = 'model.bin';
        const externalPath = 'https://example.com/model.bin';

        // Act
        await service.registerExternalFile(filename, externalPath);

        // Assert
        expect(service.getUrl(filename), externalPath);
      });
    });

    group('getAllUrls', () {
      test('returns empty map initially', () {
        // Assert
        expect(service.getAllUrls(), isEmpty);
      });

      test('returns all registered URLs', () {
        // Arrange
        service.registerUrl('model1.bin', 'https://example.com/model1.bin');
        service.registerUrl('model2.bin', 'https://example.com/model2.bin');
        service.registerUrl('model3.bin', 'https://example.com/model3.bin');

        // Act
        final urls = service.getAllUrls();

        // Assert
        expect(urls.length, 3);
        expect(urls['model1.bin'], 'https://example.com/model1.bin');
        expect(urls['model2.bin'], 'https://example.com/model2.bin');
        expect(urls['model3.bin'], 'https://example.com/model3.bin');
      });

      test('returns unmodifiable map', () {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');
        final urls = service.getAllUrls();

        // Act & Assert
        expect(
          () => urls['new.bin'] = 'https://example.com/new.bin',
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('clearAllUrls', () {
      test('clears all URL mappings', () {
        // Arrange
        service.registerUrl('model1.bin', 'https://example.com/model1.bin');
        service.registerUrl('model2.bin', 'https://example.com/model2.bin');

        // Act
        service.clearAllUrls();

        // Assert
        expect(service.getAllUrls(), isEmpty);
        expect(service.getUrl('model1.bin'), isNull);
        expect(service.getUrl('model2.bin'), isNull);
      });

      test('handles empty registry gracefully', () {
        // Act & Assert - should not throw
        service.clearAllUrls();
        expect(service.getAllUrls(), isEmpty);
      });
    });

    group('Memory Pressure Tests', () {
      test('handles 1000+ URL registrations', () {
        // Arrange & Act
        for (int i = 0; i < 1000; i++) {
          service.registerUrl('model$i.bin', 'https://example.com/model$i.bin');
        }

        // Assert
        expect(service.getAllUrls().length, 1000);
        expect(service.getUrl('model0.bin'), 'https://example.com/model0.bin');
        expect(service.getUrl('model999.bin'), 'https://example.com/model999.bin');
      });

      test('handles rapid registration and deletion', () async {
        // Act
        for (int i = 0; i < 100; i++) {
          service.registerUrl('model.bin', 'https://example.com/model$i.bin');
          await service.deleteFile('model.bin');
        }

        // Assert
        expect(service.getUrl('model.bin'), isNull);
      });
    });

    group('Concurrent Operations', () {
      test('handles concurrent registrations', () async {
        // Arrange
        final futures = <Future>[];

        // Act
        for (int i = 0; i < 100; i++) {
          futures.add(
            Future(() => service.registerUrl('model$i.bin', 'https://example.com/model$i.bin')),
          );
        }
        await Future.wait(futures);

        // Assert
        expect(service.getAllUrls().length, 100);
      });

      test('handles concurrent existence checks', () async {
        // Arrange
        service.registerUrl('model.bin', 'https://example.com/model.bin');
        final futures = <Future<bool>>[];

        // Act
        for (int i = 0; i < 100; i++) {
          futures.add(service.fileExists('model.bin'));
        }
        final results = await Future.wait(futures);

        // Assert
        expect(results.every((exists) => exists), isTrue);
      });
    });

    group('Edge Cases', () {
      test('handles duplicate registrations idempotently', () {
        // Arrange & Act
        service.registerUrl('model.bin', 'https://example.com/model.bin');
        service.registerUrl('model.bin', 'https://example.com/model.bin');
        service.registerUrl('model.bin', 'https://example.com/model.bin');

        // Assert
        expect(service.getUrl('model.bin'), 'https://example.com/model.bin');
        expect(service.getAllUrls().length, 1);
      });

      test('handles null-like strings (not actual null)', () {
        // Act & Assert
        service.registerUrl('null', 'https://example.com/null.bin');
        expect(service.getUrl('null'), 'https://example.com/null.bin');

        service.registerUrl('model.bin', 'null');
        expect(service.getUrl('model.bin'), 'null');
      });

      test('handles extremely long filenames (1000+ chars)', () {
        // Arrange
        final filename = 'model_${'a' * 1000}.bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('handles path separators in filename', () {
        // Arrange
        const filename = 'path/to/model.bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('handles whitespace in filename', () {
        // Arrange
        const filename = 'model with spaces.bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });

      test('handles newlines in filename', () {
        // Arrange
        const filename = 'model\nwith\nnewlines.bin';
        const url = 'https://example.com/model.bin';

        // Act
        service.registerUrl(filename, url);

        // Assert
        expect(service.getUrl(filename), url);
      });
    });

    group('State Management', () {
      test('maintains state across multiple operations', () async {
        // Arrange
        service.registerUrl('model1.bin', 'https://example.com/model1.bin');
        await service.writeFile('model2.bin', Uint8List.fromList([1, 2, 3]));
        await service.registerExternalFile('model3.bin', '/path/to/model3.bin');

        // Assert
        expect(await service.fileExists('model1.bin'), isTrue);
        expect(await service.fileExists('model2.bin'), isTrue);
        expect(await service.fileExists('model3.bin'), isTrue);
        expect(service.getAllUrls().length, 3);
      });

      test('clear does not affect future operations', () {
        // Arrange
        service.registerUrl('model1.bin', 'https://example.com/model1.bin');
        service.clearAllUrls();

        // Act
        service.registerUrl('model2.bin', 'https://example.com/model2.bin');

        // Assert
        expect(service.getUrl('model1.bin'), isNull);
        expect(service.getUrl('model2.bin'), 'https://example.com/model2.bin');
      });
    });
  });
}
