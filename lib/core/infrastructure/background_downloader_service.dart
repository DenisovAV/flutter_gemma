import 'dart:async';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_gemma/core/services/download_service.dart';

/// Download service using background_downloader package
///
/// Features:
/// - Background downloads with resume capability
/// - Progress tracking via streams
/// - Network interruption recovery
/// - Authentication token support
class BackgroundDownloaderService implements DownloadService {
  final FileDownloader _downloader;
  final Map<String, DownloadTask> _activeTasks = {};

  BackgroundDownloaderService({FileDownloader? downloader})
      : _downloader = downloader ?? FileDownloader();

  @override
  Future<void> download(String url, String targetPath, {String? token}) async {
    final task = DownloadTask(
      url: url,
      filename: targetPath,
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      updates: Updates.statusAndProgress,
    );

    final result = await _downloader.download(task);

    if (result.status != TaskStatus.complete) {
      throw Exception('Download failed: ${result.status}');
    }
  }

  @override
  Stream<int> downloadWithProgress(String url, String targetPath, {String? token}) async* {
    final taskId = _generateTaskId(url);

    final task = DownloadTask(
      taskId: taskId,
      url: url,
      filename: targetPath,
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      updates: Updates.statusAndProgress,
    );

    _activeTasks[taskId] = task;

    final completer = Completer<void>();
    int lastProgress = 0;

    // Listen to progress updates
    final subscription = _downloader.updates.listen((update) {
      if (update is TaskProgressUpdate && update.task.taskId == taskId) {
        lastProgress = (update.progress * 100).toInt();
      } else if (update is TaskStatusUpdate && update.task.taskId == taskId) {
        if (update.status == TaskStatus.complete) {
          completer.complete();
        } else if (update.status == TaskStatus.failed ||
                   update.status == TaskStatus.notFound ||
                   update.status == TaskStatus.canceled) {
          completer.completeError(Exception('Download failed: ${update.status}'));
        }
      }
    });

    try {
      // Start download
      await _downloader.enqueue(task);

      // Yield progress updates periodically
      while (!completer.isCompleted) {
        yield lastProgress;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Final 100% progress
      yield 100;

      await completer.future;
    } finally {
      await subscription.cancel();
      _activeTasks.remove(taskId);
    }
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

  /// Generates a unique task ID from URL
  String _generateTaskId(String url) {
    return 'download_${url.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
  }
}
