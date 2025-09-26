part of '../../../mobile/flutter_gemma_mobile.dart';

/// Base enumeration for different model management types
enum ModelManagementType {
  inference,
  embedding,
}

// ModelReplacePolicy уже определен в model_file_manager_interface.dart

/// Represents a single file that belongs to a model
abstract class ModelFile {
  /// URL from which this file can be downloaded
  String get url;

  /// Local filename for this file
  String get filename;

  /// SharedPreferences key for storing this file's installation status
  String get prefsKey;

  /// Whether this file is required for the model to function
  bool get isRequired;

  /// File extension for validation purposes
  String get extension => filename.split('.').last;
}

/// Base specification for any model (inference or embedding)
abstract class ModelSpec {
  /// Type of this model
  ModelManagementType get type;

  /// Human-readable name for this model
  String get name;

  /// All files that belong to this model
  List<ModelFile> get files;

  /// Policy for replacing old models
  ModelReplacePolicy get replacePolicy;

  /// Whether this model specification is valid
  bool get isValid => files.isNotEmpty && files.any((f) => f.isRequired);
}

/// Progress information for model downloads
class DownloadProgress {
  final int currentFileIndex;
  final int totalFiles;
  final int currentFileProgress; // 0-100
  final String currentFileName;

  const DownloadProgress({
    required this.currentFileIndex,
    required this.totalFiles,
    required this.currentFileProgress,
    required this.currentFileName,
  });

  /// Overall progress across all files (0-100)
  int get overallProgress {
    if (totalFiles == 0) return 0;

    final completedFiles = currentFileIndex;
    final currentFileWeight = currentFileProgress / 100.0;
    final totalProgress = (completedFiles + currentFileWeight) / totalFiles;

    return (totalProgress * 100).round().clamp(0, 100);
  }

  @override
  String toString() => 'DownloadProgress(file $currentFileIndex/$totalFiles, $currentFileProgress%, $currentFileName)';
}