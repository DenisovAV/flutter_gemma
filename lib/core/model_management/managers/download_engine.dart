part of '../../../mobile/flutter_gemma_mobile.dart';

/// Unified download engine for all model types
class UnifiedDownloadEngine {
  static const String downloadGroup = 'flutter_gemma_downloads';

  /// Downloads a model specification with progress tracking
  static Stream<DownloadProgress> downloadModelWithProgress(
    ModelSpec spec, {
    String? token,
  }) async* {

    try {
      final totalFiles = spec.files.length;

      for (int i = 0; i < spec.files.length; i++) {
        final file = spec.files[i];
        final filePath = await ModelFileSystemManager.getModelFilePath(file.filename);

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

        // print('Completed file ${i + 1}/$totalFiles: ${file.filename}');
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

      // print('Successfully downloaded model: ${spec.name}');
    } catch (e) {
      // print('Download failed for model ${spec.name}: $e');

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
    // print('Deleting model: ${spec.name}');

    try {
      // Delete all files
      for (final file in spec.files) {
        await ModelFileSystemManager.deleteModelFile(file.filename);
      }

      // Clear from SharedPreferences
      await ModelPreferencesManager.clearModelFiles(spec);

      // print('Successfully deleted model: ${spec.name}');
    } catch (e) {
      // print('Failed to delete model ${spec.name}: $e');
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
        // print('File already complete, skipping download: $filename');
        yield 100;
        return;

      case ResumeStatus.canResume:
        // print('Attempting to resume download: $filename');
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
              // print('Successfully resumed download: $filename');
              // Monitor the resumed download
              yield* _monitorExistingDownload(existingTask, downloader);
              return;
            }
          } catch (e) {
            // print('Failed to resume download $filename: $e');
            // Fall through to start new download
          }
        }
        break;

      case ResumeStatus.cannotResume:
      case ResumeStatus.error:
        // Clean up invalid state and start fresh
        // print('Cleaning up invalid resume state for: $filename');
        try {
          await ModelFileSystemManager.deleteModelFile(filename);
          await DownloadTaskRegistry.unregisterTask(filename);
        } catch (e) {
          // print('Failed to cleanup invalid state for $filename: $e');
        }
        break;

      case ResumeStatus.noTask:
        // print('No task registered for $filename - cleaning up orphaned file');
        try {
          await ModelFileSystemManager.deleteModelFile(filename);
          // print('Successfully cleaned up orphaned file: $filename');
        } catch (e) {
          // print('Failed to cleanup orphaned file $filename: $e');
        }
        break;

      case ResumeStatus.fileNotFound:
        // print('File not found for $filename - starting new download');
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
          headers: token != null && token.isNotEmpty
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
                // print('Download completed successfully: $filename');
                break;
              case TaskStatus.canceled:
                if (!progress.isClosed) {
                  progress.addError('Download canceled');
                  progress.close();
                }
                // Keep task registered for potential resume
                // print('Download canceled: $filename');
                break;
              case TaskStatus.failed:
                if (!progress.isClosed) {
                  // Check if this task can be resumed
                  try {
                    final canResume = await downloader.taskCanResume(task);
                    if (canResume) {
                      // print('Download failed but can be resumed: $filename');
                      // Keep task registered for resume
                      // Don't close progress stream, let caller handle retry
                      progress.addError('Download failed but resumable');
                    } else {
                      // print('Download failed and cannot be resumed: $filename');
                      await DownloadTaskRegistry.unregisterTask(filename);
                      progress.addError('Download failed permanently');
                    }
                  } catch (e) {
                    // print('Error checking resume capability for $filename: $e');
                    progress.addError('Download failed: $e');
                  }
                  progress.close();
                }
                break;
              case TaskStatus.paused:
                // print('Download paused: $filename');
                break;
              case TaskStatus.running:
                // Keep task active in registry
                break;
              default:
                // print('Download status for $filename: $status');
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
    // print('Ensuring model ready: ${spec.name}');

    // Check if target model is already ready
    if (await isModelInstalled(spec)) {
      // print('Model ${spec.name} already ready');
      return;
    }

    // Handle model switching with replace policy
    await _handleModelSwitching(spec);

    // Route based on URL scheme
    await _routeModelByScheme(spec);
  }

  /// Routes model handling based on URL scheme
  static Future<void> _routeModelByScheme(ModelSpec spec) async {
    if (spec is InferenceModelSpec) {
      final modelUri = Uri.parse(spec.modelUrl);

      switch (modelUri.scheme) {
        case 'https':
        case 'http':
          await _handleNetworkModel(spec);
          break;
        case 'asset':
          await _handleAssetModel(spec);
          break;
        case 'file':
          await _handleExternalModel(spec);
          break;
        case '': // Schemeless URLs - treat as assets for backward compatibility
          await _handleAssetModel(spec);
          break;
        default:
          throw ModelStorageException(
            'Unsupported URL scheme: "${modelUri.scheme}". Supported: https, http, asset, file, or schemeless (treated as asset)',
            null,
            'routeModelByScheme'
          );
      }
    } else if (spec is EmbeddingModelSpec) {
      final modelUri = Uri.parse(spec.modelUrl);

      switch (modelUri.scheme) {
        case 'https':
        case 'http':
          await _handleNetworkModel(spec);
          break;
        case 'asset':
          await _handleAssetModel(spec);
          break;
        case 'file':
          await _handleExternalModel(spec);
          break;
        case '': // Schemeless URLs - treat as assets for backward compatibility
          await _handleAssetModel(spec);
          break;
        default:
          throw ModelStorageException(
            'Unsupported URL scheme: "${modelUri.scheme}". Supported: https, http, asset, file, or schemeless (treated as asset)',
            null,
            'routeModelByScheme'
          );
      }
    }
  }

  /// Handles network-based models (existing logic)
  static Future<void> _handleNetworkModel(ModelSpec spec) async {
    // print('Downloading network model: ${spec.name}');
    await downloadModel(spec);
  }

  /// Handles asset-based models
  static Future<void> _handleAssetModel(ModelSpec spec) async {
    // print('Installing asset model: ${spec.name}');

    try {
      // Process each file in the spec
      for (final file in spec.files) {
        final assetPath = file.url.replaceFirst('asset://', ''); // Remove asset:// prefix
        final targetPath = await ModelFileSystemManager.getModelFilePath(file.filename);

        await _copyFromAsset(assetPath, targetPath, file.filename);

        // Register in unified system
        // TODO: Need to implement proper file registration for assets
      }

      // print('Asset model ${spec.name} installed successfully');
    } catch (e) {
      throw ModelStorageException(
        'Failed to install asset model: ${spec.name}',
        e,
        '_handleAssetModel'
      );
    }
  }

  /// Handles external file-based models
  static Future<void> _handleExternalModel(ModelSpec spec) async {
    // print('Registering external model: ${spec.name}');

    try {
      // Process each file in the spec
      for (final file in spec.files) {
        final filePath = Uri.parse(file.url).path; // Remove file:// prefix
        final targetFile = File(filePath);

        // Validate file exists
        if (!await targetFile.exists()) {
          throw ModelStorageException(
            'External model file not found: $filePath',
            null,
            '_handleExternalModel'
          );
        }

        // Register without copying - just record the external path
        await ModelPreferencesManager.registerExternalFile(
          file.filename,
          filePath,
          spec.type
        );
      }

      // print('External model ${spec.name} registered successfully');
    } catch (e) {
      throw ModelStorageException(
        'Failed to register external model: ${spec.name}',
        e,
        '_handleExternalModel'
      );
    }
  }

  /// Copies file from Flutter assets to target path
  static Future<void> _copyFromAsset(String assetPath, String targetPath, String filename) async {
    try {
      // Load asset data
      final assetData = await rootBundle.load(assetPath);
      final bytes = assetData.buffer.asUint8List();

      // Ensure target directory exists
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);

      // Write to target location
      await targetFile.writeAsBytes(bytes);

      // print('Copied asset $assetPath -> $targetPath (${bytes.length} bytes)');
    } catch (e) {
      throw ModelStorageException(
        'Failed to copy asset: $assetPath',
        e,
        '_copyFromAsset'
      );
    }
  }

    // print('Model ${spec.name} is now ready');
  // NOTE: This closing brace was moved to end of file

  /// Handles model switching according to replace policy
  static Future<void> _handleModelSwitching(ModelSpec spec) async {
    final currentSpec = await ModelPreferencesManager.loadModelSpec(spec.type, spec.name);

    if (currentSpec != null && currentSpec.name != spec.name) {
      if (spec.replacePolicy == ModelReplacePolicy.replace) {
        // print('Policy-based replacement: cleaning up ALL ${spec.type.name} models for new model: ${spec.name}');

        // Clean up ALL tasks and files of this type
        await cleanupAllTasksOfType(spec.type);

        // TODO: Also delete the specific old model files
        // await deleteModel(currentSpec);

        // print('Completed policy-based cleanup for ${spec.type.name} models');
      } else {
        // print('Policy-based keep: keeping old model ${currentSpec.name} alongside new model: ${spec.name}');
        // For keep policy, don't delete anything - multiple models are allowed
      }
    } else if (spec.replacePolicy == ModelReplacePolicy.replace) {
      // Even if no specific current model, clean up ALL tasks of this type to ensure fresh start
      // print('Policy-based replacement: cleaning up ALL existing ${spec.type.name} tasks for fresh start');
      await cleanupAllTasksOfType(spec.type);
    }
  }

  /// Performs cleanup of orphaned files and invalid resume states
  static Future<void> performCleanup() async {
    try {
      // print('Performing comprehensive model cleanup...');

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

      // print('Comprehensive model cleanup completed');
    } catch (e) {
      // print('Model cleanup failed: $e');
    }
  }

  /// Clean up task registry using policy-based approach
  static Future<void> _cleanupTaskRegistry() async {
    try {
      // print('Cleaning up task registry with policy-based approach...');

      final allTasks = await DownloadTaskRegistry.getAllRegisteredTasks();
      final toRemove = <String>[];
      final downloader = FileDownloader();

      for (final entry in allTasks.entries) {
        final filename = entry.key;
        final taskId = entry.value;

        // Determine model type and default policy
        final modelType = _detectModelType(filename);
        final defaultPolicy = _getDefaultPolicyForType(modelType);

        // print('Checking task $filename (type: ${modelType.name}, policy: ${defaultPolicy.name})');

        if (defaultPolicy == ModelReplacePolicy.replace) {
          // INFERENCE: Remove all except actively downloading
          final isActive = await _isActivelyDownloading(taskId, downloader);
          if (!isActive) {
            toRemove.add(filename);
            // print('Removing non-active inference task: $filename');
          } else {
            // print('Keeping active inference task: $filename');
          }
        } else {
          // EMBEDDING: Remove only invalid states (keep multiple models)
          final resumeStatus = await ResumeChecker.checkResumeStatus(filename);
          if (_isInvalidState(resumeStatus)) {
            toRemove.add(filename);
            // print('Removing invalid embedding task: $filename (status: ${resumeStatus.name})');
          } else {
            // print('Keeping valid embedding task: $filename (status: ${resumeStatus.name})');
          }
        }
      }

      if (toRemove.isNotEmpty) {
        await DownloadTaskRegistry.unregisterTasks(toRemove);
        // print('Policy-based cleanup: removed ${toRemove.length} task registry entries');
      } else {
        // print('Policy-based cleanup: no entries to remove');
      }
    } catch (e) {
      // print('Task registry cleanup failed: $e');
    }
  }

  /// Clean up background_downloader resources
  static Future<void> _cleanupBackgroundDownloaderResources() async {
    try {
      // print('Cleaning up background_downloader resources...');

      final downloader = FileDownloader();

      // Reset all tasks in our download group (cancels active tasks)
      await downloader.reset(group: downloadGroup);
      // Reset background_downloader tasks

    } catch (e) {
      // print('Background_downloader cleanup failed: $e');
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

  /// Detect model type from filename
  static ModelManagementType _detectModelType(String filename) {
    final extension = filename.split('.').last.toLowerCase();

    switch (extension) {
      case 'tflite':
      case 'json':
        // Embedding models typically use .tflite + .json
        return ModelManagementType.embedding;
      case 'bin':
      case 'task':
      case 'gguf':
        // Inference models typically use .bin, .task, .gguf
        return ModelManagementType.inference;
      default:
        // Default to inference for unknown types
        // print('Unknown file extension: $extension, defaulting to inference');
        return ModelManagementType.inference;
    }
  }

  /// Get default policy for model type
  static ModelReplacePolicy _getDefaultPolicyForType(ModelManagementType type) {
    switch (type) {
      case ModelManagementType.inference:
        return ModelReplacePolicy.replace; // Inference: replace old models
      case ModelManagementType.embedding:
        return ModelReplacePolicy.keep;    // Embedding: keep multiple models
    }
  }

  /// Check if a task is actively downloading
  static Future<bool> _isActivelyDownloading(String taskId, FileDownloader downloader) async {
    try {
      // Get all active tasks from background_downloader
      final activeTasks = await downloader.allTasks();

      // Check if our taskId is in the active list
      for (final task in activeTasks) {
        if (task.taskId == taskId) {
          // Check if task is in a downloading state
          final taskRecord = await downloader.database.recordForId(taskId);
          if (taskRecord != null) {
            switch (taskRecord.status) {
              case TaskStatus.enqueued:
              case TaskStatus.running:
              case TaskStatus.paused:
                // print('Task $taskId is actively downloading (status: ${taskRecord.status.name})');
                return true;
              default:
                break;
            }
          }
        }
      }

      // print('Task $taskId is not actively downloading');
      return false;
    } catch (e) {
      // print('Error checking if task $taskId is active: $e');
      return false; // Assume not active on error
    }
  }

  /// Check if resume status represents an invalid state
  static bool _isInvalidState(ResumeStatus status) {
    switch (status) {
      case ResumeStatus.cannotResume:
      case ResumeStatus.error:
      case ResumeStatus.fileNotFound:
        return true;
      case ResumeStatus.canResume:
      case ResumeStatus.fileComplete:
      case ResumeStatus.noTask:
        return false;
    }
  }

  /// Clean up all tasks and files of a specific type (for model switching)
  static Future<void> cleanupAllTasksOfType(ModelManagementType type) async {
    try {
      // print('Cleaning up all tasks of type: ${type.name}');

      final allTasks = await DownloadTaskRegistry.getAllRegisteredTasks();
      final toRemove = <String>[];

      for (final entry in allTasks.entries) {
        final filename = entry.key;
        final modelType = _detectModelType(filename);

        if (modelType == type) {
          toRemove.add(filename);
          // Also try to delete the partial file
          try {
            await ModelFileSystemManager.deleteModelFile(filename);
            // print('Deleted partial file: $filename');
          } catch (e) {
            // print('Could not delete partial file $filename: $e');
          }
        }
      }

      if (toRemove.isNotEmpty) {
        await DownloadTaskRegistry.unregisterTasks(toRemove);
        // print('Cleaned up ${toRemove.length} tasks of type ${type.name}');
      }

      // Also reset any background_downloader tasks for this type
      final downloader = FileDownloader();
      try {
        await downloader.reset(group: downloadGroup);
        // Reset background_downloader tasks for type ${type.name}
      } catch (e) {
        // print('Failed to reset background_downloader tasks: $e');
      }

    } catch (e) {
      // print('Failed to cleanup tasks of type ${type.name}: $e');
    }
  }
}