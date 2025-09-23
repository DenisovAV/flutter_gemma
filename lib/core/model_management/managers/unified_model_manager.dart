part of '../../../mobile/flutter_gemma_mobile.dart';

/// Main unified model manager that orchestrates all model operations
class UnifiedModelManager {
  bool _isInitialized = false;

  /// Initializes the unified model manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Migrate old preferences if necessary
      await ModelPreferencesManager.migrateOldPreferences();

      // Perform smart cleanup with resume detection
      await UnifiedDownloadEngine.performCleanup();

      _isInitialized = true;
      debugPrint('UnifiedModelManager initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize UnifiedModelManager: $e');
      throw ModelStorageException(
        'Failed to initialize model manager',
        e,
        'initialize',
      );
    }
  }

  /// Ensures a model is ready for use, handling all necessary operations
  Future<void> ensureModelReady(ModelSpec spec) async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Ensuring model ready - ${spec.name}');

    try {
      await UnifiedDownloadEngine.ensureModelReady(spec);
      debugPrint('UnifiedModelManager: Model ${spec.name} is ready');
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to ensure model ready - ${spec.name}: $e');
      rethrow;
    }
  }

  /// Downloads a model with progress tracking
  Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Starting download with progress - ${spec.name}');

    try {
      yield* UnifiedDownloadEngine.downloadModelWithProgress(spec, token: token);
      debugPrint('UnifiedModelManager: Download completed - ${spec.name}');
    } catch (e) {
      debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
      rethrow;
    }
  }

  /// Downloads a model without progress tracking
  Future<void> downloadModel(ModelSpec spec, {String? token}) async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Starting download - ${spec.name}');

    try {
      await UnifiedDownloadEngine.downloadModel(spec, token: token);
      debugPrint('UnifiedModelManager: Download completed - ${spec.name}');
    } catch (e) {
      debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
      rethrow;
    }
  }

  /// Checks if a model is installed and valid
  Future<bool> isModelInstalled(ModelSpec spec) async {
    await _ensureInitialized();

    try {
      final result = await UnifiedDownloadEngine.isModelInstalled(spec);
      debugPrint('UnifiedModelManager: Model ${spec.name} installed: $result');
      return result;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to check if model installed - ${spec.name}: $e');
      return false;
    }
  }

  /// Deletes a model and all its files
  Future<void> deleteModel(ModelSpec spec) async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Deleting model - ${spec.name}');

    try {
      await UnifiedDownloadEngine.deleteModel(spec);
      debugPrint('UnifiedModelManager: Model deleted - ${spec.name}');
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to delete model - ${spec.name}: $e');
      rethrow;
    }
  }

  /// Gets all installed models for a specific type
  Future<List<String>> getInstalledModels(ModelManagementType type) async {
    await _ensureInitialized();

    try {
      final files = await ModelPreferencesManager.getInstalledFiles(type);
      debugPrint('UnifiedModelManager: Found ${files.length} installed files for type $type');
      return files;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to get installed models for type $type: $e');
      return [];
    }
  }

  /// Checks if ANY model of the given type is installed
  Future<bool> isAnyModelInstalled(ModelManagementType type) async {
    await _ensureInitialized();

    try {
      return await ModelPreferencesManager.isAnyModelInstalled(type);
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to check if any model is installed for type $type: $e');
      return false;
    }
  }

  /// Performs cleanup of orphaned files
  Future<void> performCleanup() async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Performing cleanup');

    try {
      await UnifiedDownloadEngine.performCleanup();
      debugPrint('UnifiedModelManager: Cleanup completed');
    } catch (e) {
      debugPrint('UnifiedModelManager: Cleanup failed: $e');
      // Don't rethrow - cleanup failures should not break the app
    }
  }

  /// Validates all files for a model specification
  Future<bool> validateModel(ModelSpec spec) async {
    await _ensureInitialized();

    try {
      final result = await ModelFileSystemManager.validateModelFiles(spec);
      debugPrint('UnifiedModelManager: Model ${spec.name} validation: $result');
      return result;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to validate model - ${spec.name}: $e');
      return false;
    }
  }

  /// Gets the file paths for an installed model
  Future<Map<String, String>?> getModelFilePaths(ModelSpec spec) async {
    await _ensureInitialized();

    try {
      if (!await isModelInstalled(spec)) {
        return null;
      }

      final filePaths = <String, String>{};

      for (final file in spec.files) {
        final path = await ModelFileSystemManager.getModelFilePath(file.filename);
        filePaths[file.prefsKey] = path;
      }

      return filePaths;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to get file paths for ${spec.name}: $e');
      return null;
    }
  }

  /// Creates an inference model specification from parameters
  static InferenceModelSpec createInferenceSpec({
    required String name,
    required String modelUrl,
    String? loraUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) {
    return InferenceModelSpec(
      name: name,
      modelUrl: modelUrl,
      loraUrl: loraUrl,
      replacePolicy: replacePolicy,
    );
  }

  /// Creates an embedding model specification from parameters
  static EmbeddingModelSpec createEmbeddingSpec({
    required String name,
    required String modelUrl,
    required String tokenizerUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) {
    return EmbeddingModelSpec(
      name: name,
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
      replacePolicy: replacePolicy,
    );
  }

  /// Ensures the manager is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Gets storage statistics
  Future<Map<String, dynamic>> getStorageStats() async {
    await _ensureInitialized();

    try {
      final stats = <String, dynamic>{};

      // Get protected files
      final protectedFiles = await ModelPreferencesManager.getAllProtectedFiles();
      stats['protectedFiles'] = protectedFiles.length;

      // Calculate total size of protected files
      int totalSize = 0;
      for (final filename in protectedFiles) {
        final path = await ModelFileSystemManager.getModelFilePath(filename);
        totalSize += await ModelFileSystemManager.getFileSize(path);
      }
      stats['totalSizeBytes'] = totalSize;
      stats['totalSizeMB'] = (totalSize / (1024 * 1024)).round();

      // Get counts by type
      final inferenceFiles = await ModelPreferencesManager.getInstalledFiles(ModelManagementType.inference);
      final embeddingFiles = await ModelPreferencesManager.getInstalledFiles(ModelManagementType.embedding);

      stats['inferenceModels'] = inferenceFiles.length;
      stats['embeddingModels'] = embeddingFiles.length ~/ 2; // Each embedding model has 2 files

      return stats;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to get storage stats: $e');
      return {
        'protectedFiles': 0,
        'totalSizeBytes': 0,
        'totalSizeMB': 0,
        'inferenceModels': 0,
        'embeddingModels': 0,
      };
    }
  }
}