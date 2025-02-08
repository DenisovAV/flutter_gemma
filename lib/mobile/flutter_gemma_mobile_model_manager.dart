part of 'flutter_gemma_mobile.dart';

const _modelPath = 'model.bin';
const _loraPath = 'lora.bin';

class MobileModelManager extends ModelFileManager {
  MobileModelManager({
    required this.onDeleteModel,
    required this.onDeleteLora,
  });

  final AsyncCallback onDeleteModel;
  final AsyncCallback onDeleteLora;

  final _largeFileHandler = LargeFileHandler();
  late final _docsDirectory = getApplicationDocumentsDirectory();

  String? _userSetModelPath;
  String? _userSetLoraPath;

  Completer<bool>? _modelCompleter;
  Completer<bool>? _loraCompleter;

  Future<File> get _modelFile async {
    if (_userSetModelPath case String path) return File(path);
    final directory = await _docsDirectory;
    return File('${directory.path}/$_modelPath');
  }

  Future<File> get _loraFile async {
    if (_userSetLoraPath case String path) return File(path);
    final directory = await _docsDirectory;
    return File('${directory.path}/$_loraPath');
  }

  @override
  Future<bool> get isModelInstalled async => _modelCompleter != null
      ? await _modelCompleter!.future
      : await _largeFileHandler.fileExists(targetPath: _modelPath);

  @override
  Future<bool> get isLoraInstalled async => _loraCompleter != null
      ? await _loraCompleter!.future
      : await _largeFileHandler.fileExists(targetPath: _loraPath);

  Future<void> _loadNetwork(String url, String target) =>
      _largeFileHandler.copyNetworkAssetToLocalStorage(
        assetUrl: url,
        targetPath: target,
      );

  Future<void> _loadAsset(String path, String target) => _largeFileHandler.copyAssetToLocalStorage(
        assetName: path,
        targetPath: target,
      );

  Stream<int> _streamNetwork(String url, String target) =>
      _largeFileHandler.copyNetworkAssetToLocalStorageWithProgress(
        assetUrl: url,
        targetPath: target,
      );

  Stream<int> _streamAsset(String path, String target) =>
      _largeFileHandler.copyAssetToLocalStorageWithProgress(
        assetName: path,
        targetPath: target,
      );

  Future<bool> get _shouldLoadModel async {
    final completer = _modelCompleter;
    if (completer != null) {
      return completer.isCompleted ? false : throw Exception('Model is already loading');
    }
    final modelFile = await _modelFile;
    // Do not reload model if it's already exists.
    if (await modelFile.exists()) return false;
    return true;
  }

  Future<bool> get _shouldLoadLora async {
    final completer = _loraCompleter;
    if (completer != null) {
      return completer.isCompleted ? false : throw Exception('Lora weights are already loading');
    }
    final loraFile = await _loraFile;
    // Do not reload lora weights if it's already exists.
    if (await loraFile.exists()) return false;
    return true;
  }

  @override
  Future<void> installLoraWeightsFromAsset(String path) {
    return _loadLoraIfNeeded(() => _loadAsset(path, _loraPath));
  }

  @override
  Future<void> downloadLoraWeightsFromNetwork(String loraUrl) {
    return _loadLoraIfNeeded(() => _loadNetwork(loraUrl, _loraPath));
  }

  Future<void> _loadModelIfNeeded(AsyncCallback loadCallback) async {
    if (await _shouldLoadModel) {
      final completer = _modelCompleter = Completer<bool>();
      completer.complete(loadCallback().then((_) => true));
      await completer.future;
    }
  }

  Stream<int> _loadModelWithProgressIfNeeded(Stream<int> Function() loadCallback) async* {
    if (await _shouldLoadModel) {
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
  }

  Future<void> _loadLoraIfNeeded(AsyncCallback loadCallback) async {
    if (await _shouldLoadLora) {
      final completer = _loraCompleter = Completer<bool>();
      completer.complete(loadCallback().then((_) => true));
      await completer.future;
    }
  }

  @override
  Future<void> setModelPath(String path, {String? loraPath}) async {
    await Future.wait([
      _loadModelIfNeeded(() async => _userSetModelPath = path),
      if (loraPath != null) _loadLoraIfNeeded(() async => _userSetLoraPath = loraPath),
    ]);
  }

  @override
  Future<void> setLoraWeightsPath(String path) {
    return _loadLoraIfNeeded(() async => _userSetLoraPath = path);
  }

  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    await Future.wait([
      _loadModelIfNeeded(() => _loadAsset(path, _modelPath)),
      if (loraPath != null) _loadLoraIfNeeded(() => _loadAsset(loraPath, _loraPath)),
    ]);
  }

  @override
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl}) async {
    await Future.wait([
      _loadModelIfNeeded(() => _loadNetwork(url, _modelPath)),
      if (loraUrl != null) _loadLoraIfNeeded(() => _loadAsset(loraUrl, _loraPath)),
    ]);
  }

  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) async* {
    yield* _loadModelWithProgressIfNeeded(() => _streamAsset(path, _modelPath));
    if (loraPath != null) {
      await installLoraWeightsFromAsset(loraPath);
    }
  }

  @override
  Stream<int> downloadModelFromNetworkWithProgress(String url, {String? loraUrl}) async* {
    yield* _loadModelWithProgressIfNeeded(() => _streamNetwork(url, _modelPath));
    if (loraUrl != null) {
      await downloadLoraWeightsFromNetwork(loraUrl);
    }
  }

  @override
  Future<void> deleteLoraWeights() async {
    _loraCompleter = null;
    if (_userSetLoraPath != null) {
      onDeleteLora();
      _userSetLoraPath = null;
    } else {
      final lora = await _loraFile;
      if (await lora.exists()) {
        onDeleteLora();
        await lora.delete();
      }
    }
  }

  @override
  Future<void> deleteModel() async {
    _modelCompleter = null;
    if (_userSetModelPath != null) {
      await onDeleteModel();
      _userSetModelPath = null;
    } else {
      final model = await _modelFile;
      if (await model.exists()) {
        await onDeleteModel();
        await model.delete();
      }
    }
  }
}
