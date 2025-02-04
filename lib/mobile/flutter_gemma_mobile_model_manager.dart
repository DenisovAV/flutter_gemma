part of 'flutter_gemma_mobile.dart';

class MobileModelManager extends ModelManager {
  MobileModelManager({
    required this.onDeleteModel,
    required this.onDeleteLora,
  });

  final AsyncCallback onDeleteModel;
  final AsyncCallback onDeleteLora;

  final _largeFileHandler = LargeFileHandler();
  late final _docsDirectory = getApplicationDocumentsDirectory();

  Completer<bool>? _modelCompleter;
  Completer<bool>? _loraCompleter;

  Future<File> get _modelFile async {
    final directory = await _docsDirectory;
    return File('${directory.path}/$_modelPath');
  }

  Future<File> get _loraFile async {
    final directory = await _docsDirectory;
    return File('${directory.path}/$_loraPath');
  }

  @override
  Future<bool> get isModelLoaded async => _modelCompleter != null
      ? await _modelCompleter!.future
      : await _largeFileHandler.fileExists(targetPath: _modelPath);

  @override
  Future<bool> get isLoraLoaded async => _loraCompleter != null
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
  Future<void> loadAssetLoraWeights({required String loraPath}) {
    return _loadLora(() => _loadAsset(loraPath, _loraPath));
  }

  @override
  Future<void> loadNetworkLoraWeights({required String loraUrl}) {
    return _loadLora(() => _loadNetwork(loraUrl, _loraPath));
  }

  Future<void> _loadModel(AsyncCallback loadCallback) async {
    if (await _shouldLoadModel) {
      final completer = _modelCompleter = Completer<bool>();
      completer.complete(loadCallback().then((_) => true));
      await completer.future;
    }
  }

  Stream<int> _loadModelWithProgress(Stream<int> Function() loadCallback) async* {
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

  Future<void> _loadLora(AsyncCallback loadCallback) async {
    if (await _shouldLoadLora) {
      final completer = _loraCompleter = Completer<bool>();
      completer.complete(loadCallback().then((_) => true));
      await completer.future;
    }
  }

  @override
  Future<void> loadAssetModel({required String fullPath, String? loraPath}) async {
    await Future.wait([
      _loadModel(() => _loadAsset(fullPath, _modelPath)),
      if (loraPath != null) _loadLora(() => _loadAsset(loraPath, _loraPath)),
    ]);
  }

  @override
  Future<void> loadNetworkModel({required String url, String? loraUrl}) async {
    await Future.wait([
      _loadModel(() => _loadNetwork(url, _modelPath)),
      if (loraUrl != null) _loadLora(() => _loadAsset(loraUrl, _loraPath)),
    ]);
  }

  @override
  Stream<int> loadAssetModelWithProgress({required String fullPath, String? loraPath}) async* {
    yield* _loadModelWithProgress(() => _streamAsset(fullPath, _modelPath));
    if (loraPath != null) {
      await loadAssetLoraWeights(loraPath: loraPath);
    }
  }

  @override
  Stream<int> loadNetworkModelWithProgress({required String url, String? loraUrl}) async* {
    yield* _loadModelWithProgress(() => _streamNetwork(url, _modelPath));
    if (loraUrl != null) {
      await loadNetworkLoraWeights(loraUrl: loraUrl);
    }
  }

  @override
  Future<void> deleteLoraWeights() async {
    final lora = await _loraFile;
    if (await lora.exists()) {
      await lora.delete();
    }
  }

  @override
  Future<void> deleteModel() async {
    final model = await _modelFile;
    if (await model.exists()) {
      await onDeleteModel();
      await model.delete();
    }
  }
}
