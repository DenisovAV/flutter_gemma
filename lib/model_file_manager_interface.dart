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

  /// Gets storage statistics
  Future<Map<String, int>> getStorageStats();

  /// Ensures a model is ready for use, handling all necessary operations
  Future<void> ensureModelReady(String filename, String url);

  /// Installs model from Flutter assets (debug only)
  Future<void> installModelFromAsset(String path, {String? loraPath});

  /// Installs model from Flutter assets with progress tracking (debug only)
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath});

  /// Sets direct path to existing model files
  Future<void> setModelPath(String path, {String? loraPath});

  /// Clears current model cache/state
  Future<void> clearModelCache();

  /// Sets path to LoRA weights for current model
  Future<void> setLoraWeightsPath(String path);

  /// Removes LoRA weights from current model
  Future<void> deleteLoraWeights();

  /// Deletes current active model (legacy method without parameters)
  Future<void> deleteCurrentModel();
}