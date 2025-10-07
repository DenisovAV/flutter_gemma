import 'dart:async';
import 'package:background_downloader/background_downloader.dart';

/// Smart downloader with HTTP-aware retry logic
///
/// Features:
/// - HTTP-aware retry: Auth errors (401/403/404) fail after 1 attempt
/// - Transient errors (network/5xx) retry up to maxRetries times
/// - Exponential backoff strategy
/// - Completer-based waiting for completion
/// - Progress tracking with Updates.statusAndProgress
/// - Works with ANY URL (HuggingFace, Google Drive, custom servers, etc.)
/// - Supports multiple concurrent downloads
class SmartDownloader {
  static const String _downloadGroup = 'smart_downloads';

  // Global broadcast stream for FileDownloader.updates
  // This allows multiple downloads to listen simultaneously
  static Stream<TaskUpdate>? _broadcastStream;

  /// Get broadcast stream for FileDownloader updates
  /// Creates the broadcast stream once and reuses it for all downloads
  static Stream<TaskUpdate> _getUpdatesStream() {
    _broadcastStream ??= FileDownloader().updates.asBroadcastStream();
    return _broadcastStream!;
  }

  /// Downloads a file with smart retry logic and HTTP-aware error handling
  ///
  /// [url] - File URL (any server)
  /// [targetPath] - Local file path to save to
  /// [token] - Optional authorization token (e.g., HuggingFace, custom auth)
  /// [maxRetries] - Maximum number of retry attempts for transient errors (default: 10)
  /// Note: Auth errors (401/403/404) fail after 1 attempt, regardless of maxRetries.
  /// Only network errors and server errors (5xx) will be retried up to maxRetries times.
  /// Returns a stream of progress percentages (0-100)
  static Stream<int> downloadWithProgress({
    required String url,
    required String targetPath,
    String? token,
    int maxRetries = 10,
  }) {
    final progress = StreamController<int>();
    StreamSubscription? currentListener;

    _downloadWithSmartRetry(
      url: url,
      targetPath: targetPath,
      token: token,
      maxRetries: maxRetries,
      progress: progress,
      currentAttempt: 1,
      currentListener: currentListener,
      onListenerCreated: (listener) {
        currentListener = listener;
      },
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
    StreamSubscription? currentListener,
    void Function(StreamSubscription)? onListenerCreated,
  }) async {
    print('🔵 _downloadWithSmartRetry called - attempt $currentAttempt/$maxRetries');
    print('🔵 URL: $url');
    print('🔵 Target: $targetPath');

    // Declare listener outside try block so it's accessible in catch
    StreamSubscription? listener;

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
        retries: 0,  // No automatic retries - we handle ALL retries with HTTP-aware logic
        updates: Updates.statusAndProgress,  // ✅ Get both status AND progress updates
      );


      final downloader = FileDownloader();

      // Create a completer to wait for download completion
      final completer = Completer<void>();

      // Listen to broadcast stream to get full status info including HTTP code
      // Using broadcast stream allows multiple downloads and retries
      listener = _getUpdatesStream().listen((update) async {
        if (update.task.taskId != task.taskId) return;

        print('📡 Received update for task ${task.taskId}: ${update.runtimeType}');

        if (update is TaskProgressUpdate) {
          final percents = (update.progress * 100).round();
          print('📊 Progress: $percents%');
          if (!progress.isClosed) {
            progress.add(percents.clamp(0, 100));
          }
        } else if (update is TaskStatusUpdate) {
          print('📡 TaskStatusUpdate: ${update.status}, HTTP: ${update.responseStatusCode}');

          switch (update.status) {
            case TaskStatus.complete:
              if (!progress.isClosed) {
                progress.add(100);
                progress.close();
              }
              await listener?.cancel();
              completer.complete(); // ✅ Signal completion
              break;

            case TaskStatus.failed:
              print('🔴 SmartDownloader: TaskStatus.failed detected');
              print('🔴 HTTP Status Code from update: ${update.responseStatusCode}');
              print('🔴 Exception: ${update.exception}');
              print('🔴 Progress closed: ${progress.isClosed}');
              print('🔴 Current attempt: $currentAttempt');

              // Try to get HTTP code from multiple sources
              int? httpCode = update.responseStatusCode;

              // If not in responseStatusCode, check exception
              if (httpCode == null && update.exception != null) {
                if (update.exception is TaskHttpException) {
                  httpCode = (update.exception as TaskHttpException).httpResponseCode;
                  print('🔴 HTTP Status Code from TaskHttpException: $httpCode');
                }
              }

              await _handleFailedDownload(
                task: task,
                downloader: downloader,
                url: url,
                targetPath: targetPath,
                token: token,
                maxRetries: maxRetries,
                progress: progress,
                currentAttempt: currentAttempt,
                httpStatusCode: httpCode,
                currentListener: listener,
                onListenerCreated: onListenerCreated,
              );
              await listener?.cancel();
              completer.complete(); // ✅ Signal completion (even on failure)
              break;

            case TaskStatus.canceled:
              if (!progress.isClosed) {
                progress.addError('Download canceled');
                progress.close();
              }
              await listener?.cancel();
              completer.complete(); // ✅ Signal completion
              break;

            case TaskStatus.notFound:
              print('🔴 SmartDownloader: TaskStatus.notFound detected (404)');

              // 404 is a non-retryable error - handle immediately
              await _handleFailedDownload(
                task: task,
                downloader: downloader,
                url: url,
                targetPath: targetPath,
                token: token,
                maxRetries: maxRetries,
                progress: progress,
                currentAttempt: currentAttempt,
                httpStatusCode: 404,
                currentListener: listener,
                onListenerCreated: onListenerCreated,
              );
              await listener?.cancel();
              completer.complete(); // ✅ Signal completion
              break;

            default:
              break;
          }
        }
      });

      // Notify about new listener
      onListenerCreated?.call(listener);

      print('🔵 Enqueueing task ${task.taskId}...');
      final result = await downloader.enqueue(task);
      print('🔵 Enqueue result: $result');

      // ✅ Wait for download to complete
      print('🔵 Waiting for download completion...');
      await completer.future;
      print('🔵 Download completed!');

      // Ensure listener is canceled after completion
      await listener.cancel();

    } catch (e) {
      print('❌ Exception in _downloadWithSmartRetry: $e');
      print('❌ Stack trace: ${StackTrace.current}');

      // Cancel listener before retry
      await listener?.cancel();

      if (currentAttempt < maxRetries) {
        print('⚠️ Retrying after exception... attempt ${currentAttempt + 1}/$maxRetries');
        await Future.delayed(Duration(seconds: currentAttempt * 2)); // Exponential backoff
        return _downloadWithSmartRetry(
          url: url,
          targetPath: targetPath,
          token: token,
          maxRetries: maxRetries,
          progress: progress,
          currentAttempt: currentAttempt + 1,
          currentListener: currentListener,
          onListenerCreated: onListenerCreated,
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
    int? httpStatusCode,
    StreamSubscription? currentListener,
    void Function(StreamSubscription)? onListenerCreated,
  }) async {
    print('🟡 _handleFailedDownload called');
    print('🟡 httpStatusCode: $httpStatusCode');
    print('🟡 progress.isClosed: ${progress.isClosed}');

    // Check if error is retryable based on HTTP status code
    if (httpStatusCode != null) {
      print('🟢 httpStatusCode is not null: $httpStatusCode');

      // Auth errors (401, 403) and not-found (404) should NOT be retried
      if (httpStatusCode == 401) {
        print('🟢 Detected 401 - stopping immediately');
        if (!progress.isClosed) {
          print('🟢 Adding error to progress stream');
          progress.addError(
            'Authentication required (HTTP 401). '
            'Please provide a valid authentication token.'
          );
          progress.close();
          print('🟢 Progress stream closed');
        } else {
          print('⚠️ Progress already closed - cannot add error!');
        }
        return; // Stop immediately
      }

      if (httpStatusCode == 403) {
        if (!progress.isClosed) {
          progress.addError(
            'Access forbidden (HTTP 403). '
            'Your authentication token is either invalid or you do not have access to this resource. '
            'For gated models (e.g., HuggingFace), visit the model page and request access.'
          );
          progress.close();
        }
        return; // Stop immediately
      }

      if (httpStatusCode == 404) {
        if (!progress.isClosed) {
          progress.addError(
            'Model not found (HTTP 404). '
            'Please check the URL and ensure the model exists.'
          );
          progress.close();
        }
        return; // Stop immediately
      }
    }

    // First, try to resume if possible (for transient errors only)
    try {
      final canResume = await downloader.taskCanResume(task);
      if (canResume) {
        await downloader.resume(task);
        return; // Let the resume attempt continue
      }
    } catch (e) {
      // Ignore resume errors and fall back to full retry
    }

    // If resume failed or not possible, try full retry (only for transient errors)
    if (currentAttempt < maxRetries) {
      // Exponential backoff
      await Future.delayed(Duration(seconds: currentAttempt * 2));

      return _downloadWithSmartRetry(
        url: url,
        targetPath: targetPath,
        token: token,
        maxRetries: maxRetries,
        progress: progress,
        currentAttempt: currentAttempt + 1,
        currentListener: currentListener,
        onListenerCreated: onListenerCreated,
      );
    } else {
      if (!progress.isClosed) {
        progress.addError('Download failed after $maxRetries attempts. This may be due to network issues or server problems.');
        progress.close();
      }
    }
  }

  /// Checks if a URL is from HuggingFace CDN
  ///
  /// This is kept for backward compatibility but SmartDownloader works with ANY URL.
  /// You don't need to check this before using SmartDownloader.
  @Deprecated('SmartDownloader works with all URLs. No need to check anymore.')
  static bool isHuggingFaceUrl(String url) {
    return url.contains('huggingface.co') ||
           url.contains('cdn-lfs.huggingface.co') ||
           url.contains('cdn-lfs-us-1.huggingface.co') ||
           url.contains('cdn-lfs-eu-1.huggingface.co');
  }
}