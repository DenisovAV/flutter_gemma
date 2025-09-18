part of 'flutter_gemma_mobile.dart';

const _prefsModelKey = 'installed_model_file_name';
const _prefsLoraKey = 'installed_lora_file_name';
const _downloadGroup = 'flutter_gemma_downloads';

// Supported model file extensions
const _supportedExtensions = ['.task', '.bin'];

class MobileModelManager extends ModelFileManager {
  MobileModelManager({
    required this.onDeleteModel,
    required this.onDeleteLora,
  });

  final AsyncCallback onDeleteModel;
  final AsyncCallback onDeleteLora;

  final _largeFileHandler = LargeFileHandler();
  final _prefs = SharedPreferences.getInstance();

  String? _userSetModelPath;
  String? _userSetLoraPath;

  Completer<bool>? _modelCompleter;
  Completer<bool>? _loraCompleter;

  String? _modelFileName;
  String? _loraFileName;

  bool _cleanupCompleted = false;

  /// Corrects Android path from /data/user/0/ to /data/data/ for proper file access
  String _getCorrectedPath(String originalPath, String filename) {
    // Check if this is the problematic Android path format
    if (originalPath.contains('/data/user/0/')) {
      // Replace with the correct Android app data path
      final correctedPath = originalPath.replaceFirst('/data/user/0/', '/data/data/');
      return '$correctedPath/$filename';
    }
    // For other platforms or already correct paths, use the original
    return '$originalPath/$filename';
  }


  /// Cleans up orphaned files (files without corresponding SharedPrefs entry)
  Future<void> _cleanupOrphanedFiles() async {
    try {
      final prefs = await _prefs;
      final directory = await getApplicationDocumentsDirectory();

      // Get registered files from prefs
      final registeredModel = prefs.getString(_prefsModelKey);
      final registeredLora = prefs.getString(_prefsLoraKey);

      // Get all supported model files in directory
      final files = directory.listSync()
          .whereType<File>()
          .where((file) => _supportedExtensions.any((ext) => file.path.endsWith(ext)))
          .toList();

      for (final file in files) {
        final fileName = file.path.split('/').last;

        // If file is not registered in prefs - delete it
        if (fileName != registeredModel && fileName != registeredLora) {
          debugPrint('Cleaning up orphaned file: $fileName');
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup orphaned files: $e');
    }
  }

  Future<void> _ensureCleanupCompleted() async {
    if (_cleanupCompleted) return;
    await _cleanupOrphanedFiles();
    _cleanupCompleted = true;
  }

  Future<File?> get _modelFile async {
    if (_userSetModelPath case String path) return File(path);
    final directory = await getApplicationDocumentsDirectory();
    if (_modelFileName case String name) {
      // Use the correct Android path format
      final correctedPath = _getCorrectedPath(directory.path, name);
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

  @override
  Future<bool> get isModelInstalled async {
    await _ensureCleanupCompleted(); // ✅ Cleanup orphaned files on first access

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
          return;
        }),
    ]);
  }

  @override
  Future<void> setLoraWeightsPath(String path) async {
    await _loadLoraIfNeeded(() async {
      _userSetLoraPath = path;
      return;
    });
  }

  /// Downloads model from URL, uses original file name
  @override
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl, String? token}) async {
    final modelFileName = Uri.parse(url).pathSegments.last;
    _modelFileName = modelFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, modelFileName);

    final targetPath = (await _modelFile)?.path ?? "${await getApplicationDocumentsDirectory()}/$modelFileName";
    await Future.wait([
      _loadModelIfNeeded(() async => _downloadToLocalStorageWithProgress(
            assetUrl: url,
            targetPath: targetPath,
            token: token,
          )),
      if (loraUrl != null) downloadLoraWeightsFromNetwork(loraUrl),
    ]);
  }

  @override
  Stream<int> downloadModelFromNetworkWithProgress(String url, {String? loraUrl, String? token}) async* {
    final modelFileName = Uri.parse(url).pathSegments.last;
    _modelFileName = modelFileName;

    final targetPath = (await _modelFile)?.path ?? "${await getApplicationDocumentsDirectory()}/$modelFileName";

    try {
      yield* _loadModelWithProgressIfNeeded(() => _downloadToLocalStorageWithProgress(
            assetUrl: url,
            targetPath: targetPath,
            token: token,
          ));

      // ✅ Set SharedPrefs ONLY after successful download
      final prefs = await _prefs;
      await prefs.setString(_prefsModelKey, modelFileName);
    } catch (e) {
      // ✅ Cleanup partial file on error
      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
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

    final targetPath = (await _loraFile)?.path ?? "${await getApplicationDocumentsDirectory()}/$loraFileName";
    await _loadLoraIfNeeded(() async => _downloadToLocalStorageWithProgress(
          assetUrl: loraUrl,
          targetPath: targetPath,
          token: token,
        ));
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

      // ✅ Set SharedPrefs ONLY after successful asset copy
      final prefs = await _prefs;
      await prefs.setString(_prefsModelKey, modelFileName);
    } catch (e) {
      // ✅ Cleanup on error
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
    final prefs = await _prefs;

    if (_userSetModelPath != null) {
      await onDeleteModel();
      _userSetModelPath = null;
    } else if (_modelFileName case String name) {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$name');
      if (await file.exists()) {
        await onDeleteModel();
        await file.delete();
      }
    }
    await prefs.remove(_prefsModelKey);
    _modelFileName = null;
  }

  @override
  Future<void> deleteLoraWeights() async {
    _loraCompleter = null;
    final prefs = await _prefs;

    if (_userSetLoraPath != null) {
      await onDeleteLora();
      _userSetLoraPath = null;
    } else if (_loraFileName case String name) {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$name');
      if (await file.exists()) {
        await onDeleteLora();
        await file.delete();
      }
    }
    await prefs.remove(_prefsLoraKey);
    _loraFileName = null;
  }

  Stream<int> _downloadToLocalStorageWithProgress({required String assetUrl, required String targetPath, String? token}) {
    // Use HuggingFace wrapper for HF URLs to handle ETag issues
    if (HuggingFaceDownloader.isHuggingFaceUrl(assetUrl)) {
      return HuggingFaceDownloader.downloadWithProgress(
        url: assetUrl,
        targetPath: targetPath,
        token: token,
        maxRetries: 10,
      );
    }

    // Fallback to original implementation for non-HF URLs
    final progress = StreamController<int>();

    Task.split(filePath: targetPath).then((result) async {
      try {
        final (baseDirectory, directory, filename) = result;
        final task = DownloadTask(
          url: assetUrl,
          group: _downloadGroup,
          headers: token != null ? {
            'Authorization': 'Bearer $token',
            // Force HTTP/1.1 for better resume support
            'Connection': 'keep-alive',
          } : {
            'Connection': 'keep-alive',
          },
          baseDirectory: baseDirectory,
          directory: directory,
          filename: filename,
          requiresWiFi: false,
          allowPause: true,  // Enable pause for potential resume
          priority: 10,      // High priority
          retries: 10,       // Many retries for unstable network
          // Note: background_downloader will try to resume first, then restart
        );

        // Configure FileDownloader with longer timeout for large models
        final downloader = FileDownloader();

        await downloader.download(
          task,
          onProgress: (portion) {
            final percents = (portion * 100).round();
            progress.add(percents.clamp(0, 100));
          },
          onStatus: (status) {
            switch (status) {
              case TaskStatus.complete:
                if (!progress.isClosed) {
                  progress.add(100); // Ensure 100% progress
                  progress.close();
                }
                break;
              case TaskStatus.canceled:
                if (!progress.isClosed) {
                  progress.addError('Download canceled');
                  progress.close();
                }
                break;
              case TaskStatus.failed:
                if (!progress.isClosed) {
                  // Check if we can resume the failed task
                  downloader.taskCanResume(task).then((canResume) {
                    if (canResume) {
                      downloader.resume(task);
                    } else {
                      // Will be handled by retries automatically
                    }
                  }).catchError((e) {
                    progress.addError('Download failed: $e');
                    progress.close();
                  });
                } else {
                }
                break;
              case TaskStatus.paused:
                // Don't close stream on pause - let it resume
                break;
              case TaskStatus.running:
                break;
              default:
                debugPrint('Download status: $status');
                break;
            }
          },
        );
      } catch (e) {
        if (!progress.isClosed) {
          progress.addError('Download initialization failed: $e');
          progress.close();
        }
      }
    });

    return progress.stream;
  }
}
