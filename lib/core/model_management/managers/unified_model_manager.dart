part of '../../../mobile/flutter_gemma_mobile.dart';

/// Main unified model manager that orchestrates all model operations
class MobileModelManager extends ModelFileManager {
  bool _isInitialized = false;

  /// Initializes the unified model manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
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
      await _ensureModelReady(spec);
      debugPrint('UnifiedModelManager: Model ${spec.name} is ready');
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to ensure model ready - ${spec.name}: $e');
      rethrow;
    }
  }

  /// Ensures a model is ready, applying replace policy
  /// Delegates to Modern API handlers via ServiceRegistry
  Future<void> _ensureModelReady(ModelSpec spec) async {
    debugPrint('🔍 Ensuring model ready: ${spec.name}');
    debugPrint('🔍 Model source type: ${spec.files.first.source.runtimeType}');

    // Check if already installed
    final installed = await _isModelInstalled(spec);
    debugPrint('🔍 isModelInstalled returned: $installed');

    if (installed) {
      debugPrint('✅ Model ${spec.name} already ready (skipping installation)');
      return;
    }

    debugPrint('📥 Model not installed, proceeding with installation...');

    // Handle model switching with replace policy
    await _handleModelSwitching(spec);

    // Route to ServiceRegistry handlers
    await _routeModelBySource(spec);
  }

  /// Routes model handling to Modern API handlers via ServiceRegistry
  Future<void> _routeModelBySource(ModelSpec spec) async {
    // Install ALL files from spec (important for multi-file models like embedding)
    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;

    for (final file in spec.files) {
      debugPrint('🔀 Routing file: ${file.filename}, source type: ${file.source.runtimeType}');

      try {
        final handler = handlerRegistry.getHandler(file.source);

        if (handler == null) {
          throw ModelStorageException(
            'No handler registered for source type: ${file.source.runtimeType}',
            null,
            '_routeModelBySource',
          );
        }

        await handler.install(file.source);
        debugPrint('✅ File installed: ${file.filename} via Modern handler: ${file.source.runtimeType}');
      } catch (e) {
        throw ModelStorageException(
          'Failed to install file ${file.filename} via Modern handler',
          e,
          '_routeModelBySource',
        );
      }
    }
  }

  /// Handles model switching according to replace policy
  Future<void> _handleModelSwitching(ModelSpec spec) async {
    // If replace policy, clean up ALL models of this type before installing new one
    if (spec.replacePolicy == ModelReplacePolicy.replace) {
      debugPrint('Policy-based replacement: cleaning up ALL ${spec.type.name} models');

      // Delete all installed models of this type from ModelRepository
      final installedFiles = await getInstalledModels(spec.type);
      final registry = ServiceRegistry.instance;
      final repository = registry.modelRepository;

      for (final filename in installedFiles) {
        try {
          await ModelFileSystemManager.deleteModelFile(filename);
          await repository.deleteModel(filename);
        } catch (e) {
          debugPrint('Failed to delete model file $filename: $e');
        }
      }

      // Clean up tasks
      await _cleanupAllTasksOfType(spec.type);
    }
  }

  /// Clean up all tasks and files of a specific type
  Future<void> _cleanupAllTasksOfType(ModelManagementType type) async {
    try {
      debugPrint('Cleaning up all tasks of type: ${type.name}');

      final downloader = FileDownloader();
      final records = await downloader.database.allRecords();
      int cleanedCount = 0;

      for (final record in records) {
        final filename = record.task.filename;
        final modelType = _detectModelType(filename);

        if (modelType == type) {
          cleanedCount++;
          try {
            await ModelFileSystemManager.deleteModelFile(filename);
          } catch (e) {
            debugPrint('Could not delete partial file $filename: $e');
          }
        }
      }

      if (cleanedCount > 0) {
        debugPrint('Cleaned up $cleanedCount tasks of type ${type.name}');
      }

      // Reset background_downloader tasks
      try {
        await downloader.reset(group: 'flutter_gemma_downloads');
      } catch (e) {
        debugPrint('Failed to reset background_downloader tasks: $e');
      }
    } catch (e) {
      debugPrint('Failed to cleanup tasks of type ${type.name}: $e');
    }
  }

  /// Detect model type from filename
  ModelManagementType _detectModelType(String filename) {
    final extension = filename.split('.').last.toLowerCase();

    switch (extension) {
      case 'tflite':
      case 'json':
        return ModelManagementType.embedding;
      case 'bin':
      case 'task':
      case 'gguf':
        return ModelManagementType.inference;
      default:
        return ModelManagementType.inference;
    }
  }

  /// Modern API: Ensures a model spec is ready for use
  @override
  Future<void> ensureModelReadyFromSpec(ModelSpec spec) async {
    await _ensureModelReadySpec(spec);

    // Set as active model (automatically routes by type)
    setActiveModel(spec);
  }

  /// Legacy API: Ensures a model is ready for use
  @Deprecated('Use ensureModelReadyFromSpec with ModelSource instead')
  @override
  Future<void> ensureModelReady(String filename, String url) async {
    // Create spec from legacy parameters and delegate to internal method
    final spec = InferenceModelSpec.fromLegacyUrl(
      name: filename,
      modelUrl: url,
    );
    await _ensureModelReadySpec(spec);
    // Set as active inference model after ensuring it's ready
    setActiveModel(spec);
  }

  /// Downloads a model with progress tracking
  @override
  Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Starting download with progress - ${spec.name}');

    try {
      yield* _downloadModelWithProgress(spec, token: token);
      debugPrint('UnifiedModelManager: Download completed - ${spec.name}');

      // Set as active model after successful download (same as Modern API)
      setActiveModel(spec);
    } catch (e) {
      debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
      rethrow;
    }
  }

  /// Internal implementation of download with progress
  Stream<DownloadProgress> _downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
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

        // Download current file via ServiceRegistry handlers
        await for (final progress in _downloadSingleFileWithProgress(
          source: file.source,
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
        final minSize = ModelFileSystemManager.getMinimumSize(file.extension);
        if (!await ModelFileSystemManager.isFileValid(filePath, minSizeBytes: minSize)) {
          throw ModelValidationException(
            'Downloaded file failed validation: ${file.filename}',
            null,
            filePath,
          );
        }
      }

      // Note: Handlers already saved each file to ModelRepository

      // Emit final progress
      yield DownloadProgress(
        currentFileIndex: totalFiles,
        totalFiles: totalFiles,
        currentFileProgress: 100,
        currentFileName: 'Complete',
      );
    } catch (e) {
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

  /// Downloads a single file with progress tracking via ServiceRegistry
  Stream<int> _downloadSingleFileWithProgress({
    required ModelSource source,
    required String targetPath,
    String? token,
  }) async* {
    // Delegate to ServiceRegistry handler
    if (source is! NetworkSource) {
      throw ModelStorageException(
        'Cannot download from ${source.runtimeType}, only NetworkSource supported',
        null,
        '_downloadSingleFileWithProgress'
      );
    }

    // Create new NetworkSource with token if provided
    final networkSource = token != null
        ? NetworkSource(source.url, authToken: token)
        : source;

    final registry = ServiceRegistry.instance;
    final handler = registry.networkHandler;

    // Use handler's progress stream
    await for (final progress in handler.installWithProgress(networkSource)) {
      yield progress;
    }
  }

  /// Downloads a model without progress tracking
  @override
  Future<void> downloadModel(ModelSpec spec, {String? token}) async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Starting download - ${spec.name}');

    try {
      await for (final _ in _downloadModelWithProgress(spec, token: token)) {
        // Just consume the stream without emitting progress
      }
      debugPrint('UnifiedModelManager: Download completed - ${spec.name}');

      // Set as active model after successful download (same as Modern API)
      setActiveModel(spec);
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
      final result = await _isModelInstalled(spec);
      debugPrint('UnifiedModelManager: Model ${spec.name} installed: $result');
      return result;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to check if model installed - ${spec.name}: $e');
      return false;
    }
  }

  /// Internal implementation of model installation check
  Future<bool> _isModelInstalled(ModelSpec spec) async {
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Check that ALL files from spec are installed in repository
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        return false;
      }
    }

    // Validate all files exist and are valid on filesystem
    return await ModelFileSystemManager.validateModelFiles(spec);
  }

  /// Deletes a model and all its files
  @override
  Future<void> deleteModel(ModelSpec spec) async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Deleting model - ${spec.name}');

    try {
      final registry = ServiceRegistry.instance;
      final repository = registry.modelRepository;

      // Delete all files from filesystem and repository
      for (final file in spec.files) {
        await ModelFileSystemManager.deleteModelFile(file.filename);
        await repository.deleteModel(file.filename);
      }

      debugPrint('UnifiedModelManager: Model deleted - ${spec.name}');
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to delete model - ${spec.name}: $e');
      throw ModelStorageException(
        'Failed to delete model: ${spec.name}',
        e,
        'deleteModel',
      );
    }
  }

  /// Gets all installed models for a specific type
  @override
  Future<List<String>> getInstalledModels(ModelManagementType type) async {
    await _ensureInitialized();

    try {
      final registry = ServiceRegistry.instance;
      final repository = registry.modelRepository;

      // Convert ModelManagementType to repo.ModelType
      final modelType = type == ModelManagementType.inference
          ? repo.ModelType.inference
          : repo.ModelType.embedding;

      // Get all installed models and filter by type
      final allModels = await repository.listInstalled();
      final files = allModels
          .where((info) => info.type == modelType)
          .map((info) => info.id)
          .toList();

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
      final files = await getInstalledModels(type);
      return files.isNotEmpty;
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
      // 1. Get protected files from ModelRepository
      final protectedFiles = await _getAllProtectedFiles();

      // 2. Enhanced file system cleanup
      await ModelFileSystemManager.cleanupOrphanedFiles(
        protectedFiles: protectedFiles,
        enableResumeDetection: true,
      );

      // 3. Background_downloader cleanup
      final downloader = FileDownloader();
      await downloader.reset(group: 'flutter_gemma_downloads');

      debugPrint('UnifiedModelManager: Cleanup completed');
    } catch (e) {
      debugPrint('UnifiedModelManager: Cleanup failed: $e');
      // Don't rethrow - cleanup failures should not break the app
    }
  }

  /// Get all protected files from ModelRepository
  Future<List<String>> _getAllProtectedFiles() async {
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    final allModels = await repository.listInstalled();
    return allModels.map((info) => info.id).toList();
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

      final registry = ServiceRegistry.instance;
      final fileSystem = registry.fileSystemService;

      for (final file in spec.files) {
        // Get path based on source type
        final String path;
        if (file.source is FileSource) {
          // External file - use path from source
          path = (file.source as FileSource).path;
        } else if (file.source is BundledSource) {
          // Bundled source - get platform-specific bundled path
          final bundledSource = file.source as BundledSource;
          path = await fileSystem.getBundledResourcePath(bundledSource.resourceName);
        } else {
          // Downloaded/Asset file - use standard app directory
          path = await ModelFileSystemManager.getModelFilePath(file.filename);
        }
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
    return InferenceModelSpec.fromLegacyUrl(
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
    return EmbeddingModelSpec.fromLegacyUrl(
      name: name,
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
      replacePolicy: replacePolicy,
    );
  }

  /// Creates a bundled inference model specification (for production builds)
  ///
  /// Use this for models packaged with your app in native platform assets:
  /// - Android: android/src/main/assets/models/
  /// - iOS: Xcode Bundle Resources
  /// - Web: web/assets/models/
  ///
  /// Example:
  /// ```dart
  /// final spec = MobileModelManager.createBundledInferenceSpec(
  ///   resourceName: 'gemma3-270m-it-q8.task',
  /// );
  /// await manager.ensureModelReadyFromSpec(spec);
  /// ```
  static InferenceModelSpec createBundledInferenceSpec({
    required String resourceName,
    String? loraResourceName,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.replace,
  }) {
    // Extract name from resource (without extension)
    final name = resourceName.split('.').first;

    return InferenceModelSpec(
      name: name,
      modelSource: BundledSource(resourceName),
      loraSource: loraResourceName != null ? BundledSource(loraResourceName) : null,
      replacePolicy: replacePolicy,
    );
  }

  /// Creates a bundled embedding model specification (for production builds)
  ///
  /// Use this for embedding models packaged with your app in native platform assets.
  ///
  /// Example:
  /// ```dart
  /// final spec = MobileModelManager.createBundledEmbeddingSpec(
  ///   modelResourceName: 'embeddinggemma-300M.tflite',
  ///   tokenizerResourceName: 'sentencepiece.model',
  /// );
  /// await manager.ensureModelReadyFromSpec(spec);
  /// ```
  static EmbeddingModelSpec createBundledEmbeddingSpec({
    required String modelResourceName,
    required String tokenizerResourceName,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  }) {
    final name = modelResourceName.split('.').first;

    return EmbeddingModelSpec(
      name: name,
      modelSource: BundledSource(modelResourceName),
      tokenizerSource: BundledSource(tokenizerResourceName),
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

    final spec = InferenceModelSpec.fromLegacyUrl(
      name: ModelFileSystemManager.getBaseName(path.split('/').last),
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

    final spec = InferenceModelSpec.fromLegacyUrl(
      name: ModelFileSystemManager.getBaseName(path.split('/').last),
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

    final spec = InferenceModelSpec.fromLegacyUrl(
      name: ModelFileSystemManager.getBaseName(path.split('/').last),
      modelUrl: 'file://$path',
      loraUrl: loraPath != null ? 'file://$loraPath' : null,
    );

    await _ensureModelReadySpec(spec);
    setActiveModel(spec);
  }

  @override
  Future<void> clearModelCache() async {
    await _ensureInitialized();
    _activeInferenceModel = null;
    _activeEmbeddingModel = null;
    debugPrint('Model cache cleared');
  }

  // === Active Model Management ===

  ModelSpec? _activeInferenceModel;
  ModelSpec? _activeEmbeddingModel;

  /// Gets the currently active inference model specification
  ModelSpec? get activeInferenceModel => _activeInferenceModel;

  /// Gets the currently active embedding model specification
  ModelSpec? get activeEmbeddingModel => _activeEmbeddingModel;

  /// Gets the currently active model specification (backward compatibility)
  @Deprecated('Use activeInferenceModel or activeEmbeddingModel instead')
  ModelSpec? get currentActiveModel => _activeInferenceModel ?? _activeEmbeddingModel;

  /// Sets the active model for subsequent operations
  ///
  /// Automatically routes to inference or embedding based on spec type.
  @override
  void setActiveModel(ModelSpec spec) {
    if (spec is InferenceModelSpec) {
      _activeInferenceModel = spec;
      debugPrint('✅ Set active inference model: ${spec.name}');
    } else if (spec is EmbeddingModelSpec) {
      _activeEmbeddingModel = spec;
      debugPrint('✅ Set active embedding model: ${spec.name}');
    } else {
      throw ArgumentError('Unknown ModelSpec type: ${spec.runtimeType}');
    }
  }

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _ensureInitialized();

    if (_activeInferenceModel == null) {
      throw Exception('No active inference model to apply LoRA weights to. Use setModelPath first.');
    }

    // Create updated spec with new LoRA path
    final current = _activeInferenceModel as InferenceModelSpec;
    final updatedSpec = InferenceModelSpec.fromLegacyUrl(
      name: current.name,
      modelUrl: current.modelUrl,
      loraUrl: path.startsWith('/') ? 'file://$path' : path,
      replacePolicy: current.replacePolicy,
    );

    await _ensureModelReadySpec(updatedSpec);
    setActiveModel(updatedSpec);
  }

  @override
  Future<void> deleteLoraWeights() async {
    await _ensureInitialized();

    if (_activeInferenceModel == null) {
      throw Exception('No active inference model to remove LoRA weights from');
    }

    // Create updated spec without LoRA
    final current = _activeInferenceModel as InferenceModelSpec;
    final updatedSpec = InferenceModelSpec.fromLegacyUrl(
      name: current.name,
      modelUrl: current.modelUrl,
      loraUrl: null, // Remove LoRA
      replacePolicy: current.replacePolicy,
    );

    await _ensureModelReadySpec(updatedSpec);
    setActiveModel(updatedSpec);
  }

  // === Legacy Model Management Implementation ===

  @override
  Future<void> deleteCurrentModel() async {
    await _ensureInitialized();

    // Delete active inference model if exists
    if (_activeInferenceModel != null) {
      await deleteModel(_activeInferenceModel!);
      _activeInferenceModel = null;
    }

    // Delete active embedding model if exists
    if (_activeEmbeddingModel != null) {
      await deleteModel(_activeEmbeddingModel!);
      _activeEmbeddingModel = null;
    }
  }

  /// Gets storage statistics
  @override
  Future<Map<String, int>> getStorageStats() async {
    await _ensureInitialized();

    try {
      final stats = <String, int>{};

      // Get protected files from ModelRepository
      final protectedFiles = await _getAllProtectedFiles();
      stats['protectedFiles'] = protectedFiles.length;

      // Calculate total size of protected files
      int totalSize = 0;
      for (final filename in protectedFiles) {
        final path = await ModelFileSystemManager.getModelFilePath(filename);
        totalSize += await ModelFileSystemManager.getFileSize(path);
      }
      stats['totalSizeBytes'] = totalSize;
      stats['totalSizeMB'] = (totalSize / (1024 * 1024)).round();

      // Get counts by type from ModelRepository
      final inferenceFiles = await getInstalledModels(ModelManagementType.inference);
      final embeddingFiles = await getInstalledModels(ModelManagementType.embedding);

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

  /// Get information about orphaned files
  ///
  /// Returns list of files that don't have active downloads.
  /// These files can be safely deleted using cleanupStorage().
  Future<List<OrphanedFileInfo>> getOrphanedFiles() async {
    await _ensureInitialized();

    try {
      final protectedFiles = await _getProtectedFiles();
      return await ModelFileSystemManager.getOrphanedFiles(
        protectedFiles: protectedFiles,
      );
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to get orphaned files: $e');
      return [];
    }
  }

  /// Get storage statistics with orphaned file information
  Future<StorageStats> getStorageInfo() async {
    await _ensureInitialized();

    try {
      final protectedFiles = await _getProtectedFiles();
      return await ModelFileSystemManager.getStorageInfo(
        protectedFiles: protectedFiles,
      );
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to get storage info: $e');
      return const StorageStats(
        totalFiles: 0,
        totalSizeBytes: 0,
        orphanedFiles: [],
      );
    }
  }

  /// Clean up orphaned files
  ///
  /// ⚠️  This deletes files! Call getOrphanedFiles() first to see what will be deleted.
  ///
  /// Returns number of deleted files.
  Future<int> cleanupStorage() async {
    await _ensureInitialized();

    debugPrint('UnifiedModelManager: Cleaning up storage (explicit user call)');

    try {
      final protectedFiles = await _getProtectedFiles();
      final deletedCount = await ModelFileSystemManager.cleanupOrphanedFiles(
        protectedFiles: protectedFiles,
        enableResumeDetection: true,
      );

      debugPrint('UnifiedModelManager: Cleaned up $deletedCount orphaned files');
      return deletedCount;
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to cleanup storage: $e');
      return 0;
    }
  }

  /// Get list of files that should NOT be deleted
  Future<List<String>> _getProtectedFiles() async {
    final protected = <String>[];

    try {
      // Add all files from active inference model
      if (_activeInferenceModel != null) {
        for (final file in _activeInferenceModel!.files) {
          protected.add(file.filename);
        }
      }

      // Add all files from active embedding model
      if (_activeEmbeddingModel != null) {
        for (final file in _activeEmbeddingModel!.files) {
          protected.add(file.filename);
        }
      }

      // Add all installed inference models
      final installedInference = await getInstalledModels(ModelManagementType.inference);
      protected.addAll(installedInference);

      // Add all installed embedding models
      final installedEmbedding = await getInstalledModels(ModelManagementType.embedding);
      protected.addAll(installedEmbedding);

      debugPrint('UnifiedModelManager: Protected files count: ${protected.length}');
    } catch (e) {
      debugPrint('UnifiedModelManager: Failed to get protected files: $e');
    }

    return protected;
  }
}