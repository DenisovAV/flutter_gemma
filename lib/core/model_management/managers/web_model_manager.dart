part of '../../../web/flutter_gemma_web.dart';

/// Web Model Manager - Modern API Facade Pattern
///
/// Phase 5 Complete: This class now delegates all model management to the
/// Modern API (ServiceRegistry + Handlers + Repository) instead of manually
/// managing state. All methods are thin facades over the Modern API.
///
/// Architecture:
/// - OLD: Manual state maps (_installedModels, _modelPaths, etc.)
/// - NEW: Delegates to ServiceRegistry.instance → handlers → repository
///
/// Benefits:
/// - Single source of truth (repository)
/// - No code duplication
/// - Platform-agnostic (same pattern as MobileModelManager)
/// - Easier to maintain and test
class WebModelManager extends ModelFileManager {
  bool _isInitialized = false;

  /// Initializes the web model manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('WebModelManager initialized');
  }

  /// Checks if a model is installed
  ///
  /// Phase 5.3: Delegates to Modern API (ModelRepository) instead of
  /// checking manual state (_modelPaths, _loadCompleters).
  @override
  Future<bool> isModelInstalled(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Check if all files in the spec are installed
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        return false;
      }
    }

    return true;
  }

  @override
  Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
    await _ensureInitialized();

    debugPrint('WebModelManager: Starting download for ${spec.name}');

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;
    final totalFiles = spec.files.length;

    for (int i = 0; i < totalFiles; i++) {
      final file = spec.files[i];

      // Emit file start progress
      yield DownloadProgress(
        currentFileIndex: i,
        totalFiles: totalFiles,
        currentFileProgress: 0,
        currentFileName: file.filename,
      );

      // Get handler for this file's source
      final handler = handlerRegistry.getHandler(file.source);
      if (handler == null) {
        throw ModelStorageException(
          'No handler for ${file.source.runtimeType}',
          null,
          'downloadModelWithProgress',
        );
      }

      // For NetworkSource with token, update the source
      ModelSource sourceToInstall = file.source;
      if (sourceToInstall is NetworkSource && token != null) {
        sourceToInstall = NetworkSource(sourceToInstall.url, authToken: token);
      }

      // Download via Modern API handler with progress
      // All handlers implement installWithProgress (handlers that don't support
      // true progress will emit 100% immediately)
      await for (final progress in handler.installWithProgress(sourceToInstall)) {
        yield DownloadProgress(
          currentFileIndex: i,
          totalFiles: totalFiles,
          currentFileProgress: progress,
          currentFileName: file.filename,
        );
      }
    }

    // Set as active after successful download
    setActiveModel(spec);

    // Emit final progress
    yield DownloadProgress(
      currentFileIndex: totalFiles,
      totalFiles: totalFiles,
      currentFileProgress: 100,
      currentFileName: 'Complete',
    );

    debugPrint('WebModelManager: Download completed for ${spec.name}');
  }

  @override
  Future<void> downloadModel(ModelSpec spec, {String? token}) async {
    await _ensureInitialized();
    // Use the stream version but don't yield progress
    await for (final _ in downloadModelWithProgress(spec, token: token)) {
      // Just consume the stream
    }
  }

  /// Deletes a model
  ///
  /// Phase 5.5: Delegates to Modern API (ModelRepository) instead of
  /// manually removing from state maps.
  @override
  Future<void> deleteModel(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Delete all files in the spec from repository
    for (final file in spec.files) {
      await repository.deleteModel(file.filename);
    }

    debugPrint('WebModelManager: Model ${spec.name} deleted');
  }

  /// Gets list of installed model filenames
  ///
  /// Phase 5.5: Delegates to Modern API (ModelRepository) instead of
  /// querying _installedModels map.
  @override
  Future<List<String>> getInstalledModels(ModelManagementType type) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Get all installed models from repository
    final allInstalled = await repository.listInstalled();

    // Filter by type
    final filtered = allInstalled.where((m) {
      if (type == ModelManagementType.inference) {
        return m.type == repo.ModelType.inference;
      } else {
        return m.type == repo.ModelType.embedding;
      }
    }).toList();

    // Return filenames
    return filtered.map((m) => m.id).toList();
  }

  /// Checks if any model is installed
  ///
  /// Phase 5.5: Delegates to Modern API (ModelRepository) instead of
  /// checking _installedModels map.
  @override
  Future<bool> isAnyModelInstalled(ModelManagementType type) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Get all installed models from repository
    final allInstalled = await repository.listInstalled();

    if (type == ModelManagementType.inference) {
      return allInstalled.any((m) => m.type == repo.ModelType.inference);
    } else {
      return allInstalled.any((m) => m.type == repo.ModelType.embedding);
    }
  }

  @override
  Future<void> performCleanup() async {
    await _ensureInitialized();
    debugPrint('WebModelManager: Cleanup not needed on web');
  }

  /// Validates if a model is properly installed
  ///
  /// Phase 5.3: Delegates to Modern API (isModelInstalled) instead of
  /// checking manual _installedModels map.
  @override
  Future<bool> validateModel(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    // validateModel is essentially the same as isModelInstalled on web
    return await isModelInstalled(spec);
  }

  @override
  Future<Map<String, String>?> getModelFilePaths(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;
    final fileSystem = registry.fileSystemService as WebFileSystemService;

    // Check installation via repository
    bool allFilesInstalled = true;
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        allFilesInstalled = false;
        break;
      }
    }

    if (!allFilesInstalled) {
      return null;
    }

    final filePaths = <String, String>{};

    for (final file in spec.files) {
      // Get URL from WebFileSystemService based on source type
      final String path;

      if (file.source is NetworkSource) {
        // Web: Get registered URL (blob URL for auth downloads)
        // If URL lost (page reload), restore from Cache API
        var url = fileSystem.getUrl(file.filename);
        if (url == null) {
          debugPrint('[WebModelManager] Blob URL lost for ${file.filename}, restoring from cache...');

          // Try to restore from Cache API
          final networkSource = file.source as NetworkSource;
          final downloadService = registry.downloadService as WebDownloadService;
          final cacheService = downloadService.cacheService;

          // Get cached blob URL (cache service handles URL normalization internally)
          final cachedBlobUrl = await cacheService.getCachedBlobUrl(networkSource.url);
          if (cachedBlobUrl != null) {
            debugPrint('[WebModelManager] ✅ Restored blob URL from cache: $cachedBlobUrl');
            // Re-register the blob URL
            fileSystem.registerUrl(file.filename, cachedBlobUrl);
            url = cachedBlobUrl;
          } else {
            debugPrint('[WebModelManager] ⚠️  Not found in cache, will use original URL (may require auth)');
          }
        }
        path = url ?? (file.source as NetworkSource).url;
      } else if (file.source is BundledSource) {
        // Web: Bundled resources
        path = await fileSystem.getBundledResourcePath((file.source as BundledSource).resourceName);
      } else if (file.source is AssetSource) {
        // Web: Get registered Blob URL (created by WebAssetSourceHandler)
        // If URL lost (page reload), recreate it
        var url = fileSystem.getUrl(file.filename);
        if (url == null) {
          debugPrint(
              '[WebModelManager] Blob URL lost for ${file.filename}, recreating from asset...');
          // Recreate Blob URL by reinstalling
          final handler = registry.sourceHandlerRegistry.getHandler(file.source);
          if (handler != null) {
            await handler.install(file.source);
            url = fileSystem.getUrl(file.filename);
          }
        }
        path = url ?? (file.source as AssetSource).normalizedPath;
      } else if (file.source is FileSource) {
        // Web: External URL or registered path
        final fileSource = file.source as FileSource;
        path = fileSystem.getUrl(file.filename) ?? fileSource.path;
      } else {
        // Fallback: use getTargetPath
        path = await fileSystem.getTargetPath(file.filename);
      }

      filePaths[file.prefsKey] = path;
    }

    return filePaths.isNotEmpty ? filePaths : null;
  }

  /// Gets storage statistics for installed models
  ///
  /// Phase 5.3: Delegates to Modern API (ModelRepository) instead of
  /// checking manual _installedModels map.
  @override
  Future<Map<String, int>> getStorageStats() async {
    await _ensureInitialized();

    // Phase 5: Delegate to Modern API
    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // Get all installed models from repository
    final allInstalled = await repository.listInstalled();
    final installedCount = allInstalled.length;

    // Count by type
    final inferenceCount = allInstalled.where((m) => m.type == repo.ModelType.inference).length;
    final embeddingCount = allInstalled.where((m) => m.type == repo.ModelType.embedding).length;

    return {
      'protectedFiles': installedCount,
      'totalSizeBytes': 0, // Unknown for web URLs (no local file system)
      'totalSizeMB': 0,
      'inferenceModels': inferenceCount,
      'embeddingModels': embeddingCount,
    };
  }

  /// Modern API: Ensures a model spec is ready for use
  ///
  /// Phase 5.1: This method now delegates to ServiceRegistry (Modern API)
  /// instead of manually managing state. All installation is handled by
  /// source handlers through the ServiceRegistry pattern.
  @override
  Future<void> ensureModelReadyFromSpec(ModelSpec spec) async {
    await _ensureInitialized();

    // Phase 5: Delegate to ServiceRegistry (Modern API)
    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;
    final repository = registry.modelRepository;

    // Check if already installed via repository
    bool allFilesInstalled = true;
    for (final file in spec.files) {
      if (!await repository.isInstalled(file.filename)) {
        allFilesInstalled = false;
        break;
      }
    }

    if (!allFilesInstalled) {
      // Install via Modern API handlers
      for (final file in spec.files) {
        final handler = handlerRegistry.getHandler(file.source);
        if (handler == null) {
          throw ModelStorageException(
            'No handler for ${file.source.runtimeType}',
            null,
            'ensureModelReadyFromSpec',
          );
        }
        await handler.install(file.source);
      }
    }

    setActiveModel(spec);
  }

  /// Legacy API: Ensures a model is ready for use, handling all necessary operations
  ///
  /// Phase 5.5: Thin facade over ensureModelReadyFromSpec (Modern API)
  @Deprecated('Use ensureModelReadyFromSpec with ModelSource instead')
  @override
  Future<void> ensureModelReady(String filename, String url) async {
    await _ensureInitialized();

    // Create a spec and delegate to Modern API
    final spec = InferenceModelSpec.fromLegacyUrl(
      name: filename,
      modelUrl: url,
    );

    // Delegate to Modern API (no manual state management needed)
    await ensureModelReadyFromSpec(spec);
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Creates an inference model specification from parameters
  static InferenceModelSpec createInferenceSpec({
    required String name,
    required String modelUrl,
    String? loraUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
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
  /// Use this for models packaged in web/assets/models/
  ///
  /// Example:
  /// ```dart
  /// final spec = WebModelManager.createBundledInferenceSpec(
  ///   resourceName: 'gemma3-270m-it-q8.task',
  /// );
  /// await manager.ensureModelReadyFromSpec(spec);
  /// ```
  static InferenceModelSpec createBundledInferenceSpec({
    required String resourceName,
    String? loraResourceName,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
    ModelType modelType = ModelType.general,
    ModelFileType fileType = ModelFileType.task,
  }) {
    final name = resourceName.split('.').first;

    return InferenceModelSpec(
      name: name,
      modelSource: BundledSource(resourceName),
      loraSource: loraResourceName != null ? BundledSource(loraResourceName) : null,
      replacePolicy: replacePolicy,
      modelType: modelType,
      fileType: fileType,
    );
  }

  /// Creates a bundled embedding model specification (for production builds)
  ///
  /// Use this for embedding models packaged in web/assets/models/
  ///
  /// Example:
  /// ```dart
  /// final spec = WebModelManager.createBundledEmbeddingSpec(
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

  // Active models (modern API)
  ModelSpec? _activeInferenceModel;
  ModelSpec? _activeEmbeddingModel;

  /// Gets the currently active inference model specification
  @override
  ModelSpec? get activeInferenceModel => _activeInferenceModel;

  /// Gets the currently active embedding model specification
  @override
  ModelSpec? get activeEmbeddingModel => _activeEmbeddingModel;

  /// Gets the currently active model specification (backward compatibility)
  @Deprecated('Use activeInferenceModel or activeEmbeddingModel instead')
  ModelSpec? get currentActiveModel => _activeInferenceModel ?? _activeEmbeddingModel;

  // === Legacy Asset Loading Methods Implementation ===

  /// Installs model from Flutter asset (debug mode only)
  ///
  /// ⚠️ DEPRECATED: Use FlutterGemma.installModel().fromAsset() instead
  ///
  /// This method provides backward compatibility but delegates to Modern API.
  ///
  /// Migration:
  /// ```dart
  /// // OLD:
  /// await manager.installModelFromAsset('assets/models/gemma.task');
  ///
  /// // NEW:
  /// await FlutterGemma.installModel()
  ///   .fromAsset('assets/models/gemma.task')
  ///   .install();
  /// ```
  @Deprecated('Use FlutterGemma.installModel().fromAsset() instead')
  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError("Asset model loading is not supported in release builds. "
          "Use fromNetwork() or fromBundled() instead.");
    }

    await _ensureInitialized();

    // Convert legacy parameters to Modern API ModelSpec
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(path.split('/').last),
      modelSource: ModelSource.asset(path),
      loraSource: loraPath != null ? ModelSource.asset(loraPath) : null,
      modelType: ModelType.general, // Default for legacy API
      fileType: ModelFileType.task, // Default for legacy API
    );

    // Delegate to Modern API
    // This uses AssetSourceHandler which handles all the work
    await ensureModelReadyFromSpec(spec);
  }

  /// Installs model from Flutter asset with progress (debug mode only)
  ///
  /// ⚠️ DEPRECATED: Use FlutterGemma.installModel().fromAsset().installWithProgress() instead
  ///
  /// Migration:
  /// ```dart
  /// // OLD:
  /// await for (final progress in manager.installModelFromAssetWithProgress('assets/models/gemma.task')) {
  ///   debugPrint('Progress: $progress%');
  /// }
  ///
  /// // NEW:
  /// await for (final progress in FlutterGemma.installModel()
  ///     .fromAsset('assets/models/gemma.task')
  ///     .installWithProgress()) {
  ///   debugPrint('Progress: ${progress.currentFileProgress}%');
  /// }
  /// ```
  @Deprecated('Use FlutterGemma.installModel().fromAsset().installWithProgress() instead')
  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) async* {
    if (kReleaseMode) {
      throw UnsupportedError("Asset model loading is not supported in release builds. "
          "Use fromNetwork() or fromBundled() instead.");
    }

    await _ensureInitialized();

    // Convert legacy parameters to Modern API ModelSpec
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(path.split('/').last),
      modelSource: ModelSource.asset(path),
      loraSource: loraPath != null ? ModelSource.asset(loraPath) : null,
      modelType: ModelType.general, // Default for legacy API
      fileType: ModelFileType.task, // Default for legacy API
    );

    // Delegate to Modern API downloadModelWithProgress
    // This provides real progress tracking from handlers
    await for (final downloadProgress in downloadModelWithProgress(spec)) {
      yield downloadProgress.currentFileProgress;
    }
  }

  // === Legacy Direct Path Methods Implementation ===

  /// Sets model path for inference (web: URLs only)
  ///
  /// ⚠️ DEPRECATED: Use FlutterGemma.installModel().fromNetwork() instead
  ///
  /// This method provides backward compatibility but delegates to Modern API.
  ///
  /// Migration:
  /// ```dart
  /// // OLD:
  /// await manager.setModelPath('https://example.com/model.task');
  ///
  /// // NEW:
  /// await FlutterGemma.installModel()
  ///   .fromNetwork('https://example.com/model.task')
  ///   .install();
  /// ```
  @Deprecated('Use FlutterGemma.installModel().fromNetwork() instead')
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    await _ensureInitialized();

    // Create ModelSource based on path type
    final modelSource =
        path.startsWith('http') ? ModelSource.network(path) : ModelSource.file(path);

    final loraSource = loraPath != null
        ? (loraPath.startsWith('http') ? ModelSource.network(loraPath) : ModelSource.file(loraPath))
        : null;

    // Convert legacy parameters to Modern API ModelSpec
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(path.split('/').last),
      modelSource: modelSource,
      loraSource: loraSource,
      modelType: ModelType.general, // Default for legacy API
      fileType: ModelFileType.task, // Default for legacy API
    );

    // Delegate to Modern API
    await ensureModelReadyFromSpec(spec);
  }

  /// Clears model cache (legacy method)
  ///
  /// ⚠️ Note: In Modern API, model persistence is managed by ModelRepository.
  /// This method only clears active model references, not installed models.
  /// Use deleteModel() to remove installed models.
  @override
  Future<void> clearModelCache() async {
    await _ensureInitialized();

    // Clear active models
    _activeInferenceModel = null;
    _activeEmbeddingModel = null;

    debugPrint('WebModelManager: Model cache cleared (active models reset)');
  }

  // === Legacy LoRA Management Methods Implementation ===

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _ensureInitialized();

    if (_activeInferenceModel == null) {
      throw Exception(
          'No active inference model to apply LoRA weights to. Use setModelPath first.');
    }

    final current = _activeInferenceModel as InferenceModelSpec;

    // Create LoRA source from path
    final loraSource = path.startsWith('http') ? ModelSource.network(path) : ModelSource.file(path);

    final updatedSpec = InferenceModelSpec(
      name: current.name,
      modelSource: current.modelSource,
      loraSource: loraSource,
      replacePolicy: current.replacePolicy,
      modelType: current.modelType,
      fileType: current.fileType,
    );

    // Update active model (no manual _loraPaths management needed)
    setActiveModel(updatedSpec);
  }

  @override
  Future<void> deleteLoraWeights() async {
    await _ensureInitialized();

    if (_activeInferenceModel == null) {
      throw Exception('No active inference model to remove LoRA weights from');
    }

    final current = _activeInferenceModel as InferenceModelSpec;

    final updatedSpec = InferenceModelSpec(
      name: current.name,
      modelSource: current.modelSource,
      loraSource: null, // Remove LoRA
      replacePolicy: current.replacePolicy,
      modelType: current.modelType,
      fileType: current.fileType,
    );

    // Update active model (no manual _loraPaths management needed)
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

  // === Storage Management Implementation ===

  @override
  Future<StorageStats> getStorageInfo() async {
    await _ensureInitialized();
    // Web platform doesn't have file system access, return empty stats
    return const StorageStats(
      totalFiles: 0,
      totalSizeBytes: 0,
      orphanedFiles: [],
    );
  }

  @override
  Future<List<OrphanedFileInfo>> getOrphanedFiles() async {
    await _ensureInitialized();
    // Web platform doesn't have file system access, no orphaned files
    return [];
  }

  @override
  Future<int> cleanupStorage() async {
    await _ensureInitialized();
    // Web platform doesn't have file system access, nothing to cleanup
    debugPrint('WebModelManager: cleanupStorage() is a no-op on web');
    return 0;
  }

  // === Web Cache Management (NEW) ===

  /// Clear browser cache for models
  ///
  /// Deletes all cached model data from browser Cache API.
  /// This is separate from deleteModel() which only removes
  /// installation records.
  Future<void> clearCache() async {
    await _ensureInitialized();

    try {
      final registry = ServiceRegistry.instance;
      final downloadService = registry.downloadService as WebDownloadService;
      await downloadService.cacheService.clearCache();
      debugPrint('WebModelManager: Browser cache cleared');
    } catch (e) {
      debugPrint('WebModelManager: clearCache failed: $e');
      rethrow;
    }
  }

  /// Get cache statistics
  ///
  /// Returns information about browser cache usage.
  Future<Map<String, dynamic>> getCacheStats() async {
    await _ensureInitialized();

    try {
      final registry = ServiceRegistry.instance;
      final downloadService = registry.downloadService as WebDownloadService;
      final cacheService = downloadService.cacheService;

      final quota = await cacheService.getStorageQuota();
      final urls = await cacheService.getCachedUrls();

      return {
        'cachedUrls': urls.length,
        'storageUsage': quota.usage,
        'storageQuota': quota.quota,
        'usagePercent': quota.usagePercent,
        'availableBytes': quota.available,
      };
    } catch (e) {
      debugPrint('[WebModelManager] ❌ getCacheStats failed: $e');
      return {
        'cachedUrls': 0,
        'storageUsage': 0,
        'storageQuota': 0,
        'usagePercent': 0.0,
        'availableBytes': 0,
      };
    }
  }
}
