import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_gemma/core/domain/download_error.dart';
import 'package:flutter_gemma/core/domain/download_exception.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';

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
  /// [cancelToken] - Optional token for cancellation
  /// Note: Auth errors (401/403/404) fail after 1 attempt, regardless of maxRetries.
  /// Only network errors and server errors (5xx) will be retried up to maxRetries times.
  ///
  /// This method waits for completion without progress tracking.
  /// For progress tracking, use [downloadWithProgress] instead.
  ///
  /// Throws [DownloadCancelledException] if cancelled via cancelToken.
  static Future<void> download({
    required String url,
    required String targetPath,
    String? token,
    int maxRetries = 10,
    CancelToken? cancelToken,
  }) async {
    final completer = Completer<void>();

    // Use downloadWithProgress but just wait for completion
    downloadWithProgress(
      url: url,
      targetPath: targetPath,
      token: token,
      maxRetries: maxRetries,
      cancelToken: cancelToken,
    ).listen(
      (_) {}, // Ignore progress updates
      onError: (error) => completer.completeError(error),
      onDone: () => completer.complete(),
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Downloads a file with smart retry logic and HTTP-aware error handling
  ///
  /// [url] - File URL (any server)
  /// [targetPath] - Local file path to save to
  /// [token] - Optional authorization token (e.g., HuggingFace, custom auth)
  /// [maxRetries] - Maximum number of retry attempts for transient errors (default: 10)
  /// [cancelToken] - Optional token for cancellation
  /// Note: Auth errors (401/403/404) fail after 1 attempt, regardless of maxRetries.
  /// Only network errors and server errors (5xx) will be retried up to maxRetries times.
  /// Returns a stream of progress percentages (0-100)
  ///
  /// The stream will emit [DownloadCancelledException] if cancelled via cancelToken.
  static Stream<int> downloadWithProgress({
    required String url,
    required String targetPath,
    String? token,
    int maxRetries = 10,
    CancelToken? cancelToken,
  }) {
    final progress = StreamController<int>();
    StreamSubscription? currentListener;
    StreamSubscription? cancellationListener;
    String? currentTaskId; // ← ADD: Store task ID for cancellation

    // Listen for cancellation
    if (cancelToken != null) {
      cancellationListener = cancelToken.whenCancelled.asStream().listen((_) async {
        debugPrint('🚫 Cancellation requested');

        // Cancel the actual download task
        if (currentTaskId != null) {
          debugPrint('🚫 Cancelling task: $currentTaskId');
          try {
            await FileDownloader()
                .cancelTaskWithId(currentTaskId!); // ← ADD: Actually cancel the task
          } catch (e) {
            debugPrint('⚠️ Failed to cancel task: $e');
          }
        }

        if (!progress.isClosed) {
          progress.addError(
            DownloadCancelledException(
              cancelToken.cancelReason ?? 'Download cancelled',
              StackTrace.current,
            ),
          );
          progress.close();
        }
        currentListener?.cancel();
        cancellationListener?.cancel();
      });
    }

    _downloadWithSmartRetry(
      url: url,
      targetPath: targetPath,
      token: token,
      maxRetries: maxRetries,
      progress: progress,
      currentAttempt: 1,
      currentListener: currentListener,
      cancelToken: cancelToken,
      onListenerCreated: (listener) {
        currentListener = listener;
      },
      onTaskCreated: (taskId) {
        currentTaskId = taskId; // ← ADD: Store task ID when created
      },
    ).whenComplete(() {
      // Clean up cancellation listener when download completes
      cancellationListener?.cancel();
    });

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
    CancelToken? cancelToken,
    void Function(StreamSubscription)? onListenerCreated,
    void Function(String taskId)? onTaskCreated, // ← ADD: Callback for task ID
  }) async {
    // Check cancellation before starting
    try {
      cancelToken?.throwIfCancelled();
    } catch (e) {
      if (!progress.isClosed) {
        progress.addError(e);
        progress.close();
      }
      return;
    }

    debugPrint('🔵 _downloadWithSmartRetry called - attempt $currentAttempt/$maxRetries');
    debugPrint('🔵 URL: $url');
    debugPrint('🔵 Target: $targetPath');

    // Declare listener outside try block so it's accessible in catch
    StreamSubscription? listener;

    try {
      final (baseDirectory, directory, filename) = await Task.split(filePath: targetPath);

      final task = DownloadTask(
        url: url,
        group: _downloadGroup,
        headers: token != null
            ? {
                'Authorization': 'Bearer $token',
                'Connection': 'keep-alive',
                // Attempt to work around CDN ETag issues
                'Cache-Control': 'no-cache, no-store',
                'Pragma': 'no-cache',
              }
            : {
                'Connection': 'keep-alive',
                'Cache-Control': 'no-cache, no-store',
                'Pragma': 'no-cache',
              },
        baseDirectory: baseDirectory,
        directory: directory,
        filename: filename,
        requiresWiFi: false,
        allowPause: true, // Try resume first
        priority: 10,
        retries: 0, // No automatic retries - we handle ALL retries with HTTP-aware logic
        updates: Updates.statusAndProgress, // ✅ Get both status AND progress updates
      );

      final downloader = FileDownloader();

      // Create a completer to wait for download completion
      final completer = Completer<void>();

      // Listen to broadcast stream to get full status info including HTTP code
      // Using broadcast stream allows multiple downloads and retries
      listener = _getUpdatesStream().listen((update) async {
        if (update.task.taskId != task.taskId) return;

        debugPrint('📡 Received update for task ${task.taskId}: ${update.runtimeType}');

        if (update is TaskProgressUpdate) {
          final percents = (update.progress * 100).round();
          debugPrint('📊 Progress: $percents%');
          if (!progress.isClosed) {
            progress.add(percents.clamp(0, 100));
          }
        } else if (update is TaskStatusUpdate) {
          debugPrint('📡 TaskStatusUpdate: ${update.status}, HTTP: ${update.responseStatusCode}');

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
              debugPrint('🔴 SmartDownloader: TaskStatus.failed detected');
              debugPrint('🔴 HTTP Status Code from update: ${update.responseStatusCode}');
              debugPrint('🔴 Exception: ${update.exception}');
              debugPrint('🔴 Progress closed: ${progress.isClosed}');
              debugPrint('🔴 Current attempt: $currentAttempt');

              // Try to get HTTP code from multiple sources
              int? httpCode = update.responseStatusCode;

              // If not in responseStatusCode, check exception
              if (httpCode == null && update.exception != null) {
                if (update.exception is TaskHttpException) {
                  httpCode = (update.exception as TaskHttpException).httpResponseCode;
                  debugPrint('🔴 HTTP Status Code from TaskHttpException: $httpCode');
                }
              }

              final resumePending = await _handleFailedDownload(
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
                cancelToken: cancelToken,
                onListenerCreated: onListenerCreated,
                onTaskCreated: onTaskCreated,
              );

              // Only cleanup if no resume is pending
              // If resume was triggered, we need to keep listening for the result
              if (!resumePending) {
                await listener?.cancel();
                completer.complete();
              } else {
                debugPrint('🔄 Resume pending - keeping listener active');
              }
              break;

            case TaskStatus.canceled:
              if (!progress.isClosed) {
                progress.addError(
                  const DownloadException(DownloadError.canceled()),
                  StackTrace.current,
                );
                progress.close();
              }
              await listener?.cancel();
              completer.complete(); // ✅ Signal completion
              break;

            case TaskStatus.notFound:
              debugPrint('🔴 SmartDownloader: TaskStatus.notFound detected (404)');

              // 404 is a non-retryable error - handle immediately
              // Note: 404 always returns false (no resume), but using same pattern for consistency
              final resumePending404 = await _handleFailedDownload(
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
                cancelToken: cancelToken,
                onListenerCreated: onListenerCreated,
                onTaskCreated: onTaskCreated,
              );

              if (!resumePending404) {
                await listener?.cancel();
                completer.complete();
              }
              break;

            default:
              break;
          }
        }
      });

      // Notify about new listener
      onListenerCreated?.call(listener);

      debugPrint('🔵 Enqueueing task ${task.taskId}...');
      final result = await downloader.enqueue(task);
      debugPrint('🔵 Enqueue result: $result');

      // Notify about task ID for cancellation
      onTaskCreated?.call(task.taskId); // ← ADD: Notify task created

      // ✅ Wait for download to complete
      debugPrint('🔵 Waiting for download completion...');
      await completer.future;
      debugPrint('🔵 Download completed!');

      // Ensure listener is canceled after completion
      await listener.cancel();
    } catch (e) {
      debugPrint('❌ Exception in _downloadWithSmartRetry: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');

      // Cancel listener before retry
      await listener?.cancel();

      if (currentAttempt < maxRetries) {
        debugPrint('⚠️ Retrying after exception... attempt ${currentAttempt + 1}/$maxRetries');
        await Future.delayed(Duration(seconds: currentAttempt * 2)); // Exponential backoff

        // Check cancellation before retry
        try {
          cancelToken?.throwIfCancelled();
        } catch (e) {
          if (!progress.isClosed) {
            progress.addError(e);
            progress.close();
          }
          return;
        }

        return _downloadWithSmartRetry(
          url: url,
          targetPath: targetPath,
          token: token,
          maxRetries: maxRetries,
          progress: progress,
          currentAttempt: currentAttempt + 1,
          currentListener: currentListener,
          cancelToken: cancelToken,
          onListenerCreated: onListenerCreated,
          onTaskCreated: onTaskCreated, // ← ADD: Pass callback through
        );
      } else {
        if (!progress.isClosed) {
          progress.addError(
            DownloadException(
              DownloadError.unknown(
                'Download failed after $maxRetries attempts: $e',
              ),
            ),
            StackTrace.current,
          );
          progress.close();
        }
      }
    }
  }

  /// Handles a failed download by attempting resume or retry.
  ///
  /// Returns `true` if resume was triggered (caller should keep listener active).
  /// Returns `false` if giving up or starting fresh retry (caller can cleanup).
  static Future<bool> _handleFailedDownload({
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
    CancelToken? cancelToken,
    void Function(StreamSubscription)? onListenerCreated,
    void Function(String taskId)? onTaskCreated,
  }) async {
    debugPrint('🟡 _handleFailedDownload called');
    debugPrint('🟡 httpStatusCode: $httpStatusCode');
    debugPrint('🟡 progress.isClosed: ${progress.isClosed}');

    // Check if error is retryable based on HTTP status code
    if (httpStatusCode != null) {
      debugPrint('🟢 httpStatusCode is not null: $httpStatusCode');

      // Auth errors (401, 403) and not-found (404) should NOT be retried
      if (httpStatusCode == 401) {
        debugPrint('🟢 Detected 401 - stopping immediately');
        if (!progress.isClosed) {
          debugPrint('🟢 Adding error to progress stream');
          progress.addError(
            const DownloadException(DownloadError.unauthorized()),
            StackTrace.current,
          );
          progress.close();
          debugPrint('🟢 Progress stream closed');
        } else {
          debugPrint('⚠️ Progress already closed - cannot add error!');
        }
        return false; // Stop immediately, no resume pending
      }

      if (httpStatusCode == 403) {
        if (!progress.isClosed) {
          progress.addError(
            const DownloadException(DownloadError.forbidden()),
            StackTrace.current,
          );
          progress.close();
        }
        return false; // Stop immediately, no resume pending
      }

      if (httpStatusCode == 404) {
        if (!progress.isClosed) {
          progress.addError(
            const DownloadException(DownloadError.notFound()),
            StackTrace.current,
          );
          progress.close();
        }
        return false; // Stop immediately, no resume pending
      }
    }

    // First, try to resume if possible (for transient errors only)
    try {
      final canResume = await downloader.taskCanResume(task);
      if (canResume) {
        debugPrint('🔄 Attempting to resume task ${task.taskId}...');
        await downloader.resume(task);
        debugPrint('🔄 Resume triggered, waiting for status update...');
        // Resume triggered - let event loop handle the result
        // If resume succeeds → TaskStatus.complete will fire
        // If resume fails (e.g., weak ETag) → TaskStatus.failed will fire and retry logic runs
        return true; // ✅ Resume pending - caller should keep listener active!
      }
    } catch (e) {
      debugPrint('⚠️ Resume failed with exception: $e');
      // Fall through to retry logic below
    }

    // If resume failed or not possible, try full retry (only for transient errors)
    if (currentAttempt < maxRetries) {
      // Exponential backoff
      await Future.delayed(Duration(seconds: currentAttempt * 2));

      // Check cancellation before retry
      try {
        cancelToken?.throwIfCancelled();
      } catch (e) {
        if (!progress.isClosed) {
          progress.addError(e);
          progress.close();
        }
        return false; // Cancelled, no resume pending
      }

      // Start fresh retry - new listener will be created
      await _downloadWithSmartRetry(
        url: url,
        targetPath: targetPath,
        token: token,
        maxRetries: maxRetries,
        progress: progress,
        currentAttempt: currentAttempt + 1,
        currentListener: currentListener,
        cancelToken: cancelToken,
        onListenerCreated: onListenerCreated,
        onTaskCreated: onTaskCreated,
      );
      return false; // Fresh retry started, no resume pending on THIS listener
    } else {
      if (!progress.isClosed) {
        progress.addError(
          DownloadException(
            DownloadError.network(
              'Download failed after $maxRetries attempts. This may be due to network issues or server problems.',
            ),
          ),
          StackTrace.current,
        );
        progress.close();
      }
      return false; // Gave up, no resume pending
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
