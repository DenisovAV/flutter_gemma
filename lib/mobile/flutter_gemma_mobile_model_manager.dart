part of 'flutter_gemma_mobile.dart';

const _prefsModelKey = 'installed_model_file_name';
const _prefsLoraKey = 'installed_lora_file_name';

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
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl}) async {
    final modelFileName = Uri.parse(url).pathSegments.last;
    _modelFileName = modelFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, modelFileName);

    await Future.wait([
      _loadModelIfNeeded(() => _largeFileHandler.copyNetworkAssetToLocalStorage(
        assetUrl: url,
        targetPath: modelFileName,
      )),
      if (loraUrl != null) downloadLoraWeightsFromNetwork(loraUrl),
    ]);
  }

  @override
  Stream<int> downloadModelFromNetworkWithProgress(String url, {String? loraUrl}) async* {
    final modelFileName = Uri.parse(url).pathSegments.last;
    _modelFileName = modelFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, modelFileName);

    yield* _loadModelWithProgressIfNeeded(() => _largeFileHandler.copyNetworkAssetToLocalStorageWithProgress(
      assetUrl: url,
      targetPath: modelFileName,
    ));

    if (loraUrl != null) {
      await downloadLoraWeightsFromNetwork(loraUrl);
    }
  }

  @override
  Future<void> downloadLoraWeightsFromNetwork(String loraUrl) async {
    final loraFileName = Uri.parse(loraUrl).pathSegments.last;
    _loraFileName = loraFileName;

    final prefs = await _prefs;
    await prefs.setString(_prefsLoraKey, loraFileName);

    await _loadLoraIfNeeded(() => _largeFileHandler.copyNetworkAssetToLocalStorage(
      assetUrl: loraUrl,
      targetPath: loraFileName,
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

    final prefs = await _prefs;
    await prefs.setString(_prefsModelKey, modelFileName);

    yield* _loadModelWithProgressIfNeeded(() => _largeFileHandler.copyAssetToLocalStorageWithProgress(
      assetName: path,
      targetPath: modelFileName,
    ));

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
}