import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_gemma/core/domain/download_error.dart';
import 'package:flutter_gemma/core/domain/download_exception.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';

/// Decision for a failed download: whether to resume, do a fresh retry, or give
/// up. Extracted so the resume-attempt cap (#355) is unit-testable.
enum ResumeAction { resume, retry, giveUp }

@visibleForTesting
const int kMaxResumeAttempts = 3;

/// Watchdog window after a resume: if no progress/terminal event arrives within
/// this, the task is presumed silently dead (#355) and the stream is closed.
@visibleForTesting
const Duration kResumeWatchdog = Duration(seconds: 90);

/// Returns a [Timer] that fires [onTimeout] after [timeout] unless cancelled.
/// The download loop cancels it when the next progress/status event arrives, and
/// wires [onTimeout] to close [progress] with a network error + cancel the
/// listener, so a silently-dead post-resume task can never hang forever.
@visibleForTesting
Timer armResumeWatchdog({
  required StreamController<int> progress,
  required void Function() onTimeout,
  Duration timeout = kResumeWatchdog,
}) {
  return Timer(timeout, onTimeout);
}

/// Whether [_ensureConfigured] should register a running [TaskNotification]
/// for the given [foreground] setting (#356). Extracted as a pure function so
/// the decision is unit-testable without a `FileDownloader` seam: on Android,
/// `background_downloader` only calls `WorkManager.setForeground()` — the
/// thing that actually activates the foreground service — when a `running`
/// notification is configured. Setting `Config.runInForeground` alone is a
/// no-op without it.
///
/// Scoped to the EXPLICIT `foreground: true` flag only (#357 review). The
/// notification, once configured, is global: `background_downloader`'s
/// `Notifications.kt` shows it for every task in the `running` state,
/// including ones that are NOT running in foreground
/// (`displayNotification`'s `else` branch calls `notify()` unconditionally
/// when `runInForeground` is false for that task). Returning true for the
/// auto-detect branch (`foreground == null`) would therefore show a
/// "Downloading model" notification on EVERY download — including small
/// ones well under the 500MB foreground threshold, where none showed before.
/// Trade-off: an auto-detected LARGE file (>500MB, which DOES run in
/// foreground) won't get a notification unless the caller passes
/// `foreground: true` explicitly. That's accepted in order to avoid the
/// spurious notification on the much more common small-download path.
@visibleForTesting
bool shouldConfigureForegroundNotification(bool? foreground) =>
    foreground == true;

/// Pure decision for [_handleFailedDownload]. Resume is only chosen while under
/// [maxResumeAttempts] — the old code resumed unconditionally whenever
/// `canResume`, which let a repeatedly-failing resume loop forever (#355).
@visibleForTesting
ResumeAction decideFailedDownloadAction({
  required bool canResume,
  required int resumeAttempt,
  required int currentAttempt,
  required int maxRetries,
  required int maxResumeAttempts,
}) {
  if (canResume && resumeAttempt < maxResumeAttempts) {
    return ResumeAction.resume;
  }
  if (currentAttempt < maxRetries) {
    return ResumeAction.retry;
  }
  return ResumeAction.giveUp;
}

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
/// - Auto-detects resume support based on server (HuggingFace = no resume)
/// - Android foreground service for large files (>500MB by default)
class SmartDownloader {
  static const String _downloadGroup = 'smart_downloads';
  static const int _foregroundThresholdMB = 500;

  // Track if FileDownloader has been configured
  static bool _isConfigured = false;
  static bool? _lastForegroundSetting;

  /// Configure FileDownloader for foreground mode
  ///
  /// [foreground]:
  /// - null: auto-detect based on file size (>500MB = foreground)
  /// - true: always use foreground
  /// - false: never use foreground
  static Future<void> _ensureConfigured(bool? foreground) async {
    // Only reconfigure if setting changed
    if (_isConfigured && _lastForegroundSetting == foreground) return;

    final downloader = FileDownloader();

    if (foreground == true) {
      // Always foreground
      await downloader.configure(
        androidConfig: [(Config.runInForeground, Config.always)],
      );
      gemmaLog('📲 SmartDownloader: Configured for ALWAYS foreground');
    } else if (foreground == false) {
      // Never foreground
      await downloader.configure(
        androidConfig: [(Config.runInForeground, Config.never)],
      );
      gemmaLog('📲 SmartDownloader: Configured for NEVER foreground');
    } else {
      // Auto-detect based on file size (default)
      await downloader.configure(
        globalConfig: [
          (Config.runInForegroundIfFileLargerThan, _foregroundThresholdMB),
        ],
      );
      gemmaLog(
        '📲 SmartDownloader: Configured for AUTO foreground (>${_foregroundThresholdMB}MB)',
      );
    }

    // #356: `Config.runInForeground`/`runInForegroundIfFileLargerThan` alone
    // never activates Android's real foreground service — the plugin only
    // calls `WorkManager.setForeground()` once a `running` notification is
    // configured. Without this, `foreground: true` was a no-op: no
    // notification, no setForeground() call, no Doze/battery-optimization
    // exemption. This does NOT touch WorkManager's separate 9-minute
    // `TaskRunner` timeout (#192) — that limit is unrelated and unchanged.
    //
    // Scoped to `foreground == true` only (#357 review) — see
    // shouldConfigureForegroundNotification's doc comment for why the
    // auto-detect (`null`) branch is intentionally excluded.
    if (shouldConfigureForegroundNotification(foreground)) {
      downloader.configureNotification(
        running: const TaskNotification('Downloading model', '{filename}'),
        progressBar: true,
      );

      // #357 review (Bug 2): on Android 13+ (API 33), background_downloader's
      // `displayNotification()` bails out BEFORE calling `setForeground()` if
      // `POST_NOTIFICATIONS` isn't granted at RUNTIME — declaring it in the
      // manifest alone is necessary but not sufficient, so the foreground
      // service would silently fail to activate. Request it proactively here
      // so a foreground download actually gets the exemption it asked for.
      // Best-effort: don't block/fail the download on a denial, just log it.
      // This is a no-op that resolves to `granted` on platforms/versions that
      // don't need the permission (e.g. desktop, pre-Android-13).
      try {
        final status = await downloader.permissions.request(
          PermissionType.notifications,
        );
        gemmaLog('📲 SmartDownloader: POST_NOTIFICATIONS request → $status');
      } catch (e) {
        gemmaLog('⚠️ SmartDownloader: POST_NOTIFICATIONS request failed: $e');
      }
    }

    _isConfigured = true;
    _lastForegroundSetting = foreground;
  }

  /// Check if URL is from HuggingFace CDN (uses weak ETag, resume not reliable)
  static bool _isHuggingFaceUrl(String url) {
    return url.contains('huggingface.co') ||
        url.contains('cdn-lfs.huggingface.co') ||
        url.contains('cdn-lfs-us-1.huggingface.co') ||
        url.contains('cdn-lfs-eu-1.huggingface.co');
  }

  // Global broadcast stream for FileDownloader.updates
  // This allows multiple downloads to listen simultaneously
  static Stream<TaskUpdate>? _broadcastStream;

  /// Get broadcast stream for FileDownloader updates
  /// Creates the broadcast stream once and reuses it for all downloads
  /// Optional hub stream configured at init (e.g. host cache client forwarder).
  static Stream<TaskUpdate>? _configuredDownloadUpdatesStream;

  /// Memoized broadcast wrapper for [_configuredDownloadUpdatesStream].
  static Stream<TaskUpdate>? _configuredBroadcastStream;

  /// Registers a shared download-updates stream for all SmartDownloader
  /// paths (new downloads and attach-to-existing).
  ///
  /// [stream] may be single- or broadcast; non-broadcast sources are
  /// wrapped with [Stream.asBroadcastStream] so concurrent downloads can
  /// each call [Stream.listen].
  static void configureDownloadUpdatesStream(Stream<TaskUpdate>? stream) {
    _configuredDownloadUpdatesStream = stream;
    _configuredBroadcastStream = null;
  }

  /// Clears injected hub configuration (e.g. registry reset / dispose).
  static void clearConfiguration() {
    _configuredDownloadUpdatesStream = null;
    _configuredBroadcastStream = null;
    _broadcastStream = null;
  }

  @visibleForTesting
  static void resetDownloadUpdatesStreamConfig() => clearConfiguration();

  @visibleForTesting
  static Stream<TaskUpdate> debugResolveUpdatesStream() =>
      _resolveUpdatesStream();

  static Stream<TaskUpdate> _getUpdatesStream() {
    _broadcastStream ??= FileDownloader().updates.asBroadcastStream();
    return _broadcastStream!;
  }

  static Stream<TaskUpdate> _resolveUpdatesStream() {
    final source = _configuredDownloadUpdatesStream;
    if (source != null) {
      _configuredBroadcastStream ??= source.isBroadcast
          ? source
          : source.asBroadcastStream();
      return _configuredBroadcastStream!;
    }
    return _getUpdatesStream();
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
  /// [foreground] - Android foreground service mode:
  ///   - null (default): auto-detect based on file size (>500MB = foreground)
  ///   - true: always use foreground (shows notification)
  ///   - false: never use foreground
  ///
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
    bool? foreground,
  }) {
    final progress = StreamController<int>();
    StreamSubscription? currentListener;
    StreamSubscription? cancellationListener;
    String? currentTaskId; // ← ADD: Store task ID for cancellation

    // Listen for cancellation
    if (cancelToken != null) {
      cancellationListener = cancelToken.whenCancelled.asStream().listen((
        _,
      ) async {
        gemmaLog('🚫 Cancellation requested');

        // Cancel the actual download task
        if (currentTaskId != null) {
          gemmaLog('🚫 Cancelling task: $currentTaskId');
          try {
            await FileDownloader().cancelTaskWithId(
              currentTaskId!,
            ); // ← ADD: Actually cancel the task
          } catch (e) {
            gemmaLog('⚠️ Failed to cancel task: $e');
          }
          // Also clear any pending resume watchdog so a cancelled download
          // doesn't leave a Timer holding the (now-closed) progress stream
          // alive for up to 90s.
          _cancelResumeWatchdog(currentTaskId!);
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

    // Configure FileDownloader and start download
    _ensureConfigured(foreground)
        .then((_) async {
          await _downloadWithSmartRetry(
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
              currentTaskId = taskId;
            },
          );
        })
        .catchError((Object e, StackTrace st) {
          // If _ensureConfigured() or a synchronous failure in
          // _downloadWithSmartRetry throws, surface it on the progress stream
          // and close it — otherwise the caller's `await for` over
          // progress.stream hangs forever (the silent-hang class this hub work
          // exists to prevent).
          if (!progress.isClosed) {
            progress.addError(e, st);
            progress.close();
          }
        })
        .whenComplete(() {
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
    int resumeAttempt = 0,
  }) async {
    // Mutable so the SAME listener can bump it across successive resume
    // rounds for this task (#355): a resume keeps this listener active, and
    // the next `TaskStatus.failed` for it must see a higher resumeAttempt so
    // decideFailedDownloadAction() eventually falls through to retry/giveUp
    // instead of resuming forever. A fresh retry recurses into a NEW call of
    // this method with a fresh `resumeAttempt: 0` scope — it must NOT reuse
    // this local.
    var localResumeAttempt = resumeAttempt;
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

    // Generate deterministic taskId based on URL + targetPath
    // This prevents duplicate downloads of the same file
    final taskId =
        '${url.hashCode.toUnsigned(32).toRadixString(16)}_${targetPath.hashCode.toUnsigned(32).toRadixString(16)}';

    gemmaLog(
      '🔵 _downloadWithSmartRetry called - attempt $currentAttempt/$maxRetries',
    );
    gemmaLog('🔵 URL: $url');
    gemmaLog('🔵 Target: $targetPath');
    gemmaLog('🔵 TaskId: $taskId');

    // Declare listener outside try block so it's accessible in catch
    StreamSubscription? listener;

    try {
      final downloader = FileDownloader();

      // Check if task already exists (e.g., after app restart or sleep/wake)
      final existingTask = await downloader.taskForId(taskId);
      if (existingTask != null) {
        gemmaLog(
          '🔵 Task $taskId already in progress, attaching to existing...',
        );

        // Create completer to wait for existing task completion
        final completer = Completer<void>();

        // Attach listener to existing task
        listener = _resolveUpdatesStream().listen(
          (update) async {
            if (update.task.taskId != taskId) return;

            if (update is TaskProgressUpdate) {
              // A live event means the task is not dead — cancel any pending
              // resume watchdog so a normally-progressing task never false-fires (#355).
              _cancelResumeWatchdog(update.task.taskId);
              final percents = (update.progress * 100).round();
              gemmaLog('📊 Progress (existing): $percents%');
              if (!progress.isClosed) {
                progress.add(percents.clamp(0, 100));
              }
            } else if (update is TaskStatusUpdate) {
              _cancelResumeWatchdog(update.task.taskId);
              gemmaLog('📡 TaskStatusUpdate (existing): ${update.status}');
              if (update.status == TaskStatus.complete) {
                if (!progress.isClosed) {
                  progress.add(100);
                  progress.close();
                }
                await listener?.cancel();
                completer.complete();
              } else if (update.status == TaskStatus.failed ||
                  update.status == TaskStatus.canceled) {
                // Existing task failed - let caller handle retry
                if (!progress.isClosed) {
                  progress.addError(
                    DownloadException(
                      DownloadError.network(
                        'Existing download failed: ${update.status}',
                      ),
                    ),
                  );
                  progress.close();
                }
                await listener?.cancel();
                completer.complete();
              }
            }
          },
          onError: (Object error, StackTrace stackTrace) async {
            if (!progress.isClosed) {
              progress.addError(error, stackTrace);
              progress.close();
            }
            await listener?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError(
                  'Download updates stream closed before task $taskId '
                  'completed',
                ),
                StackTrace.current,
              );
            }
          },
        );

        onListenerCreated?.call(listener);
        onTaskCreated?.call(taskId);

        await completer.future;
        return;
      }

      final (baseDirectory, directory, filename) = await Task.split(
        filePath: targetPath,
      );

      // Auto-detect allowPause based on URL
      // HuggingFace uses weak ETags - resume not reliable
      // Other servers (GCS, Kaggle, custom) - resume usually works
      final allowPause = !_isHuggingFaceUrl(url);
      gemmaLog(
        '🔵 allowPause: $allowPause (HuggingFace: ${_isHuggingFaceUrl(url)})',
      );

      final task = DownloadTask(
        taskId: taskId,
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
        allowPause:
            allowPause, // Auto-detect: false for HuggingFace, true for others
        priority: 10,
        retries: 0, // We handle retries manually with HTTP-aware logic
        updates: Updates.statusAndProgress,
      );

      // Create a completer to wait for download completion
      final completer = Completer<void>();

      // Listen to broadcast stream to get full status info including HTTP code
      // Using broadcast stream allows multiple downloads and retries
      listener = _resolveUpdatesStream().listen(
        (update) async {
          if (update.task.taskId != task.taskId) return;

          gemmaLog(
            '📡 Received update for task ${task.taskId}: ${update.runtimeType}',
          );

          if (update is TaskProgressUpdate) {
            // A live event means the task is not dead — cancel any pending
            // resume watchdog so a normally-progressing task never false-fires (#355).
            _cancelResumeWatchdog(update.task.taskId);
            final percents = (update.progress * 100).round();
            gemmaLog('📊 Progress: $percents%');
            if (!progress.isClosed) {
              progress.add(percents.clamp(0, 100));
            }
          } else if (update is TaskStatusUpdate) {
            _cancelResumeWatchdog(update.task.taskId);
            gemmaLog(
              '📡 TaskStatusUpdate: ${update.status}, HTTP: ${update.responseStatusCode}',
            );

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
                gemmaLog('🔴 SmartDownloader: TaskStatus.failed detected');
                gemmaLog(
                  '🔴 HTTP Status Code from update: ${update.responseStatusCode}',
                );
                gemmaLog('🔴 Exception: ${update.exception}');
                gemmaLog('🔴 Progress closed: ${progress.isClosed}');
                gemmaLog('🔴 Current attempt: $currentAttempt');

                // Try to get HTTP code from multiple sources
                int? httpCode = update.responseStatusCode;

                // If not in responseStatusCode, check exception
                if (httpCode == null && update.exception != null) {
                  if (update.exception is TaskHttpException) {
                    httpCode = (update.exception as TaskHttpException)
                        .httpResponseCode;
                    gemmaLog(
                      '🔴 HTTP Status Code from TaskHttpException: $httpCode',
                    );
                  }
                }

                // Capture-and-increment SYNCHRONOUSLY (before the await) rather
                // than after it returns (#357 review): a broadcast stream's
                // onData handlers don't serialize, so a second `failed`/
                // `notFound` event for this task could interleave with this
                // await and read the stale (pre-increment) counter. Bumping it
                // here — before yielding control — guarantees two concurrent
                // failed events for this task always see DIFFERENT
                // resumeAttempt values. If the call turns out NOT to have
                // triggered a resume, give the slot back so a non-resume
                // failure never consumes budget it didn't use.
                final attemptForThisRound = localResumeAttempt;
                localResumeAttempt++;

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
                  resumeAttempt: attemptForThisRound,
                  onSettle: () {
                    // Watchdog fire is a terminal outcome for this round —
                    // settle the completer so the outer
                    // `.whenComplete(() => cancellationListener?.cancel())`
                    // in downloadWithProgress runs (#357 review fix: was
                    // never called before, leaking the subscription).
                    if (!completer.isCompleted) completer.complete();
                  },
                );

                // Only cleanup if no resume is pending
                // If resume was triggered, we need to keep listening for the result
                if (!resumePending) {
                  localResumeAttempt--; // give the slot back — not consumed
                  await listener?.cancel();
                  completer.complete();
                } else {
                  gemmaLog(
                    '🔄 Resume pending - keeping listener active '
                    '(resumeAttempt now $localResumeAttempt)',
                  );
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
                gemmaLog(
                  '🔴 SmartDownloader: TaskStatus.notFound detected (404)',
                );

                // 404 is a non-retryable error - handle immediately
                // Note: 404 always returns false (no resume), but using same pattern for consistency
                //
                // Same synchronous capture-and-increment as the `failed` case
                // above (#357 review) — closes the race window where a second
                // concurrent event could read a stale counter mid-await.
                final attemptForThisRound404 = localResumeAttempt;
                localResumeAttempt++;

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
                  resumeAttempt: attemptForThisRound404,
                  onSettle: () {
                    // 404 never resumes (checked earlier in
                    // _handleFailedDownload), so the watchdog is never armed
                    // on this path — kept for consistency with the `failed`
                    // case above in case that ever changes.
                    if (!completer.isCompleted) completer.complete();
                  },
                );

                if (!resumePending404) {
                  localResumeAttempt--; // give the slot back — not consumed
                  await listener?.cancel();
                  completer.complete();
                }
                break;

              default:
                break;
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) async {
          if (!progress.isClosed) {
            progress.addError(error, stackTrace);
            progress.close();
          }
          await listener?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'Download updates stream closed before task ${task.taskId} '
                'completed',
              ),
              StackTrace.current,
            );
          }
        },
      );

      // Notify about new listener
      onListenerCreated?.call(listener);

      gemmaLog('🔵 Enqueueing task ${task.taskId}...');
      final result = await downloader.enqueue(task);
      gemmaLog('🔵 Enqueue result: $result');

      // Notify about task ID for cancellation
      onTaskCreated?.call(task.taskId); // ← ADD: Notify task created

      // ✅ Wait for download to complete
      gemmaLog('🔵 Waiting for download completion...');
      await completer.future;
      gemmaLog('🔵 Download completed!');

      // Ensure listener is canceled after completion
      await listener.cancel();
    } catch (e) {
      gemmaLog('❌ Exception in _downloadWithSmartRetry: $e');
      gemmaLog('❌ Stack trace: ${StackTrace.current}');

      // Cancel listener before retry
      await listener?.cancel();

      if (currentAttempt < maxRetries) {
        gemmaLog(
          '⚠️ Retrying after exception... attempt ${currentAttempt + 1}/$maxRetries',
        );
        await Future.delayed(
          Duration(seconds: currentAttempt * 2),
        ); // Exponential backoff

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

        // resumeAttempt intentionally omitted → resets to 0 for a fresh retry
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
    required int resumeAttempt,
    void Function()? onSettle,
  }) async {
    gemmaLog('🟡 _handleFailedDownload called');
    gemmaLog('🟡 httpStatusCode: $httpStatusCode');
    gemmaLog('🟡 progress.isClosed: ${progress.isClosed}');

    // Check if error is retryable based on HTTP status code
    if (httpStatusCode != null) {
      gemmaLog('🟢 httpStatusCode is not null: $httpStatusCode');

      // Auth errors (401, 403) and not-found (404) should NOT be retried
      if (httpStatusCode == 401) {
        gemmaLog('🟢 Detected 401 - stopping immediately');
        if (!progress.isClosed) {
          gemmaLog('🟢 Adding error to progress stream');
          progress.addError(
            const DownloadException(DownloadError.unauthorized()),
            StackTrace.current,
          );
          progress.close();
          gemmaLog('🟢 Progress stream closed');
        } else {
          gemmaLog('⚠️ Progress already closed - cannot add error!');
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

    // Decide resume vs retry vs give-up. Resume is CAPPED (#355): the old code
    // resumed unconditionally whenever canResume, so a repeatedly-failing
    // resume (HF weak-ETag) or a silently-dead task looped/hung forever.
    bool canResume = false;
    try {
      canResume = await downloader.taskCanResume(task);
    } catch (e) {
      gemmaLog('⚠️ taskCanResume threw: $e — treating as not resumable');
    }

    final action = decideFailedDownloadAction(
      canResume: canResume,
      resumeAttempt: resumeAttempt,
      currentAttempt: currentAttempt,
      maxRetries: maxRetries,
      maxResumeAttempts: kMaxResumeAttempts,
    );

    if (action == ResumeAction.resume) {
      gemmaLog(
        '🔄 Resuming task ${task.taskId} '
        // +1: human-readable 1-indexed; the cap comparison is 0-indexed
        '(resume attempt ${resumeAttempt + 1}/$kMaxResumeAttempts)...',
      );
      try {
        await downloader.resume(task);
        gemmaLog('🔄 Resume triggered, waiting for status update...');
        // Resume was accepted - let event loop handle the result.
        // If resume succeeds → TaskStatus.complete will fire.
        // If resume fails (e.g., weak ETag) → TaskStatus.failed will fire and
        // the SAME listener re-enters this method with resumeAttempt + 1
        // (threaded by the caller in _downloadWithSmartRetry).
        _armResumeWatchdog(
          taskId: task.taskId,
          progress: progress,
          listener: currentListener,
          onSettle: onSettle,
        );
        return true; // ✅ Resume pending - caller should keep listener active!
      } catch (e) {
        gemmaLog('⚠️ resume() threw: $e — falling through to retry/give-up');
        // resume() was never accepted, so no status event will ever arrive
        // for it — do NOT arm the watchdog or return true here, that would
        // leave the listener waiting forever. Fall through to the bounded
        // retry/give-up logic below instead.
      }
    }
    // action == retry or giveUp → fall through to the retry/give-up logic
    // below, which is already correctly capped on currentAttempt < maxRetries.
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
      // resumeAttempt intentionally omitted → resets to 0 for a fresh retry
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

  /// Keyed by taskId (#355 follow-up): SmartDownloader supports CONCURRENT
  /// downloads, so a single shared `Timer?` field would let one task's
  /// arm/cancel clobber another's watchdog. Each in-flight task gets its own
  /// entry.
  static final Map<String, Timer> _resumeWatchdogs = {};

  /// Arms the resume watchdog (#355 part 3): if no progress/status update
  /// arrives for [taskId] within [kResumeWatchdog], the task is presumed
  /// silently dead and [progress] is force-closed with a network error so the
  /// caller's `await for` over the stream can never hang forever.
  ///
  /// [onSettle] (#357 review): the `_downloadWithSmartRetry` listener that
  /// armed this watchdog is awaiting its own `Completer<void>` and cancels
  /// `cancellationListener` in a `.whenComplete()` once that completer
  /// settles. A watchdog firing IS a terminal outcome for that round — it
  /// force-closes [progress] and cancels [listener] — but without also
  /// completing the completer, that `.whenComplete()` never runs and the
  /// cancellation subscription leaks. [onSettle] lets the caller pass its
  /// completer-completion so a watchdog fire settles the same way any other
  /// terminal status update does.
  static void _armResumeWatchdog({
    required String taskId,
    required StreamController<int> progress,
    required StreamSubscription? listener,
    void Function()? onSettle,
  }) {
    _resumeWatchdogs.remove(taskId)?.cancel();
    _resumeWatchdogs[taskId] = armResumeWatchdog(
      progress: progress,
      onTimeout: () {
        gemmaLog('⏱️ Resume watchdog fired for $taskId — closing as failed');
        _resumeWatchdogs.remove(taskId);
        if (!progress.isClosed) {
          progress.addError(
            const DownloadException(
              DownloadError.network('Download resume timed out (no progress)'),
            ),
            StackTrace.current,
          );
          progress.close();
        }
        listener?.cancel();
        onSettle?.call();
      },
    );
  }

  /// Cancels a pending resume watchdog for [taskId] — called the moment any
  /// subsequent progress/status event arrives for that task, proving it's not
  /// dead. Only ever touches this task's own entry, so concurrent downloads
  /// can't cancel each other's watchdog.
  static void _cancelResumeWatchdog(String taskId) {
    _resumeWatchdogs.remove(taskId)?.cancel();
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
