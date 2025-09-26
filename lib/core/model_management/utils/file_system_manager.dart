part of '../../../mobile/flutter_gemma_mobile.dart';

/// Unified file system operations for model management
class ModelFileSystemManager {
  static const List<String> _supportedExtensions = ['.task', '.bin', '.json', '.tflite'];
  static const int _defaultMinSizeBytes = 1024 * 1024; // 1MB

  /// Corrects Android path from /data/user/0/ to /data/data/ for proper file access
  static String getCorrectedPath(String originalPath, String filename) {
    // Check if this is the problematic Android path format
    if (originalPath.contains('/data/user/0/')) {
      // Replace with the correct Android app data path
      final correctedPath = originalPath.replaceFirst('/data/user/0/', '/data/data/');
      return '$correctedPath/$filename';
    }
    // For other platforms or already correct paths, use the original
    return '$originalPath/$filename';
  }

  /// Validates if a file exists and meets minimum size requirements
  static Future<bool> isFileValid(
    String filePath, {
    int minSizeBytes = _defaultMinSizeBytes,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return false;
      }

      // Basic size check - model files should be at least the minimum size
      final sizeInBytes = await file.length();
      if (sizeInBytes < minSizeBytes) {
        debugPrint('File $filePath too small: $sizeInBytes bytes (minimum: $minSizeBytes)');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error validating file $filePath: $e');
      return false;
    }
  }

  /// Gets the full file path for a model file with Android path correction
  static Future<String> getModelFilePath(String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    return getCorrectedPath(directory.path, filename);
  }

  /// Smart cleanup: removes orphaned files immediately, keeps potential resume files
  static Future<void> cleanupOrphanedFiles({
    required List<String> protectedFiles,
    List<String>? supportedExtensions,
    bool enableResumeDetection = false,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final extensions = supportedExtensions ?? _supportedExtensions;

      // Get all supported model files in directory
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => extensions.any((ext) => file.path.endsWith(ext)))
          .toList();

      for (final file in files) {
        final fileName = file.path.split('/').last;

        // NEVER delete files that are protected
        if (protectedFiles.contains(fileName)) {
          debugPrint('Keeping protected file: $fileName');
          continue;
        }

        // Check if this could be a partial download worth keeping for resume
        if (enableResumeDetection && await _shouldKeepForResume(file)) {
          debugPrint('Keeping potential partial download: $fileName');
          continue;
        }

        // File is not protected and not resumable → delete immediately
        debugPrint('Removing orphaned file: $fileName');
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to cleanup orphaned files: $e');
    }
  }

  /// Determines if a file should be kept for potential resume
  static Future<bool> _shouldKeepForResume(File file) async {
    try {
      final size = await file.length();
      final extension = file.path.split('.').last.toLowerCase();

      // Empty files are definitely garbage
      if (size == 0) return false;

      // Check if file size suggests it's a partial download
      switch (extension) {
        case 'task':
        case 'bin':
          // Inference models usually >50MB, if <50MB likely partial
          return size < 50 * 1024 * 1024;
        case 'tflite':
          // Embedding models usually >5MB, if <5MB likely partial
          return size < 5 * 1024 * 1024;
        case 'json':
          // Tokenizer files are usually <1MB, if >10MB likely partial of something else
          return size > 10 * 1024 * 1024;
        default:
          return false;
      }
    } catch (e) {
      debugPrint('Failed to analyze file for resume: $e');
      return false;
    }
  }

  /// Safely deletes a model file
  static Future<void> deleteModelFile(String filename) async {
    try {
      final filePath = await getModelFilePath(filename);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        debugPrint('Deleted model file: $filename');
      }
    } catch (e) {
      debugPrint('Failed to delete model file $filename: $e');
      throw ModelStorageException(
        'Failed to delete model file: $filename',
        e,
        'delete',
      );
    }
  }

  /// Ensures a directory exists, creating it if necessary
  static Future<void> ensureDirectoryExists(String dirPath) async {
    try {
      final directory = Directory(dirPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to create directory $dirPath: $e');
      throw ModelStorageException(
        'Failed to create directory: $dirPath',
        e,
        'create_directory',
      );
    }
  }

  /// Gets file size in bytes, returns 0 if file doesn't exist
  static Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      debugPrint('Failed to get file size for $filePath: $e');
      return 0;
    }
  }

  /// Validates all files in a model specification
  static Future<bool> validateModelFiles(ModelSpec spec) async {
    for (final file in spec.files) {
      final filePath = await getModelFilePath(file.filename);
      final minSize = file.extension == '.json' ? 1024 : _defaultMinSizeBytes; // Smaller requirement for JSON files

      if (!await isFileValid(filePath, minSizeBytes: minSize)) {
        debugPrint('Model file validation failed: ${file.filename}');
        return false;
      }
    }
    return true;
  }

  /// Cleans up failed download files for a model specification
  static Future<void> cleanupFailedDownload(ModelSpec spec) async {
    debugPrint('Cleaning up failed download for model: ${spec.name}');

    for (final file in spec.files) {
      try {
        final filePath = await getModelFilePath(file.filename);
        final fileObj = File(filePath);
        if (await fileObj.exists()) {
          await fileObj.delete();
          debugPrint('Cleaned up partial file: ${file.filename}');
        }
      } catch (e) {
        debugPrint('Failed to cleanup file ${file.filename}: $e');
      }
    }
  }
}