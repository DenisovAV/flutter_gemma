part of '../../../mobile/flutter_gemma_mobile.dart';

/// Status of resume possibility for a file
enum ResumeStatus {
  /// File can be resumed - has taskId and server supports resume
  canResume,

  /// File exists but resume is not possible (server/task issues)
  cannotResume,

  /// No active download task for this file
  noTask,

  /// File is already complete and valid
  fileComplete,

  /// File doesn't exist at all
  fileNotFound,

  /// Error occurred during resume check
  error,
}

/// Smart resume detection utility
///
/// This class checks if downloads can be properly resumed by validating:
/// 1. File existence and state
/// 2. Task registry mapping
/// 3. background_downloader resume capability
/// 4. Server support for ranges
class ResumeChecker {
  static final _downloader = FileDownloader();

  /// Check resume status for a single file
  ///
  /// [filename] - The model filename (e.g., 'gemma-2b-it.bin')
  /// Returns [ResumeStatus] indicating what action should be taken
  static Future<ResumeStatus> checkResumeStatus(String filename) async {
    try {
      debugPrint('ResumeChecker: Checking resume status for $filename');

      // 1. Check if file exists and get its state
      final filePath = await ModelFileSystemManager.getModelFilePath(filename);
      final file = File(filePath);

      debugPrint('ResumeChecker: Checking file path: $filePath');
      final fileExists = await file.exists();
      debugPrint('ResumeChecker: File exists: $fileExists for $filename');

      if (!fileExists) {
        debugPrint('ResumeChecker: File not found: $filename at path: $filePath');
        return ResumeStatus.fileNotFound;
      }

      // 2. Check if file is already complete
      final fileSize = await file.length();
      final isValid = await ModelFileSystemManager.isFileValid(filePath);

      debugPrint('ResumeChecker: File size: $fileSize, isValid: $isValid for $filename');

      if (isValid && fileSize > 0) {
        debugPrint('ResumeChecker: File is already complete: $filename');
        return ResumeStatus.fileComplete;
      }

      // 3. Check if we have a registered task for this file
      final taskId = await DownloadTaskRegistry.getTaskId(filename);
      debugPrint('ResumeChecker: TaskId for $filename: $taskId');

      if (taskId == null) {
        debugPrint('ResumeChecker: No registered task for $filename - returning noTask status');
        return ResumeStatus.noTask;
      }

      // 4. Create a task object to check resume capability
      final task = DownloadTask(
        taskId: taskId,
        url: 'placeholder', // We don't need real URL for resume check
        filename: filename,
        group: UnifiedDownloadEngine.downloadGroup,
      );

      // 5. Check if background_downloader thinks this task can be resumed
      final canResume = await _downloader.taskCanResume(task);
      if (canResume) {
        debugPrint('ResumeChecker: File can be resumed: $filename');
        return ResumeStatus.canResume;
      } else {
        debugPrint('ResumeChecker: File cannot be resumed: $filename');
        return ResumeStatus.cannotResume;
      }

    } catch (e) {
      debugPrint('ResumeChecker: Error checking resume status for $filename: $e');
      return ResumeStatus.error;
    }
  }

  /// Check resume status for all files in a model specification
  ///
  /// [spec] - The model specification to check
  /// Returns map of filename -> ResumeStatus for each file
  static Future<Map<String, ResumeStatus>> checkModelResume(ModelSpec spec) async {
    debugPrint('ResumeChecker: Checking resume status for model: ${spec.name}');

    final results = <String, ResumeStatus>{};

    for (final file in spec.files) {
      final status = await checkResumeStatus(file.filename);
      results[file.filename] = status;
    }

    final summary = _summarizeResumeResults(results);
    debugPrint('ResumeChecker: Model ${spec.name} resume summary: $summary');

    return results;
  }

  /// Get resume recommendations for a model
  ///
  /// [spec] - The model specification to analyze
  /// Returns structured recommendations for each file
  static Future<Map<String, ResumeRecommendation>> getResumeRecommendations(ModelSpec spec) async {
    final statuses = await checkModelResume(spec);
    final recommendations = <String, ResumeRecommendation>{};

    for (final entry in statuses.entries) {
      final filename = entry.key;
      final status = entry.value;

      recommendations[filename] = switch (status) {
        ResumeStatus.canResume => ResumeRecommendation(
            action: ResumeAction.resume,
            reason: 'File can be resumed from partial state',
          ),
        ResumeStatus.fileComplete => ResumeRecommendation(
            action: ResumeAction.skip,
            reason: 'File is already complete and valid',
          ),
        ResumeStatus.cannotResume => ResumeRecommendation(
            action: ResumeAction.restart,
            reason: 'Resume not possible, should delete and restart',
          ),
        ResumeStatus.noTask => ResumeRecommendation(
            action: ResumeAction.restart,
            reason: 'No registered task, should start fresh download',
          ),
        ResumeStatus.fileNotFound => ResumeRecommendation(
            action: ResumeAction.download,
            reason: 'File not found, should start new download',
          ),
        ResumeStatus.error => ResumeRecommendation(
            action: ResumeAction.restart,
            reason: 'Error during resume check, safer to restart',
          ),
      };
    }

    return recommendations;
  }

  /// Clean up invalid resume states for a model
  ///
  /// [spec] - The model specification to clean
  /// Returns the number of cleaned up files
  static Future<int> cleanupInvalidResumeStates(ModelSpec spec) async {
    debugPrint('ResumeChecker: Cleaning up invalid resume states for ${spec.name}');

    final statuses = await checkModelResume(spec);
    int cleanedCount = 0;

    for (final entry in statuses.entries) {
      final filename = entry.key;
      final status = entry.value;

      switch (status) {
        case ResumeStatus.cannotResume:
        case ResumeStatus.error:
          // Delete partial file and unregister task
          try {
            await ModelFileSystemManager.deleteModelFile(filename);
            await DownloadTaskRegistry.unregisterTask(filename);
            cleanedCount++;
            debugPrint('ResumeChecker: Cleaned up invalid resume state for $filename');
          } catch (e) {
            debugPrint('ResumeChecker: Failed to cleanup $filename: $e');
          }
          break;

        case ResumeStatus.noTask:
          // File exists but no task - check if it's partial
          try {
            final filePath = await ModelFileSystemManager.getModelFilePath(filename);
            final isValid = await ModelFileSystemManager.isFileValid(filePath);

            if (!isValid) {
              // Partial file without task - delete it
              await ModelFileSystemManager.deleteModelFile(filename);
              cleanedCount++;
              debugPrint('ResumeChecker: Removed orphaned partial file: $filename');
            }
          } catch (e) {
            debugPrint('ResumeChecker: Error checking orphaned file $filename: $e');
          }
          break;

        default:
          // Other statuses don't need cleanup
          break;
      }
    }

    debugPrint('ResumeChecker: Cleaned up $cleanedCount files for model ${spec.name}');
    return cleanedCount;
  }

  /// Get statistics about resume states across all registered tasks
  static Future<Map<String, dynamic>> getResumeStatistics() async {
    try {
      final allTasks = await DownloadTaskRegistry.getAllRegisteredTasks();
      final stats = <String, int>{
        'totalRegistered': allTasks.length,
        'canResume': 0,
        'cannotResume': 0,
        'noTask': 0,
        'fileComplete': 0,
        'fileNotFound': 0,
        'error': 0,
      };

      for (final filename in allTasks.keys) {
        final status = await checkResumeStatus(filename);
        final statusName = status.name;
        stats[statusName] = (stats[statusName] ?? 0) + 1;
      }

      return {
        'summary': stats,
        'lastChecked': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'lastChecked': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Helper to summarize resume results
  static String _summarizeResumeResults(Map<String, ResumeStatus> results) {
    final counts = <ResumeStatus, int>{};
    for (final status in results.values) {
      counts[status] = (counts[status] ?? 0) + 1;
    }

    return counts.entries
        .map((e) => '${e.key.name}: ${e.value}')
        .join(', ');
  }
}

/// Recommended action based on resume status
enum ResumeAction {
  /// Resume the existing download
  resume,

  /// Skip download (file is complete)
  skip,

  /// Delete partial file and restart download
  restart,

  /// Start new download (file not found)
  download,
}

/// Resume recommendation for a specific file
class ResumeRecommendation {
  final ResumeAction action;
  final String reason;

  const ResumeRecommendation({
    required this.action,
    required this.reason,
  });

  @override
  String toString() => '${action.name}: $reason';
}