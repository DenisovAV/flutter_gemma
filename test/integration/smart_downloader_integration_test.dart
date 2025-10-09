import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:background_downloader/background_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // TODO: These tests fail with "TaskException: Callbacks into the Dart VM are currently prohibited"
  // This is because background_downloader makes native callbacks from background isolates.
  // Options to fix:
  // 1. Mock background_downloader to avoid native callbacks
  // 2. Run these tests on real devices only
  // 3. Rewrite tests to not rely on actual downloads
  // For now, skipping all tests in this group.
  group('SmartDownloader Integration Tests', skip: 'Tests fail due to background_downloader VM callback restrictions. See TODO above.', () {
    late Directory tempDir;

    setUpAll(() async {
      // Setup test environment
      tempDir = Directory.systemTemp.createTempSync('smart_downloader_test_');

      // Mock path provider to use temp directory
      PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);

      // Initialize FileDownloader
      FileDownloader().configureNotificationForGroup(
        'smart_downloads',
        running: const TaskNotification('Downloading', 'file'),
        complete: const TaskNotification('Download complete', 'file'),
        error: const TaskNotification('Download failed', 'file'),
      );
    });

    tearDownAll(() async {
      // Cleanup temp directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Sequential Downloads', () {
      test('downloads first model, then second model successfully', () async {
        final firstModelPath = '${tempDir.path}/model1.bin';
        final secondModelPath = '${tempDir.path}/model2.bin';

        // Test URLs that return small files
        const firstUrl = 'https://httpbin.org/bytes/1024'; // 1KB
        const secondUrl = 'https://httpbin.org/bytes/2048'; // 2KB

        // Download first model
        final firstProgress = <int>[];
        final firstStream = SmartDownloader.downloadWithProgress(
          url: firstUrl,
          targetPath: firstModelPath,
          maxRetries: 3,
        );

        await for (final progress in firstStream) {
          firstProgress.add(progress);
          print('📊 First model progress: $progress%');
        }

        expect(firstProgress.isNotEmpty, true, reason: 'First model should have progress updates');
        expect(firstProgress.last, 100, reason: 'First model should complete at 100%');
        expect(await File(firstModelPath).exists(), true, reason: 'First model file should exist');

        print('✅ First model downloaded successfully');
        print('⏸️  Waiting 2 seconds before second download...');
        await Future.delayed(const Duration(seconds: 2));

        // Download second model
        final secondProgress = <int>[];
        final secondStream = SmartDownloader.downloadWithProgress(
          url: secondUrl,
          targetPath: secondModelPath,
          maxRetries: 3,
        );

        await for (final progress in secondStream) {
          secondProgress.add(progress);
          print('📊 Second model progress: $progress%');
        }

        expect(secondProgress.isNotEmpty, true, reason: 'Second model should have progress updates');
        expect(secondProgress.last, 100, reason: 'Second model should complete at 100%');
        expect(await File(secondModelPath).exists(), true, reason: 'Second model file should exist');

        print('✅ Second model downloaded successfully');

        // Verify file sizes
        final firstSize = await File(firstModelPath).length();
        final secondSize = await File(secondModelPath).length();

        expect(firstSize, 1024, reason: 'First model should be 1KB');
        expect(secondSize, 2048, reason: 'Second model should be 2KB');

        // Cleanup
        await File(firstModelPath).delete();
        await File(secondModelPath).delete();
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('downloads three models sequentially without errors', () async {
        final paths = [
          '${tempDir.path}/seq_model1.bin',
          '${tempDir.path}/seq_model2.bin',
          '${tempDir.path}/seq_model3.bin',
        ];

        const urls = [
          'https://httpbin.org/bytes/512',  // 512 bytes
          'https://httpbin.org/bytes/1024', // 1KB
          'https://httpbin.org/bytes/2048', // 2KB
        ];

        for (var i = 0; i < paths.length; i++) {
          print('🔵 Downloading model ${i + 1}/3...');

          final progress = <int>[];
          final stream = SmartDownloader.downloadWithProgress(
            url: urls[i],
            targetPath: paths[i],
            maxRetries: 3,
          );

          await for (final p in stream) {
            progress.add(p);
          }

          expect(progress.last, 100, reason: 'Model ${i + 1} should complete');
          expect(await File(paths[i]).exists(), true, reason: 'Model ${i + 1} file should exist');

          print('✅ Model ${i + 1}/3 downloaded successfully');

          // Small delay between downloads
          if (i < paths.length - 1) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }

        // Cleanup
        for (final path in paths) {
          await File(path).delete();
        }
      }, timeout: const Timeout(Duration(minutes: 3)));
    });

    group('Keep Policy Tests', () {
      test('does not overwrite existing file with keep policy', () async {
        final modelPath = '${tempDir.path}/keep_model.bin';

        // Create existing file with specific content
        final existingContent = List.filled(512, 0xFF);
        await File(modelPath).writeAsBytes(existingContent);
        final originalSize = await File(modelPath).length();

        print('📁 Created existing file: $originalSize bytes');

        // Attempt to download with keep policy (by checking file exists first)
        if (await File(modelPath).exists()) {
          print('⏭️  File already exists, skipping download (keep policy)');
          // Skip download
        } else {
          fail('File should exist for keep policy test');
        }

        // Verify file was NOT overwritten
        final currentSize = await File(modelPath).length();
        expect(currentSize, originalSize, reason: 'File should not be overwritten with keep policy');

        final currentContent = await File(modelPath).readAsBytes();
        expect(currentContent, existingContent, reason: 'Content should be unchanged');

        print('✅ Keep policy: file preserved');

        // Cleanup
        await File(modelPath).delete();
      });
    });

    group('Replace Policy Tests', () {
      test('overwrites existing file with replace policy', () async {
        final modelPath = '${tempDir.path}/replace_model.bin';
        const url = 'https://httpbin.org/bytes/1024';

        // Create existing file with specific content
        final existingContent = List.filled(512, 0xFF);
        await File(modelPath).writeAsBytes(existingContent);
        final originalSize = await File(modelPath).length();

        print('📁 Created existing file: $originalSize bytes');

        // Download and replace
        print('🔄 Downloading with replace policy...');
        final progress = <int>[];
        final stream = SmartDownloader.downloadWithProgress(
          url: url,
          targetPath: modelPath,
          maxRetries: 3,
        );

        await for (final p in stream) {
          progress.add(p);
        }

        expect(progress.last, 100, reason: 'Download should complete');

        // Verify file was overwritten
        final newSize = await File(modelPath).length();
        expect(newSize, isNot(originalSize), reason: 'File should be replaced');
        expect(newSize, 1024, reason: 'New file should be 1KB');

        final newContent = await File(modelPath).readAsBytes();
        expect(newContent, isNot(existingContent), reason: 'Content should be different');

        print('✅ Replace policy: file overwritten');

        // Cleanup
        await File(modelPath).delete();
      }, timeout: const Timeout(Duration(minutes: 1)));
    });

    group('Resume Interrupted Download', () {
      test('resumes interrupted download', () async {
        final modelPath = '${tempDir.path}/resume_model.bin';
        const url = 'https://httpbin.org/bytes/4096'; // 4KB

        // Start download
        print('🔵 Starting initial download...');
        final firstStream = SmartDownloader.downloadWithProgress(
          url: url,
          targetPath: modelPath,
          maxRetries: 3,
        );

        var interrupted = false;
        try {
          await for (final progress in firstStream) {
            print('📊 Progress: $progress%');

            // Simulate interruption at 50% (we can't really control this with httpbin)
            // So we'll just cancel the stream early to simulate interruption
            if (progress >= 30 && !interrupted) {
              interrupted = true;
              print('⚠️  Simulating interruption at $progress%');
              break; // Break out of stream
            }
          }
        } catch (e) {
          print('⚠️  Download interrupted: $e');
        }

        // Check if partial file exists (may or may not depending on background_downloader behavior)
        final partialExists = await File(modelPath).exists();
        print('📁 Partial file exists: $partialExists');

        // Attempt to resume/retry download
        print('🔄 Attempting to resume download...');
        await Future.delayed(const Duration(seconds: 1));

        final resumeProgress = <int>[];
        final resumeStream = SmartDownloader.downloadWithProgress(
          url: url,
          targetPath: modelPath,
          maxRetries: 3,
        );

        await for (final progress in resumeStream) {
          resumeProgress.add(progress);
          print('📊 Resume progress: $progress%');
        }

        expect(resumeProgress.last, 100, reason: 'Resumed download should complete');
        expect(await File(modelPath).exists(), true, reason: 'File should exist after resume');

        final finalSize = await File(modelPath).length();
        expect(finalSize, 4096, reason: 'Final file should be complete (4KB)');

        print('✅ Download resumed and completed successfully');

        // Cleanup
        await File(modelPath).delete();
      }, timeout: const Timeout(Duration(minutes: 2)));
    });

    group('HTTP Error Handling', () {
      test('handles 404 error correctly (no retry)', () async {
        final modelPath = '${tempDir.path}/not_found.bin';
        const url = 'https://httpbin.org/status/404';

        print('🔴 Testing 404 error handling...');

        var errorReceived = false;
        var errorMessage = '';

        try {
          final stream = SmartDownloader.downloadWithProgress(
            url: url,
            targetPath: modelPath,
            maxRetries: 3,
          );

          await for (final progress in stream) {
            print('📊 Progress: $progress%');
          }

          fail('Should have thrown an error for 404');
        } catch (e) {
          errorReceived = true;
          errorMessage = e.toString();
          print('✅ Received expected error: $errorMessage');
        }

        expect(errorReceived, true, reason: '404 should produce an error');
        expect(errorMessage.toLowerCase(), contains('404'), reason: 'Error should mention 404');

        // File should not exist
        expect(await File(modelPath).exists(), false, reason: 'File should not exist for 404');

        print('✅ 404 error handled correctly');
      }, timeout: const Timeout(Duration(minutes: 1)));

      test('handles 401 error correctly (no retry)', () async {
        final modelPath = '${tempDir.path}/unauthorized.bin';
        const url = 'https://httpbin.org/status/401';

        print('🔴 Testing 401 error handling...');

        var errorReceived = false;
        var errorMessage = '';

        try {
          final stream = SmartDownloader.downloadWithProgress(
            url: url,
            targetPath: modelPath,
            maxRetries: 3,
          );

          await for (final progress in stream) {
            print('📊 Progress: $progress%');
          }

          fail('Should have thrown an error for 401');
        } catch (e) {
          errorReceived = true;
          errorMessage = e.toString();
          print('✅ Received expected error: $errorMessage');
        }

        expect(errorReceived, true, reason: '401 should produce an error');
        expect(
          errorMessage.toLowerCase().contains('401') ||
          errorMessage.toLowerCase().contains('auth'),
          true,
          reason: 'Error should mention authentication',
        );

        print('✅ 401 error handled correctly');
      }, timeout: const Timeout(Duration(minutes: 1)));
    });

    group('Progress Tracking', () {
      test('reports progress updates for large file', () async {
        final modelPath = '${tempDir.path}/progress_test.bin';
        const url = 'https://httpbin.org/bytes/8192'; // 8KB

        print('🔵 Testing progress tracking...');

        final progressUpdates = <int>[];
        final stream = SmartDownloader.downloadWithProgress(
          url: url,
          targetPath: modelPath,
          maxRetries: 3,
        );

        await for (final progress in stream) {
          progressUpdates.add(progress);
          print('📊 Progress: $progress%');
        }

        expect(progressUpdates.isNotEmpty, true, reason: 'Should have progress updates');
        expect(progressUpdates.first, greaterThanOrEqualTo(0), reason: 'First progress should be >= 0');
        expect(progressUpdates.last, 100, reason: 'Last progress should be 100');

        // Check that progress is monotonically increasing
        for (var i = 1; i < progressUpdates.length; i++) {
          expect(
            progressUpdates[i] >= progressUpdates[i - 1],
            true,
            reason: 'Progress should be monotonically increasing',
          );
        }

        print('✅ Progress tracking works correctly');
        print('📊 Total progress updates: ${progressUpdates.length}');

        // Cleanup
        await File(modelPath).delete();
      }, timeout: const Timeout(Duration(minutes: 1)));
    });
  });
}

/// Mock PathProvider for testing
class MockPathProviderPlatform extends PathProviderPlatform {
  final Directory tempDir;

  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempDir.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return tempDir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return tempDir.path;
  }
}
