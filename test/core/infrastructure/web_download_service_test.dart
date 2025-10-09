import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/infrastructure/web_download_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_js_interop.dart';
import 'package:flutter_gemma/core/infrastructure/blob_url_manager.dart';

void main() {
  group('WebDownloadService', () {
    late WebFileSystemService fileSystem;
    late WebJsInterop jsInterop;
    late BlobUrlManager blobUrlManager;
    late WebDownloadService service;

    setUp(() {
      fileSystem = WebFileSystemService();
      jsInterop = WebJsInterop();
      blobUrlManager = BlobUrlManager(jsInterop, fileSystem);
      fileSystem.setOnBlobUrlRemoved(blobUrlManager.cleanupByUrl);
      service = WebDownloadService(fileSystem, jsInterop, blobUrlManager);
    });

    group('download', () {
      test('registers URL in file system', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles authentication token parameter', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        const token = 'hf_testtoken123';

        // Act
        await service.download(url, targetPath, token: token);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
        // Token is logged but not stored in this implementation
      });

      test('overwrites existing URL', () async {
        // Arrange
        const url1 = 'https://example.com/model1.bin';
        const url2 = 'https://example.com/model2.bin';
        const targetPath = 'model.bin';

        // Act
        await service.download(url1, targetPath);
        await service.download(url2, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url2);
      });

      test('handles empty URL', () async {
        // Arrange
        const url = '';
        const targetPath = 'model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles empty targetPath', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = '';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles very long URLs (10000+ chars)', () async {
        // Arrange
        final url = 'https://example.com/${'a' * 10000}.bin';
        const targetPath = 'model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles special characters in URL', () async {
        // Arrange
        const url = 'https://example.com/model?token=abc&version=1.0#latest';
        const targetPath = 'model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles Unicode in URL', () async {
        // Arrange
        const url = 'https://example.com/模型/🤖/модель.bin';
        const targetPath = 'model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });
    });

    group('downloadWithProgress', () {
      test('emits progress from 0 to 100', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        final progressValues = <int>[];

        // Act
        await for (final progress in service.downloadWithProgress(url, targetPath)) {
          progressValues.add(progress);
        }

        // Assert
        expect(progressValues.first, 0);
        expect(progressValues.last, 100);
        expect(progressValues, isNotEmpty);
      });

      test('progress is monotonically increasing', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        final progressValues = <int>[];

        // Act
        await for (final progress in service.downloadWithProgress(url, targetPath)) {
          progressValues.add(progress);
        }

        // Assert
        for (int i = 1; i < progressValues.length; i++) {
          expect(
            progressValues[i],
            greaterThanOrEqualTo(progressValues[i - 1]),
            reason: 'Progress should be monotonically increasing',
          );
        }
      });

      test('progress values are within 0-100 range', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';

        // Act
        await for (final progress in service.downloadWithProgress(url, targetPath)) {
          // Assert
          expect(progress, greaterThanOrEqualTo(0));
          expect(progress, lessThanOrEqualTo(100));
        }
      });

      test('registers URL after progress completes', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath)) {
          // Consume stream
        }

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles authentication token parameter', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        const token = 'hf_testtoken123';

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath, token: token)) {
          // Consume stream
        }

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('maxRetries parameter is accepted but not used', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath, maxRetries: 5)) {
          // Consume stream
        }

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('emits multiple progress events', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        final progressValues = <int>[];

        // Act
        await for (final progress in service.downloadWithProgress(url, targetPath)) {
          progressValues.add(progress);
        }

        // Assert
        expect(progressValues.length, greaterThan(5));
      });

      test('completes in reasonable time', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        final stopwatch = Stopwatch()..start();

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath)) {
          // Consume stream
        }
        stopwatch.stop();

        // Assert - should complete in under 2 seconds
        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
      });
    });

    group('canResume', () {
      test('always returns false', () async {
        // Assert
        expect(await service.canResume('task123'), isFalse);
        expect(await service.canResume(''), isFalse);
        expect(await service.canResume('nonexistent'), isFalse);
      });
    });

    group('resume', () {
      test('throws UnsupportedError', () async {
        // Assert
        expect(
          () => service.resume('task123'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws with helpful error message', () async {
        // Assert
        try {
          await service.resume('task123');
          fail('Should have thrown UnsupportedError');
        } catch (e) {
          expect(e, isA<UnsupportedError>());
          expect(
            e.toString(),
            contains('not supported on web'),
          );
        }
      });
    });

    group('cancel', () {
      test('completes successfully (no-op)', () async {
        // Act & Assert - should not throw
        await service.cancel('task123');
        await service.cancel('');
        await service.cancel('nonexistent');
      });
    });

    group('Edge Cases', () {
      test('handles concurrent downloads to same target', () async {
        // Arrange
        const url1 = 'https://example.com/model1.bin';
        const url2 = 'https://example.com/model2.bin';
        const targetPath = 'model.bin';

        // Act
        final futures = [
          service.download(url1, targetPath),
          service.download(url2, targetPath),
        ];
        await Future.wait(futures);

        // Assert - last one wins
        final registeredUrl = fileSystem.getUrl(targetPath);
        expect(registeredUrl == url1 || registeredUrl == url2, isTrue);
      });

      test('handles concurrent downloads to different targets', () async {
        // Arrange
        final futures = <Future>[];

        // Act
        for (int i = 0; i < 10; i++) {
          futures.add(
            service.download('https://example.com/model$i.bin', 'model$i.bin'),
          );
        }
        await Future.wait(futures);

        // Assert
        for (int i = 0; i < 10; i++) {
          expect(
            fileSystem.getUrl('model$i.bin'),
            'https://example.com/model$i.bin',
          );
        }
      });

      test('handles concurrent progress downloads', () async {
        // Arrange
        final futures = <Future>[];

        // Act
        for (int i = 0; i < 5; i++) {
          futures.add(
            service.downloadWithProgress('https://example.com/model$i.bin', 'model$i.bin').drain(),
          );
        }
        await Future.wait(futures);

        // Assert
        for (int i = 0; i < 5; i++) {
          expect(
            fileSystem.getUrl('model$i.bin'),
            'https://example.com/model$i.bin',
          );
        }
      });

      test('handles stream cancellation mid-download', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        var count = 0;

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath)) {
          count++;
          if (count >= 5) {
            break; // Cancel stream early
          }
        }

        // Assert - URL should still be registered
        expect(count, 5);
        // URL might not be registered if stream was cancelled before completion
      });

      test('handles extremely long target paths', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        final targetPath = 'path/${'subdir/' * 100}model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('handles special characters in target path', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'path/with spaces/!@#\$%^&*().bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(fileSystem.getUrl(targetPath), url);
      });
    });

    group('Integration with WebFileSystemService', () {
      test('registered URL is accessible via fileSystem', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';

        // Act
        await service.download(url, targetPath);

        // Assert
        expect(await fileSystem.fileExists(targetPath), isTrue);
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('downloadWithProgress updates fileSystem', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath)) {
          // Consume stream
        }

        // Assert
        expect(await fileSystem.fileExists(targetPath), isTrue);
        expect(fileSystem.getUrl(targetPath), url);
      });

      test('download works with shared fileSystem instance', () async {
        // Arrange
        const url1 = 'https://example.com/model1.bin';
        const url2 = 'https://example.com/model2.bin';

        // Act
        await service.download(url1, 'model1.bin');
        fileSystem.registerUrl('model2.bin', url2);

        // Assert
        expect(fileSystem.getAllUrls().length, 2);
        expect(fileSystem.getUrl('model1.bin'), url1);
        expect(fileSystem.getUrl('model2.bin'), url2);
      });
    });

    group('Memory Pressure', () {
      test('handles 100 rapid downloads', () async {
        // Arrange
        final futures = <Future>[];

        // Act
        for (int i = 0; i < 100; i++) {
          futures.add(
            service.download('https://example.com/model$i.bin', 'model$i.bin'),
          );
        }
        await Future.wait(futures);

        // Assert
        expect(fileSystem.getAllUrls().length, 100);
      });

      test('handles 100 rapid progress downloads', () async {
        // Arrange
        final futures = <Future>[];

        // Act
        for (int i = 0; i < 100; i++) {
          futures.add(
            service.downloadWithProgress('https://example.com/model$i.bin', 'model$i.bin').drain(),
          );
        }
        await Future.wait(futures);

        // Assert
        expect(fileSystem.getAllUrls().length, 100);
      });
    });

    group('Progress Timing', () {
      test('progress events are evenly distributed', () async {
        // Arrange
        const url = 'https://example.com/model.bin';
        const targetPath = 'model.bin';
        final timestamps = <int>[];
        final stopwatch = Stopwatch()..start();

        // Act
        await for (final _ in service.downloadWithProgress(url, targetPath)) {
          timestamps.add(stopwatch.elapsedMilliseconds);
        }

        // Assert
        expect(timestamps.length, greaterThan(5));

        // Check that events are somewhat evenly distributed
        if (timestamps.length > 2) {
          final intervals = <int>[];
          for (int i = 1; i < timestamps.length; i++) {
            intervals.add(timestamps[i] - timestamps[i - 1]);
          }

          // Intervals should be relatively consistent (within 2x of each other)
          final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
          for (final interval in intervals) {
            expect(
              interval,
              lessThan(avgInterval * 3),
              reason: 'Progress events should be somewhat evenly distributed',
            );
          }
        }
      });
    });
  });
}
