part of 'flutter_gemma_mobile.dart';

const _prefsModelKey = 'installed_model_file_name';
const _prefsLoraKey = 'installed_lora_file_name';
const _downloadGroup = 'flutter_gemma_downloads';

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

  /// Cleans up orphaned files (files without corresponding SharedPrefs entry)
  Future<void> _cleanupOrphanedFiles() async {
    try {
      final prefs = await _prefs;
      final directory = await getApplicationDocumentsDirectory();
      
      // Get registered files from prefs
      final registeredModel = prefs.getString(_prefsModelKey);
      final registeredLora = prefs.getString(_prefsLoraKey);
      
      // Get all .task and .bin files in directory
      final files = directory.listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.task') || file.path.endsWith('.bin'))
          .toList();
      
      for (final file in files) {
        final fileName = file.path.split('/').last;
        
        // If file is not registered in prefs - delete it
        if (fileName != registeredModel && fileName != registeredLora) {
          print('Cleaning up orphaned file: $fileName');
          await file.delete();
        }
      }
    } catch (e) {
      print('Failed to cleanup orphaned files: $e');
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
      return File('${directory.path}/$name');
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
        _userSetModelPath = path;
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
    final progress = StreamController<int>();

    Task.split(filePath: targetPath).then((result) async {
      try {
        final (baseDirectory, directory, filename) = result;
        final task = DownloadTask(
          url: assetUrl,
          group: _downloadGroup,
          headers: token != null ? {'Authorization': 'Bearer $token'} : {},
          baseDirectory: baseDirectory,
          directory: directory,
          filename: filename,
        );

        await FileDownloader().download(
          task,
          onProgress: (portion) {
            final percents = (portion * 100).round();
            progress.add(percents.clamp(0, 100));
          },
          onStatus: (status) {
            switch (status) {
              case TaskStatus.complete:
                progress.close();
                break;
              case TaskStatus.canceled:
                progress.addError('Download canceled');
                progress.close();
                break;
              case TaskStatus.failed:
                progress.addError('Download failed');
                progress.close();
                break;
              case TaskStatus.paused:
                progress.addError('Download paused');
                progress.close();
                break;
              default:
                // No action needed for other statuses
                break;
            }
          },
        );
      } catch (e) {
        progress.addError('Download initialization failed: $e');
        progress.close();
      }
    });

    return progress.stream;
  }
}