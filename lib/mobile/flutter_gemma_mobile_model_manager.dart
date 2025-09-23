part of 'flutter_gemma_mobile.dart';

const _prefsModelKey = 'installed_model_file_name';
const _prefsLoraKey = 'installed_lora_file_name';
const _prefsReplaceKey = 'model_replace_policy';

class MobileModelManager extends ModelFileManager {
  MobileModelManager({
    required this.onDeleteModel,
    required this.onDeleteLora,
  }) {
    // Initialize unified system
    _unifiedManager = UnifiedModelManager();
    _initializeUnifiedSystem();
  }

  Future<void> _initializeUnifiedSystem() async {
    try {
      await _unifiedManager.initialize();
      await _loadReplacePolicy();
    } catch (e) {
      debugPrint('Failed to initialize unified system: $e');
    }
  }

  final AsyncCallback onDeleteModel;
  final AsyncCallback onDeleteLora;

  final _largeFileHandler = LargeFileHandler();
  final _prefs = SharedPreferences.getInstance();

  // === Unified system integration ===
  late final UnifiedModelManager _unifiedManager;


  String? _userSetModelPath;
  String? _userSetLoraPath;

  Completer<bool>? _modelCompleter;
  Completer<bool>? _loraCompleter;

  String? _modelFileName;
  String? _loraFileName;

  ModelReplacePolicy _replacePolicy = ModelReplacePolicy.keep;

  Future<File?> get _modelFile async {
    if (_userSetModelPath case String path) return File(path);
    final directory = await getApplicationDocumentsDirectory();
    if (_modelFileName case String name) {
      // Use the unified system path correction
      final correctedPath = ModelFileSystemManager.getCorrectedPath(directory.path, name);
      return File(correctedPath);
    }
    return null;
  }

  Future<File?> get _loraFile async {
    if (_userSetLoraPath case String path) return File(path);
    final directory = await getApplicationDocumentsDirectory();
    if (_loraFileName case String name) {
      return File('${directory.path}/$name');
    }
    return null;
  }

  /// Sets the policy for handling old models when switching
  @override
  Future<void> setReplacePolicy(ModelReplacePolicy policy) async {
    _replacePolicy = policy;
    final prefs = await _prefs;
    await prefs.setBool(_prefsReplaceKey, policy == ModelReplacePolicy.replace);
    debugPrint('ModelManager replace policy: ${policy.name}');
  }

  /// Gets the current replace policy
  @override
  ModelReplacePolicy get replacePolicy => _replacePolicy;

  /// Loads the replace policy from SharedPreferences
  Future<void> _loadReplacePolicy() async {
    final prefs = await _prefs;
    final shouldReplace = prefs.getBool(_prefsReplaceKey) ?? false;
    _replacePolicy = shouldReplace ? ModelReplacePolicy.replace : ModelReplacePolicy.keep;
  }





  /// Ensures the specified model is ready using unified system
  @override
  Future<void> ensureModelReady(String targetModel, String modelUrl) async {
    final spec = UnifiedModelManager.createInferenceSpec(
      name: targetModel.split('.').first,
      modelUrl: modelUrl,
      replacePolicy: _replacePolicy,
    );

    await _unifiedManager.ensureModelReady(spec);
    _modelFileName = targetModel;
  }


  @override
  Future<bool> get isModelInstalled async {
    // Return cached result if available
    if (_modelCompleter != null) return await _modelCompleter!.future;

    final prefs = await _prefs;
    final name = prefs.getString(_prefsModelKey);
    if (name == null) return false;

    _modelFileName = name;
    final file = await _modelFile;
    return file != null && await file.exists();
  }

  @override
  Future<bool> get isLoraInstalled async {
    // Return cached result if available
    if (_loraCompleter != null) return await _loraCompleter!.future;

    final prefs = await _prefs;
    final name = prefs.getString(_prefsLoraKey);
    if (name == null) return false;

    _loraFileName = name;
    final file = await _loraFile;
    return file != null && await file.exists();
  }

  Future<void> _loadModelIfNeeded(AsyncCallback loadCallback) async {
    if (await isModelInstalled) return;

    final completer = _modelCompleter = Completer<bool>();
    completer.complete(loadCallback().then((_) => true));
    await completer.future;
  }

  Stream<int> _loadModelWithProgressIfNeeded(Stream<int> Function() loadCallback) async* {
    if (await isModelInstalled) return;

    final completer = _modelCompleter = Completer<bool>();
    try {
      await for (final progress in loadCallback()) {
        yield progress;
      }
      completer.complete(true);
    } catch (e, st) {
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> _loadLoraIfNeeded(AsyncCallback loadCallback) async {
    if (await isLoraInstalled) return;

    final completer = _loraCompleter = Completer<bool>();
    completer.complete(loadCallback().then((_) => true));
    await completer.future;
  }

  /// Sets direct file paths
  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    await Future.wait([
      _loadModelIfNeeded(() async {
        // Apply Android path correction if needed
        final correctedPath = path;
        _userSetModelPath = correctedPath;
        // Update the cached filename when setting a new path
        final fileName = Uri.parse(correctedPath).pathSegments.last;
        _modelFileName = fileName;
        final prefs = await _prefs;
        await prefs.setString(_prefsModelKey, fileName);
        return;
      }),
      if (loraPath != null)
        _loadLoraIfNeeded(() async {
          _userSetLoraPath = loraPath;
          _loraFileName = Uri.parse(loraPath).pathSegments.last;
          final prefs = await _prefs;
          await prefs.setString(_prefsLoraKey, _loraFileName!);
          return;
        }),
    ]);
  }

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _loadLoraIfNeeded(() async {
      _userSetLoraPath = path;
      _loraFileName = Uri.parse(path).pathSegments.last;
      final prefs = await _prefs;
      await prefs.setString(_prefsLoraKey, _loraFileName!);
      return;
    });
  }

  /// Downloads model from URL using unified system
  @override
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl, String? token}) async {
    final modelFileName = Uri.parse(url).pathSegments.last;
    _modelFileName = modelFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, modelFileName);

    await Future.wait([
      _loadModelIfNeeded(() async {
        // Use unified system for download
        final spec = UnifiedModelManager.createInferenceSpec(
          name: _extractModelName(url),
          modelUrl: url,
          loraUrl: loraUrl,
          replacePolicy: _replacePolicy,
        );
        await _unifiedManager.downloadModel(spec, token: token);
      }),
      if (loraUrl != null) downloadLoraWeightsFromNetwork(loraUrl, token: token),
    ]);
  }

  @override
  Stream<int> downloadModelFromNetworkWithProgress(String url, {String? loraUrl, String? token}) async* {
    final modelFileName = Uri.parse(url).pathSegments.last;
    _modelFileName = modelFileName;

    try {
      yield* _loadModelWithProgressIfNeeded(() async* {
        // Use unified system for download with progress
        final spec = UnifiedModelManager.createInferenceSpec(
          name: _extractModelName(url),
          modelUrl: url,
          loraUrl: loraUrl,
          replacePolicy: _replacePolicy,
        );

        await for (final progress in _unifiedManager.downloadModelWithProgress(spec, token: token)) {
          yield progress.overallProgress;
        }
      });

      // Set SharedPrefs ONLY after successful download
      final prefs = await _prefs;
      await prefs.setString(_prefsModelKey, modelFileName);
    } catch (e) {
      // Cleanup on error
      _modelFileName = null;
      rethrow;
    }

    if (loraUrl != null) {
      await downloadLoraWeightsFromNetwork(loraUrl, token: token);
    }
  }

  @override
  Future<void> downloadLoraWeightsFromNetwork(String loraUrl, {String? token}) async {
    final loraFileName = Uri.parse(loraUrl).pathSegments.last;
    _loraFileName = loraFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsLoraKey, loraFileName);

    await _loadLoraIfNeeded(() async {
      // For LoRA, we can use the legacy download system or unified
      // For now keep it simple since LoRA is handled in main download
      return;
    });
  }

  /// Installs from asset
  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    final modelFileName = Uri.parse(path).pathSegments.last;
    _modelFileName = modelFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, modelFileName);

    await Future.wait([
      _loadModelIfNeeded(() => _largeFileHandler.copyAssetToLocalStorage(
            assetName: path,
            targetPath: modelFileName,
          )),
      if (loraPath != null) installLoraWeightsFromAsset(loraPath),
    ]);
  }

  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) async* {
    final modelFileName = Uri.parse(path).pathSegments.last;
    _modelFileName = modelFileName;

    try {
      yield* _loadModelWithProgressIfNeeded(() => _largeFileHandler.copyAssetToLocalStorageWithProgress(
            assetName: path,
            targetPath: modelFileName,
          ));

      // Set SharedPrefs ONLY after successful asset copy
      final prefs = await _prefs;
      await prefs.setString(_prefsModelKey, modelFileName);
    } catch (e) {
      // Cleanup on error
      _modelFileName = null;
      rethrow;
    }

    if (loraPath != null) {
      await installLoraWeightsFromAsset(loraPath);
    }
  }

  @override
  Future<void> installLoraWeightsFromAsset(String path) async {
    final loraFileName = Uri.parse(path).pathSegments.last;
    _loraFileName = loraFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsLoraKey, loraFileName);

    await _loadLoraIfNeeded(() => _largeFileHandler.copyAssetToLocalStorage(
          assetName: path,
          targetPath: loraFileName,
        ));
  }

  /// Forces update of the cached model filename - useful when switching between different models
  @override
  Future<void> forceUpdateModelFilename(String filename) async {
    _modelFileName = filename;
    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, filename);
    // Reset the completer to force re-check of model existence
    _modelCompleter = null;
  }

  /// Clears all model cache and resets state - useful for model switching
  @override
  Future<void> clearModelCache() async {
    _modelCompleter = null;
    _modelFileName = null;
    _userSetModelPath = null;
    final prefs = await _prefs;
    await prefs.remove(_prefsModelKey);
  }

  @override
  Future<void> deleteModel() async {
    _modelCompleter = null;

    // Try to find and delete any inference models using unified system
    final files = await _unifiedManager.getInstalledModels(ModelManagementType.inference);
    if (files.isNotEmpty) {
      for (final filename in files) {
        if (!filename.contains('lora')) {
          final spec = UnifiedModelManager.createInferenceSpec(
            name: filename.split('.').first,
            modelUrl: 'local://$filename',
          );
          await _unifiedManager.deleteModel(spec);
          await onDeleteModel();
          break;
        }
      }
    }

    // Cleanup legacy state
    _userSetModelPath = null;
    _modelFileName = null;

    final prefs = await _prefs;
    await prefs.remove(_prefsModelKey);
  }

  @override
  Future<void> deleteLoraWeights() async {
    _loraCompleter = null;

    // Find and delete LoRA files using unified system
    final files = await _unifiedManager.getInstalledModels(ModelManagementType.inference);
    for (final filename in files) {
      if (filename.contains('lora') || (filename.endsWith('.bin') && _loraFileName == filename)) {
        try {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$filename');
          if (await file.exists()) {
            await onDeleteLora();
            await file.delete();
          }
        } catch (e) {
          debugPrint('Failed to delete LoRA file $filename: $e');
        }
      }
    }

    // Cleanup legacy state
    _userSetLoraPath = null;
    _loraFileName = null;

    final prefs = await _prefs;
    await prefs.remove(_prefsLoraKey);
  }


  // === RAG Embedding Model Management ===

  /// Download embedding model using unified system
  Future<void> downloadEmbeddingModel({
    required String modelUrl,
    required String tokenizerUrl,
    required String modelFilename,
    required String tokenizerFilename,
    String? token,
  }) async {
    final spec = UnifiedModelManager.createEmbeddingSpec(
      name: modelFilename.split('.').first,
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
    );

    await _unifiedManager.downloadModel(spec, token: token);
  }

  /// Download embedding model with progress using unified system
  Stream<int> downloadEmbeddingModelWithProgress({
    required String modelUrl,
    required String tokenizerUrl,
    required String modelFilename,
    required String tokenizerFilename,
    String? token,
  }) async* {
    final spec = UnifiedModelManager.createEmbeddingSpec(
      name: modelFilename.split('.').first,
      modelUrl: modelUrl,
      tokenizerUrl: tokenizerUrl,
    );

    await for (final progress in _unifiedManager.downloadModelWithProgress(spec, token: token)) {
      yield progress.overallProgress;
    }
  }

  /// Check if embedding model is installed using unified system
  Future<bool> get isEmbeddingModelInstalled async {
    return await _unifiedManager.isAnyModelInstalled(ModelManagementType.embedding);
  }

  /// Get installed embedding model file paths using unified system
  Future<({String? modelPath, String? tokenizerPath})?> get embeddingModelPaths async {
    final files = await _unifiedManager.getInstalledModels(ModelManagementType.embedding);
    if (files.length < 2) return null;

    final directory = await getApplicationDocumentsDirectory();
    final modelFile = files.firstWhere((f) => f.endsWith('.tflite'), orElse: () => files.first);
    final tokenizerFile = files.firstWhere((f) => f.endsWith('.json'), orElse: () => files.last);

    return (
      modelPath: '${directory.path}/$modelFile',
      tokenizerPath: '${directory.path}/$tokenizerFile',
    );
  }

  /// Delete embedding model using unified system
  Future<void> deleteEmbeddingModel() async {
    final files = await _unifiedManager.getInstalledModels(ModelManagementType.embedding);
    if (files.isEmpty) return;

    // Create a spec to delete - we need at least one model
    final modelFile = files.firstWhere((f) => f.endsWith('.tflite'), orElse: () => files.first);
    final tokenizerFile = files.firstWhere((f) => f.endsWith('.json'), orElse: () => files.last);

    final spec = UnifiedModelManager.createEmbeddingSpec(
      name: modelFile.split('.').first,
      modelUrl: 'local://$modelFile',
      tokenizerUrl: 'local://$tokenizerFile',
    );

    await _unifiedManager.deleteModel(spec);
  }

  // === Unified model management methods ===

  /// Performs cleanup using unified system
  Future<void> performCleanup() async {
    await _unifiedManager.performCleanup();
  }

  /// Gets storage statistics using unified system
  Future<Map<String, dynamic>> getStorageStats() async {
    return await _unifiedManager.getStorageStats();
  }

  /// Helper to extract model name from URL
  String _extractModelName(String url) {
    final filename = Uri.parse(url).pathSegments.last;
    return filename.split('.').first;
  }
}
