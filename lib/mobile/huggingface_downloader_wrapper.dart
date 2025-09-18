import 'dart:async';
import 'package:background_downloader/background_downloader.dart';

/// Wrapper around background_downloader to handle HuggingFace ETag issues
///
/// HuggingFace CDN (Cloudfront) can return different ETags for the same file
/// across different servers/regions, causing resume failures.
/// This wrapper implements smart retry logic to work around ETag mismatches.
class HuggingFaceDownloader {
  static const String _downloadGroup = 'huggingface_downloads';

  /// Downloads a file from HuggingFace with smart ETag handling
  ///
  /// [url] - HuggingFace file URL
  /// [targetPath] - Local file path to save to
  /// [token] - HuggingFace authorization token
  /// [maxRetries] - Maximum number of download attempts (default: 10)
  /// [onProgress] - Progress callback (0-100)
  static Stream<int> downloadWithProgress({
    required String url,
    required String targetPath,
    String? token,
    int maxRetries = 10,
  }) {
    final progress = StreamController<int>();

    _downloadWithSmartRetry(
      url: url,
      targetPath: targetPath,
      token: token,
      maxRetries: maxRetries,
      progress: progress,
      currentAttempt: 1,
    );

    return progress.stream;
  }

  static Future<void> _downloadWithSmartRetry({
    required String url,
    required String targetPath,
    String? token,
    required int maxRetries,
    required StreamController<int> progress,
    required int currentAttempt,
  }) async {
    try {
      final (baseDirectory, directory, filename) = await Task.split(filePath: targetPath);

      final task = DownloadTask(
        url: url,
        group: _downloadGroup,
        headers: token != null ? {
          'Authorization': 'Bearer $token',
          'Connection': 'keep-alive',
          // Attempt to work around CDN ETag issues
          'Cache-Control': 'no-cache, no-store',
          'Pragma': 'no-cache',
        } : {
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache, no-store',
          'Pragma': 'no-cache',
        },
        baseDirectory: baseDirectory,
        directory: directory,
        filename: filename,
        requiresWiFi: false,
        allowPause: true,  // Try resume first
        priority: 10,
        retries: 1,  // Handle retries manually for better control
      );


      final downloader = FileDownloader();

      await downloader.download(
        task,
        onProgress: (portion) {
          final percents = (portion * 100).round();
          if (!progress.isClosed) {
            progress.add(percents.clamp(0, 100));
          }
        },
        onStatus: (status) async {

          switch (status) {
            case TaskStatus.complete:
              if (!progress.isClosed) {
                progress.add(100);
                progress.close();
              }
              break;

            case TaskStatus.failed:
              await _handleFailedDownload(
                task: task,
                downloader: downloader,
                url: url,
                targetPath: targetPath,
                token: token,
                maxRetries: maxRetries,
                progress: progress,
                currentAttempt: currentAttempt,
              );
              break;

            case TaskStatus.canceled:
              if (!progress.isClosed) {
                progress.addError('Download canceled');
                progress.close();
              }
              break;

            case TaskStatus.paused:
              // Don't close stream, let it resume
              break;

            case TaskStatus.running:
              break;

            default:
              break;
          }
        },
      );

    } catch (e) {
      if (currentAttempt < maxRetries) {
        await Future.delayed(Duration(seconds: currentAttempt * 2)); // Exponential backoff
        return _downloadWithSmartRetry(
          url: url,
          targetPath: targetPath,
          token: token,
          maxRetries: maxRetries,
          progress: progress,
          currentAttempt: currentAttempt + 1,
        );
      } else {
        if (!progress.isClosed) {
          progress.addError('Download failed after $maxRetries attempts: $e');
          progress.close();
        }
      }
    }
  }

  static Future<void> _handleFailedDownload({
    required DownloadTask task,
    required FileDownloader downloader,
    required String url,
    required String targetPath,
    String? token,
    required int maxRetries,
    required StreamController<int> progress,
    required int currentAttempt,
  }) async {

    // First, try to resume if possible
    try {
      final canResume = await downloader.taskCanResume(task);
      if (canResume) {
        await downloader.resume(task);
        return; // Let the resume attempt continue
      }
    } catch (e) {
      // Ignore resume errors and fall back to full retry
    }

    // If resume failed or not possible, try full retry
    if (currentAttempt < maxRetries) {
      // Small delay before retry
      await Future.delayed(Duration(seconds: currentAttempt * 2));

      return _downloadWithSmartRetry(
        url: url,
        targetPath: targetPath,
        token: token,
        maxRetries: maxRetries,
        progress: progress,
        currentAttempt: currentAttempt + 1,
      );
    } else {
      if (!progress.isClosed) {
        progress.addError('Download failed after $maxRetries attempts. This may be due to ETag issues with HuggingFace CDN.');
        progress.close();
      }
    }
  }

  /// Checks if a URL is from HuggingFace CDN
  static bool isHuggingFaceUrl(String url) {
    return url.contains('huggingface.co') ||
           url.contains('cdn-lfs.huggingface.co') ||
           url.contains('cdn-lfs-us-1.huggingface.co') ||
           url.contains('cdn-lfs-eu-1.huggingface.co');
  }
}