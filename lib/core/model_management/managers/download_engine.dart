part of '../../../mobile/flutter_gemma_mobile.dart';

/// Unified download engine for all model types
class UnifiedDownloadEngine {
  static const String downloadGroup = 'flutter_gemma_downloads';

  /// Downloads a model specification with progress tracking
  static Stream<DownloadProgress> downloadModelWithProgress(
    ModelSpec spec, {
    String? token,
  }) async* {
    debugPrint('Starting download for model: ${spec.name} (${spec.files.length} files)');

    try {
      final totalFiles = spec.files.length;
      int completedFiles = 0;

      for (int i = 0; i < spec.files.length; i++) {
        final file = spec.files[i];
        final filePath = await ModelFileSystemManager.getModelFilePath(file.filename);

        debugPrint('Downloading file ${i + 1}/$totalFiles: ${file.filename}');

        // Emit progress for current file start
        yield DownloadProgress(
          currentFileIndex: i,
          totalFiles: totalFiles,
          currentFileProgress: 0,
          currentFileName: file.filename,
        );

        // Download current file with progress
        await for (final progress in _downloadSingleFileWithProgress(
          url: file.url,
          targetPath: filePath,
          token: token,
        )) {
          yield DownloadProgress(
            currentFileIndex: i,
            totalFiles: totalFiles,
            currentFileProgress: progress,
            currentFileName: file.filename,
          );
        }

        // Validate downloaded file
        final minSize = file.extension == '.json' ? 1024 : 1024 * 1024; // 1KB for JSON, 1MB for others
        if (!await ModelFileSystemManager.isFileValid(filePath, minSizeBytes: minSize)) {
          throw ModelValidationException(
            'Downloaded file failed validation: ${file.filename}',
            null,
            filePath,
          );
        }

        completedFiles++;
        debugPrint('Completed file $completedFiles/$totalFiles: ${file.filename}');
      }

      // Save to SharedPreferences ONLY after ALL files are successfully downloaded
      await ModelPreferencesManager.saveModelFiles(spec);

      // Emit final progress
      yield DownloadProgress(
        currentFileIndex: totalFiles,
        totalFiles: totalFiles,
        currentFileProgress: 100,
        currentFileName: 'Complete',
      );

      debugPrint('Successfully downloaded model: ${spec.name}');
    } catch (e) {
      debugPrint('Download failed for model ${spec.name}: $e');

      // Cleanup any partial files
      await ModelFileSystemManager.cleanupFailedDownload(spec);

      if (e is ModelException) {
        rethrow;
      } else {
        throw ModelDownloadException(
          'Failed to download model: ${spec.name}',
          e,
        );
      }
    }
  }

  /// Downloads a model specification without progress tracking
  static Future<void> downloadModel(
    ModelSpec spec, {
    String? token,
  }) async {
    await for (final _ in downloadModelWithProgress(spec, token: token)) {
      // Just consume the stream without emitting progress
    }
  }

  /// Checks if a model specification is fully installed and valid
  static Future<bool> isModelInstalled(ModelSpec spec) async {
    // Check SharedPreferences first
    if (!await ModelPreferencesManager.isModelInstalled(spec)) {
      return false;
    }

    // Validate all files exist and are valid
    return await ModelFileSystemManager.validateModelFiles(spec);
  }

  /// Deletes all files for a model specification
  static Future<void> deleteModel(ModelSpec spec) async {
    debugPrint('Deleting model: ${spec.name}');

    try {
      // Delete all files
      for (final file in spec.files) {
        await ModelFileSystemManager.deleteModelFile(file.filename);
      }

      // Clear from SharedPreferences
      await ModelPreferencesManager.clearModelFiles(spec);

      debugPrint('Successfully deleted model: ${spec.name}');
    } catch (e) {
      debugPrint('Failed to delete model ${spec.name}: $e');
      throw ModelStorageException(
        'Failed to delete model: ${spec.name}',
        e,
        'delete_model',
      );
    }
  }

  /// Downloads a single file with progress tracking
  /// Enhanced with smart resume detection and task registry integration
  static Stream<int> _downloadSingleFileWithProgress({
    required String url,
    required String targetPath,
    String? token,
  }) async* {
    final filename = targetPath.split('/').last;

    // Check if we can resume this file before starting new download
    final resumeStatus = await ResumeChecker.checkResumeStatus(filename);

    switch (resumeStatus) {
      case ResumeStatus.fileComplete:
        debugPrint('File already complete, skipping download: $filename');
        yield 100;
        return;

      case ResumeStatus.canResume:
        debugPrint('Attempting to resume download: $filename');
        final taskId = await DownloadTaskRegistry.getTaskId(filename);
        if (taskId != null) {
          final existingTask = DownloadTask(
            taskId: taskId,
            url: url,
            filename: filename,
            group: downloadGroup,
          );

          final downloader = FileDownloader();
          try {
            final resumed = await downloader.resume(existingTask);
            if (resumed) {
              debugPrint('Successfully resumed download: $filename');
              // Monitor the resumed download
              yield* _monitorExistingDownload(existingTask, downloader);
              return;
            }
          } catch (e) {
            debugPrint('Failed to resume download $filename: $e');
            // Fall through to start new download
          }
        }
        break;

      case ResumeStatus.cannotResume:
      case ResumeStatus.error:
        // Clean up invalid state and start fresh
        debugPrint('Cleaning up invalid resume state for: $filename');
        try {
          await ModelFileSystemManager.deleteModelFile(filename);
          await DownloadTaskRegistry.unregisterTask(filename);
        } catch (e) {
          debugPrint('Failed to cleanup invalid state for $filename: $e');
        }
        break;

      default:
        // Continue with normal download process
        break;
    }

    // Use HuggingFace wrapper for HF URLs to handle ETag issues
    if (HuggingFaceDownloader.isHuggingFaceUrl(url)) {
      yield* HuggingFaceDownloader.downloadWithProgress(
        url: url,
        targetPath: targetPath,
        token: token,
        maxRetries: 10,
      );
      return;
    }

    // Start new download with task registry integration
    final progress = StreamController<int>();

    Task.split(filePath: targetPath).then((result) async {
      try {
        final (baseDirectory, directory, filename) = result;

        // Generate taskId and register before starting download
        final taskId = _generateTaskId();
        await DownloadTaskRegistry.registerTask(filename, taskId);

        final task = DownloadTask(
          taskId: taskId,
          url: url,
          group: downloadGroup,
          headers: token != null
              ? {
                  'Authorization': 'Bearer $token',
                  'Connection': 'keep-alive',
                }
              : {
                  'Connection': 'keep-alive',
                },
          baseDirectory: baseDirectory,
          directory: directory,
          filename: filename,
          requiresWiFi: false,
          allowPause: true,
          priority: 10,
          retries: 10,
        );

        final downloader = FileDownloader();

        await downloader.download(
          task,
          onProgress: (portion) {
            final percents = (portion * 100).round();
            progress.add(percents.clamp(0, 100));
          },
          onStatus: (status) async {
            switch (status) {
              case TaskStatus.complete:
                if (!progress.isClosed) {
                  progress.add(100);
                  progress.close();
                }
                // Unregister task on successful completion
                await DownloadTaskRegistry.unregisterTask(filename);
                debugPrint('Download completed successfully: $filename');
                break;
              case TaskStatus.canceled:
                if (!progress.isClosed) {
                  progress.addError('Download canceled');
                  progress.close();
                }
                // Keep task registered for potential resume
                debugPrint('Download canceled: $filename');
                break;
              case TaskStatus.failed:
                if (!progress.isClosed) {
                  // Check if this task can be resumed
                  try {
                    final canResume = await downloader.taskCanResume(task);
                    if (canResume) {
                      debugPrint('Download failed but can be resumed: $filename');
                      // Keep task registered for resume
                      // Don't close progress stream, let caller handle retry
                      progress.addError('Download failed but resumable');
                    } else {
                      debugPrint('Download failed and cannot be resumed: $filename');
                      await DownloadTaskRegistry.unregisterTask(filename);
                      progress.addError('Download failed permanently');
                    }
                  } catch (e) {
                    debugPrint('Error checking resume capability for $filename: $e');
                    progress.addError('Download failed: $e');
                  }
                  progress.close();
                }
                break;
              case TaskStatus.paused:
                debugPrint('Download paused: $filename');
                break;
              case TaskStatus.running:
                // Keep task active in registry
                break;
              default:
                debugPrint('Download status for $filename: $status');
                break;
            }
          },
        );
      } catch (e) {
        // Cleanup task registration on initialization failure
        await DownloadTaskRegistry.unregisterTask(filename);
        if (!progress.isClosed) {
          progress.addError('Download initialization failed: $e');
          progress.close();
        }
      }
    });

    yield* progress.stream;
  }

  /// Ensures a model is ready, applying replace policy
  static Future<void> ensureModelReady(ModelSpec spec) async {
    debugPrint('Ensuring model ready: ${spec.name}');

    // Check if target model is already ready
    if (await isModelInstalled(spec)) {
      debugPrint('Model ${spec.name} already ready');
      return;
    }

    // Handle model switching with replace policy
    await _handleModelSwitching(spec);

    // Download the target model if not available
    if (!await isModelInstalled(spec)) {
      debugPrint('Downloading model: ${spec.name}');
      await downloadModel(spec);
    }

    debugPrint('Model ${spec.name} is now ready');
  }

  /// Handles model switching according to replace policy
  static Future<void> _handleModelSwitching(ModelSpec spec) async {
    final currentSpec = await ModelPreferencesManager.loadModelSpec(spec.type, spec.name);

    if (currentSpec != null && currentSpec.name != spec.name) {
      if (spec.replacePolicy == ModelReplacePolicy.replace) {
        debugPrint('Replacing old model: ${currentSpec.name} with ${spec.name}');
        await deleteModel(currentSpec);
      } else {
        debugPrint('Keeping old model: ${currentSpec.name} alongside ${spec.name}');
      }
    }
  }

  /// Performs cleanup of orphaned files and invalid resume states
  static Future<void> performCleanup() async {
    try {
      debugPrint('Performing comprehensive model cleanup...');

      // 1. Enhanced file system cleanup
      final protectedFiles = await ModelPreferencesManager.getAllProtectedFiles();
      await ModelFileSystemManager.cleanupOrphanedFiles(
        protectedFiles: protectedFiles,
        enableResumeDetection: true,
      );

      // 2. Task registry cleanup
      await _cleanupTaskRegistry();

      // 3. Background_downloader cleanup
      await _cleanupBackgroundDownloaderResources();

      debugPrint('Comprehensive model cleanup completed');
    } catch (e) {
      debugPrint('Model cleanup failed: $e');
    }
  }

  /// Clean up task registry by removing invalid entries
  static Future<void> _cleanupTaskRegistry() async {
    try {
      debugPrint('Cleaning up task registry...');

      final allTasks = await DownloadTaskRegistry.getAllRegisteredTasks();
      final toRemove = <String>[];

      for (final entry in allTasks.entries) {
        final filename = entry.key;
        final resumeStatus = await ResumeChecker.checkResumeStatus(filename);

        switch (resumeStatus) {
          case ResumeStatus.fileComplete:
          case ResumeStatus.cannotResume:
          case ResumeStatus.error:
          case ResumeStatus.fileNotFound:
            toRemove.add(filename);
            break;
          default:
            // Keep valid entries
            break;
        }
      }

      if (toRemove.isNotEmpty) {
        await DownloadTaskRegistry.unregisterTasks(toRemove);
        debugPrint('Cleaned up ${toRemove.length} invalid task registry entries');
      }
    } catch (e) {
      debugPrint('Task registry cleanup failed: $e');
    }
  }

  /// Clean up background_downloader resources
  static Future<void> _cleanupBackgroundDownloaderResources() async {
    try {
      debugPrint('Cleaning up background_downloader resources...');

      final downloader = FileDownloader();

      // Reset all tasks in our download group (cancels active tasks)
      final resetCount = await downloader.reset(group: downloadGroup);
      debugPrint('Reset $resetCount background_downloader tasks');

    } catch (e) {
      debugPrint('Background_downloader cleanup failed: $e');
    }
  }

  /// Monitor an existing download task
  static Stream<int> _monitorExistingDownload(DownloadTask task, FileDownloader downloader) async* {
    final progress = StreamController<int>();

    // Set up monitoring for the resumed task
    downloader.updates.listen((update) {
      if (update.task.taskId == task.taskId) {
        switch (update) {
          case TaskProgressUpdate progressUpdate:
            final percent = (progressUpdate.progress * 100).round();
            if (!progress.isClosed) {
              progress.add(percent);
            }
            break;
          case TaskStatusUpdate statusUpdate:
            switch (statusUpdate.status) {
              case TaskStatus.complete:
                if (!progress.isClosed) {
                  progress.add(100);
                  progress.close();
                }
                // Unregister task on successful completion
                DownloadTaskRegistry.unregisterTask(task.filename);
                break;
              case TaskStatus.failed:
              case TaskStatus.canceled:
                if (!progress.isClosed) {
                  progress.addError('Download ${statusUpdate.status.name}: ${statusUpdate.exception?.description ?? "Unknown error"}');
                  progress.close();
                }
                break;
              default:
                break;
            }
            break;
        }
      }
    });

    yield* progress.stream;
  }

  /// Generate a unique task ID
  static String _generateTaskId() {
    return 'flutter_gemma_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().toString().split('#')[1].replaceAll(RegExp(r'[()]'), '')}';
  }
}