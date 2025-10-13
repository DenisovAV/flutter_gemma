import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';

/// Policy for handling old models when switching to new ones
enum ModelReplacePolicy {
  /// Keep all models on disk (default)
  keep,
  /// Delete previous model when switching to save space
  replace,
}

abstract class ModelFileManager {
  /// Check if a model is installed and valid
  Future<bool> isModelInstalled(ModelSpec spec);

  /// Downloads a model with progress tracking
  Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token});

  /// Downloads a model without progress tracking
  Future<void> downloadModel(ModelSpec spec, {String? token});

  /// Deletes a model and all its files
  Future<void> deleteModel(ModelSpec spec);

  /// Gets all installed models for a specific type
  Future<List<String>> getInstalledModels(ModelManagementType type);

  /// Checks if ANY model of the given type is installed
  Future<bool> isAnyModelInstalled(ModelManagementType type);

  /// Performs cleanup of orphaned files
  Future<void> performCleanup();

  /// Validates all files for a model specification
  Future<bool> validateModel(ModelSpec spec);

  /// Gets the file paths for an installed model
  Future<Map<String, String>?> getModelFilePaths(ModelSpec spec);

  /// Gets storage statistics (legacy format)
  Future<Map<String, int>> getStorageStats();

  /// Gets detailed storage information including orphaned files
  Future<StorageStats> getStorageInfo();

  /// Gets list of orphaned files (files without active downloads)
  Future<List<OrphanedFileInfo>> getOrphanedFiles();

  /// Explicitly cleanup orphaned files (user must call this - NOT automatic)
  /// Returns number of deleted files
  Future<int> cleanupStorage();

  /// Modern API: Ensures a model spec is ready for use
  Future<void> ensureModelReadyFromSpec(ModelSpec spec);

  /// Legacy API: Ensures a model is ready for use, handling all necessary operations
  @Deprecated('Use ensureModelReadyFromSpec with ModelSource instead')
  Future<void> ensureModelReady(String filename, String url);

  /// Legacy API: Installs model from Flutter assets (debug only)
  @Deprecated('Use FlutterGemma.installModel().fromAsset() instead')
  Future<void> installModelFromAsset(String path, {String? loraPath});

  /// Legacy API: Installs model from Flutter assets with progress tracking (debug only)
  @Deprecated('Use FlutterGemma.installModel().fromAsset().withProgress() instead')
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath});

  /// Legacy API: Sets direct path to existing model files
  @Deprecated('Use FlutterGemma.installModel().fromFile() instead')
  Future<void> setModelPath(String path, {String? loraPath});

  /// Clears current model cache/state
  Future<void> clearModelCache();

  /// Legacy API: Sets path to LoRA weights for current model
  @Deprecated('Use FlutterGemma.installModel().withLoraFromFile() instead')
  Future<void> setLoraWeightsPath(String path);

  /// Legacy API: Removes LoRA weights from current model
  @Deprecated('Reinstall model without LoRA using FlutterGemma.installModel()')
  Future<void> deleteLoraWeights();

  /// Legacy API: Deletes current active model (legacy method without parameters)
  @Deprecated('Use deleteModel(spec) with ModelSpec instead')
  Future<void> deleteCurrentModel();

  /// Sets the active model for subsequent inference operations
  void setActiveModel(ModelSpec spec);

  /// Gets the currently active inference model specification
  ModelSpec? get activeInferenceModel;

  /// Gets the currently active embedding model specification
  ModelSpec? get activeEmbeddingModel;
}