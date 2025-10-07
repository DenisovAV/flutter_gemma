import 'dart:async';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/download_error.dart';
import 'package:flutter_gemma/core/domain/download_exception.dart';
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';

/// Download service implementation using SmartDownloader
///
/// This is a thin wrapper around SmartDownloader to implement the DownloadService interface.
/// All downloads benefit from SmartDownloader's HTTP-aware retry logic.
///
/// Features (provided by SmartDownloader):
/// - HTTP-aware retry (401/403/404 fail after 1 attempt, others retry up to maxRetries)
/// - Background downloads with resume capability
/// - Progress tracking via streams
/// - Network interruption recovery
/// - Authentication token support
/// - Works with ANY URL (HuggingFace, Google Drive, custom servers, etc.)
class BackgroundDownloaderService implements DownloadService {
  final FileDownloader _downloader;
  final Map<String, DownloadTask> _activeTasks = {};
  bool _initialized = false;

  BackgroundDownloaderService({FileDownloader? downloader})
      : _downloader = downloader ?? FileDownloader();

  /// Initialize download service with tracking and resume support
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    try {
      // Enable tracking for smart_downloads group
      // This allows automatic resume after app restart/kill
      await _downloader.trackTasksInGroup('smart_downloads');

      // Resume any downloads that were interrupted by app kill
      await _downloader.resumeFromBackground();

      // Reschedule tasks that were killed (with 5s delay as recommended)
      Future.delayed(const Duration(seconds: 5), () {
        _downloader.rescheduleKilledTasks();
      });

      debugPrint('BackgroundDownloaderService: Initialized with tracking enabled');
    } catch (e) {
      debugPrint('BackgroundDownloaderService: Initialization error: $e');
    }

    _initialized = true;
  }

  @override
  Future<void> download(String url, String targetPath, {String? token}) async {
    await _ensureInitialized();

    final task = DownloadTask(
      url: url,
      filename: targetPath,
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      updates: Updates.statusAndProgress,
    );

    final result = await _downloader.download(task);

    if (result.status != TaskStatus.complete) {
      throw _createDownloadException(result.status, null, null);
    }
  }

  @override
  Stream<int> downloadWithProgress(
    String url,
    String targetPath, {
    String? token,
    int maxRetries = 10,
  }) {
    // Delegate to SmartDownloader for all URLs
    // SmartDownloader provides HTTP-aware retry logic for ANY URL
    return SmartDownloader.downloadWithProgress(
      url: url,
      targetPath: targetPath,
      token: token,
      maxRetries: maxRetries,
    );
  }

  @override
  Future<bool> canResume(String taskId) async {
    final task = _activeTasks[taskId];
    if (task == null) return false;

    final taskRecord = await _downloader.database.recordForId(taskId);
    if (taskRecord == null) return false;

    // Can resume if task was paused or failed and supports resume
    return taskRecord.status == TaskStatus.paused ||
           taskRecord.status == TaskStatus.failed;
  }

  @override
  Future<void> resume(String taskId) async {
    final task = _activeTasks[taskId];
    if (task == null) {
      throw UnsupportedError('Task not found: $taskId');
    }

    final canResumeTask = await canResume(taskId);
    if (!canResumeTask) {
      throw UnsupportedError('Task cannot be resumed: $taskId');
    }

    await _downloader.resume(task);
  }

  @override
  Future<void> cancel(String taskId) async {
    final task = _activeTasks[taskId];
    if (task != null) {
      await _downloader.cancelTaskWithId(taskId);
      _activeTasks.remove(taskId);
    }
  }

  /// Creates a type-safe exception based on HTTP status code and task status
  DownloadException _createDownloadException(
    TaskStatus status,
    int? httpStatusCode,
    TaskException? taskException,
  ) {
    // Check HTTP status code first for specific errors
    if (httpStatusCode != null) {
      final error = switch (httpStatusCode) {
        401 => const DownloadError.unauthorized(),
        403 => const DownloadError.forbidden(),
        404 => const DownloadError.notFound(),
        429 => const DownloadError.rateLimited(),
        >= 500 => DownloadError.serverError(httpStatusCode),
        _ => DownloadError.unknown('HTTP $httpStatusCode'),
      };
      return DownloadException(error);
    }

    // Fall back to task status
    final error = switch (status) {
      TaskStatus.notFound => const DownloadError.notFound(),
      TaskStatus.canceled => const DownloadError.canceled(),
      TaskStatus.failed => _mapTaskExceptionToError(taskException),
      _ => DownloadError.unknown('Unexpected status: $status'),
    };

    return DownloadException(error);
  }

  /// Maps TaskException to appropriate DownloadError
  DownloadError _mapTaskExceptionToError(TaskException? taskException) {
    if (taskException == null) {
      return const DownloadError.unknown('Download failed');
    }

    final description = taskException.description.toLowerCase();

    // Check for network-related errors
    if (description.contains('connection') ||
        description.contains('network') ||
        description.contains('timeout') ||
        description.contains('socket')) {
      return DownloadError.network(taskException.description);
    }

    return DownloadError.unknown(taskException.description);
  }
}
