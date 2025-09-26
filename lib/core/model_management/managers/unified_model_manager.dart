part of '../../../mobile/flutter_gemma_mobile.dart';

/// Main unified model manager that orchestrates all model operations
class MobileModelManager extends ModelFileManager {
  bool _isInitialized = false;

  /// Initializes the unified model manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
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

  /// Internal method for ModelSpec-based operations
  Future<void> _ensureModelReadySpec(ModelSpec spec) async {
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

  /// Ensures a model is ready for use, handling all necessary operations
  @override
  Future<void> ensureModelReady(String filename, String url) async {
    // Create spec from legacy parameters and delegate to internal method
    final spec = InferenceModelSpec(
      name: filename,
      modelUrl: url,
    );
    await _ensureModelReadySpec(spec);
    // Set as current active model after ensuring it's ready
    _currentActiveModel = spec;
  }

  /// Downloads a model with progress tracking
  @override
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
  @override
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
  @override
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
  @override
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
  @override
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
  @override
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
  @override
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
  @override
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
  @override
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
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.replace,
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


  // === Legacy Asset Loading Methods Implementation ===

  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError("Asset model loading is not supported in release builds");
    }

    await _ensureInitialized();

    final spec = InferenceModelSpec(
      name: path.split('/').last.replaceAll('.bin', '').replaceAll('.task', ''),
      modelUrl: 'asset://$path',
      loraUrl: loraPath != null ? 'asset://$loraPath' : null,
    );

    await _ensureModelReadySpec(spec);
  }

  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) async* {
    if (kReleaseMode) {
      throw UnsupportedError("Asset model loading is not supported in release builds");
    }

    await _ensureInitialized();

    final spec = InferenceModelSpec(
      name: path.split('/').last.replaceAll('.bin', '').replaceAll('.task', ''),
      modelUrl: 'asset://$path',
      loraUrl: loraPath != null ? 'asset://$loraPath' : null,
    );

    // Since assets are copied instantly, we'll simulate progress
    for (int progress = 0; progress <= 100; progress += 10) {
      yield progress;
      if (progress < 100) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    await _ensureModelReadySpec(spec);
  }

  // === Legacy Direct Path Methods Implementation ===

  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    await _ensureInitialized();

    final spec = InferenceModelSpec(
      name: path.split('/').last.replaceAll('.bin', '').replaceAll('.task', ''),
      modelUrl: 'file://$path',
      loraUrl: loraPath != null ? 'file://$loraPath' : null,
    );

    await _ensureModelReadySpec(spec);
    _currentActiveModel = spec;
  }

  @override
  Future<void> clearModelCache() async {
    await _ensureInitialized();
    _currentActiveModel = null;
    debugPrint('Model cache cleared');
  }

  // === Legacy LoRA Management Methods Implementation ===

  ModelSpec? _currentActiveModel;

  /// Gets the currently active model specification
  ModelSpec? get currentActiveModel => _currentActiveModel;

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _ensureInitialized();

    if (_currentActiveModel == null) {
      throw Exception('No active model to apply LoRA weights to. Use setModelPath first.');
    }

    // Create updated spec with new LoRA path
    late ModelSpec updatedSpec;
    if (_currentActiveModel is InferenceModelSpec) {
      final current = _currentActiveModel as InferenceModelSpec;
      updatedSpec = InferenceModelSpec(
        name: current.name,
        modelUrl: current.modelUrl,
        loraUrl: path.startsWith('/') ? 'file://$path' : path,
        replacePolicy: current.replacePolicy,
      );
    } else {
      throw Exception('LoRA weights can only be applied to inference models');
    }

    await _ensureModelReadySpec(updatedSpec);
    _currentActiveModel = updatedSpec;
  }

  @override
  Future<void> deleteLoraWeights() async {
    await _ensureInitialized();

    if (_currentActiveModel == null) {
      throw Exception('No active model to remove LoRA weights from');
    }

    // Create updated spec without LoRA
    late ModelSpec updatedSpec;
    if (_currentActiveModel is InferenceModelSpec) {
      final current = _currentActiveModel as InferenceModelSpec;
      updatedSpec = InferenceModelSpec(
        name: current.name,
        modelUrl: current.modelUrl,
        loraUrl: null, // Remove LoRA
        replacePolicy: current.replacePolicy,
      );
    } else {
      throw Exception('LoRA weights can only be removed from inference models');
    }

    await _ensureModelReadySpec(updatedSpec);
    _currentActiveModel = updatedSpec;
  }

  // === Legacy Model Management Implementation ===

  @override
  Future<void> deleteCurrentModel() async {
    await _ensureInitialized();

    if (_currentActiveModel != null) {
      await deleteModel(_currentActiveModel!);
      _currentActiveModel = null;
    }
  }

  /// Gets storage statistics
  @override
  Future<Map<String, int>> getStorageStats() async {
    await _ensureInitialized();

    try {
      final stats = <String, int>{};

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