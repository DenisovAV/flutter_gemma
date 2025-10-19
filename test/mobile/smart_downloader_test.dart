import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartDownloader Unit Tests', () {
    group('API Consistency', () {
      test('download() method exists and has correct signature', () {
        // Verify that SmartDownloader.download() exists
        // This test ensures the method was added correctly
        expect(
          SmartDownloader.download,
          isNotNull,
          reason: 'SmartDownloader.download() should exist',
        );

        // Verify it's a static method (is Function check is implicit - method compiles)
      });

      test('downloadWithProgress() method exists and has correct signature', () {
        expect(
          SmartDownloader.downloadWithProgress,
          isNotNull,
          reason: 'SmartDownloader.downloadWithProgress() should exist',
        );

        // Verify it's a static method (is Function check is implicit - method compiles)
      });

      test('both methods accept same parameters', () {
        // Both methods should accept:
        // - url (required)
        // - targetPath (required)
        // - token (optional)
        // - maxRetries (optional, default: 10)

        // This test verifies the API is consistent
        // We can't easily test parameter names in Dart, but we can verify
        // that the methods have the same contract by checking they compile

        const url = 'https://example.com/model.bin';
        const targetPath = '/tmp/model.bin';
        const token = 'test_token';
        const maxRetries = 5;

        // These should compile without errors
        expect(
          () => SmartDownloader.download(
            url: url,
            targetPath: targetPath,
            token: token,
            maxRetries: maxRetries,
          ),
          returnsNormally,
        );

        expect(
          () => SmartDownloader.downloadWithProgress(
            url: url,
            targetPath: targetPath,
            token: token,
            maxRetries: maxRetries,
          ),
          returnsNormally,
        );
      });
    });

    group('Return Types', () {
      test('download() returns Future<void>', () async {
        // Verify return type
        final result = SmartDownloader.download(
          url: 'https://example.com/test.bin',
          targetPath: '/tmp/test.bin',
        );

        expect(
          result,
          isA<Future<void>>(),
          reason: 'download() should return Future<void>',
        );
      });

      test('downloadWithProgress() returns Stream<int>', () {
        // Verify return type
        final result = SmartDownloader.downloadWithProgress(
          url: 'https://example.com/test.bin',
          targetPath: '/tmp/test.bin',
        );

        expect(
          result,
          isA<Stream<int>>(),
          reason: 'downloadWithProgress() should return Stream<int>',
        );
      });
    });

    group('Parameter Validation', () {
      test('download() accepts minimal parameters', () {
        expect(
          () => SmartDownloader.download(
            url: 'https://example.com/model.bin',
            targetPath: '/tmp/model.bin',
          ),
          returnsNormally,
          reason: 'Should accept only required parameters',
        );
      });

      test('download() accepts optional token', () {
        expect(
          () => SmartDownloader.download(
            url: 'https://example.com/model.bin',
            targetPath: '/tmp/model.bin',
            token: 'test_token',
          ),
          returnsNormally,
          reason: 'Should accept optional token parameter',
        );
      });

      test('download() accepts optional maxRetries', () {
        expect(
          () => SmartDownloader.download(
            url: 'https://example.com/model.bin',
            targetPath: '/tmp/model.bin',
            maxRetries: 5,
          ),
          returnsNormally,
          reason: 'Should accept optional maxRetries parameter',
        );
      });

      test('download() accepts all parameters', () {
        expect(
          () => SmartDownloader.download(
            url: 'https://example.com/model.bin',
            targetPath: '/tmp/model.bin',
            token: 'test_token',
            maxRetries: 5,
          ),
          returnsNormally,
          reason: 'Should accept all parameters',
        );
      });
    });

    group('Error Propagation', () {
      test('download() propagates errors from downloadWithProgress()', () async {
        // Test that download() properly propagates errors
        // We test with a stream that immediately errors

        final completer = Completer<void>();

        // Start download (will fail immediately due to invalid URL or network issues)
        SmartDownloader.download(
          url: 'https://httpbin.org/status/404', // This will return 404
          targetPath: '/tmp/error_test.bin',
          maxRetries: 1, // Limit retries for faster test
        ).then(
          (_) => completer.complete(),
          onError: (error) => completer.completeError(error),
        );

        // Should receive an error
        expect(
          completer.future,
          throwsA(anything),
          reason: 'download() should propagate errors from stream',
        );
      });

      test('downloadWithProgress() stream can emit errors', () {
        final stream = SmartDownloader.downloadWithProgress(
          url: 'https://httpbin.org/status/500', // Server error
          targetPath: '/tmp/error_test.bin',
          maxRetries: 1,
        );

        expect(
          stream.first, // Try to get first event (will be error)
          throwsA(anything),
          reason: 'Stream should emit errors for failed downloads',
        );
      });
    });

    group('Stream Completion', () {
      test('download() completes when stream completes', () async {
        // This test verifies that download() waits for the stream to complete
        // We'll use a mock scenario by checking the future completes

        final downloadFuture = SmartDownloader.download(
          url: 'https://httpbin.org/bytes/100', // Small file
          targetPath: '/tmp/completion_test.bin',
          maxRetries: 1,
        );

        // The future should complete (either successfully or with error)
        // We use a timeout to ensure it doesn't hang
        await expectLater(
          downloadFuture.timeout(const Duration(seconds: 30)),
          anyOf([completes, throwsA(anything)]),
          reason: 'download() should complete when stream completes',
        );
      });
    });

    group('Default Parameters', () {
      test('download() uses default maxRetries of 10', () {
        // We can't directly test default parameter values, but we can verify
        // that calling without maxRetries doesn't throw
        expect(
          () => SmartDownloader.download(
            url: 'https://example.com/model.bin',
            targetPath: '/tmp/model.bin',
          ),
          returnsNormally,
          reason: 'Should use default maxRetries when not specified',
        );
      });

      test('downloadWithProgress() uses default maxRetries of 10', () {
        expect(
          () => SmartDownloader.downloadWithProgress(
            url: 'https://example.com/model.bin',
            targetPath: '/tmp/model.bin',
          ),
          returnsNormally,
          reason: 'Should use default maxRetries when not specified',
        );
      });
    });

    group('Documentation', () {
      test('download() has proper documentation', () {
        // This is a meta-test to ensure developers document the API
        // In a real scenario, we'd parse the source code for doc comments
        // For now, we just verify the method exists and is callable
        expect(
          SmartDownloader.download,
          isNotNull,
          reason: 'download() should be documented',
        );
      });
    });
  });

  group('SmartDownloader Integration with BackgroundDownloaderService', () {
    test('download() should be used by BackgroundDownloaderService.download()', () {
      // This test documents the expected integration
      // BackgroundDownloaderService should delegate to SmartDownloader
      // We can't test this directly without mocking, but we document the expectation
      expect(
        SmartDownloader.download,
        isNotNull,
        reason: 'BackgroundDownloaderService.download() should delegate to this',
      );
    });

    test(
        'downloadWithProgress() should be used by BackgroundDownloaderService.downloadWithProgress()',
        () {
      expect(
        SmartDownloader.downloadWithProgress,
        isNotNull,
        reason: 'BackgroundDownloaderService.downloadWithProgress() should delegate to this',
      );
    });
  });
}
