import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'flutter_gemma.dart';

const _modelPath = 'model.bin';
const _loraPath = 'lora.bin';

@visibleForTesting
const methodChannel = MethodChannel('flutter_gemma');
@visibleForTesting
const eventChannel = EventChannel('flutter_gemma_stream');

class FlutterGemma extends FlutterGemmaPlugin {
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;

  @override
  final modelManager = MobileModelManager();

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  Future<InferenceModel> init({
    int maxTokens = 1024,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 1,
  }) async {
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModel>();
    if (await modelManager.isLoaded) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final loraPath = await modelManager.isLoraLoaded ? '${directory.path}/$_loraPath' : null;

        final arguments = {
          'modelPath': '${directory.path}/$_modelPath',
          'maxTokens': maxTokens,
          'temperature': temperature,
          'randomSeed': randomSeed,
          'topK': topK,
          if (loraPath != null) ...{
            'loraPath': loraPath,
            'supportedLoraRanks': supportedLoraRanks,
          },
        };

        final result = await methodChannel.invokeMethod<bool>('init', arguments) ?? false;
        if (!result) {
          throw Exception('Initialization failed');
        }
        final model = _initializedModel = MobileInferenceModel(
          onClose: () {
            _initializedModel = null;
            _initCompleter = null;
          },
        );
        completer.complete(model);
        return model;
      } catch (e, st) {
        completer.completeError(e, st);
        Error.throwWithStackTrace(e, st);
      }
    } else {
      throw Exception(
        'Gemma Model is not loaded yet. User the `modelManager` to load the model first',
      );
    }
  }
}

class MobileModelManager extends ModelManager {
  Completer<bool>? _loadCompleter;
  final _largeFileHandler = LargeFileHandler();

  @override
  Future<void> deleteModel() {
    throw UnimplementedError();
  }

  @override
  Future<bool> get isLoaded async => _loadCompleter != null
      ? await _loadCompleter!.future
      : await _largeFileHandler.fileExists(targetPath: _modelPath);

  @override
  Future<bool> get isLoraLoaded async =>
      await isLoaded && await _largeFileHandler.fileExists(targetPath: _loraPath);

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

  Future<void> _loadModel({
    required Future<void> Function() loadFunction,
  }) async {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _loadCompleter = Completer<bool>();
      try {
        await loadFunction();
        _loadCompleter?.complete(true);
      } catch (error) {
        _loadCompleter?.completeError(error);
        rethrow;
      }
    } else {
      throw Exception('Gemma is already loading');
    }
  }

  Stream<int> _loadModelWithProgress({
    required Stream<int> Function() loadFunction,
    Future<void> Function()? postLoadFunction,
  }) {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _loadCompleter = Completer<bool>();
      final stream = loadFunction().asBroadcastStream()
        ..listen(
          (_) {},
          onDone: () async {
            await postLoadFunction?.call();
            _loadCompleter?.complete(true);
          },
          onError: (error) {
            _loadCompleter?.completeError(error);
          },
        );
      return stream;
    } else {
      throw Exception('Gemma is already loading');
    }
  }

  @override
  Future<void> loadAssetLoraWeights({required String loraPath}) => _loadAsset(loraPath, _loraPath);

  @override
  Future<void> loadNetworkLoraWeights({required String loraUrl}) =>
      _loadNetwork(loraUrl, _loraPath);

  @override
  Future<void> loadAssetModel({required String fullPath, String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError("Method loadAssetModel should not be used in the release build");
    }
    return _loadModel(
        loadFunction: () => Future.wait([
              _loadAsset(fullPath, _modelPath),
              if (loraPath != null) _loadAsset(loraPath, _loraPath),
            ]));
  }

  @override
  Future<void> loadNetworkModel({required String url, String? loraUrl}) async {
    return _loadModel(
      loadFunction: () => Future.wait([
        _loadNetwork(url, _modelPath),
        if (loraUrl != null) _loadAsset(loraUrl, _loraPath),
      ]),
    );
  }

  @override
  Stream<int> loadAssetModelWithProgress({required String fullPath, String? loraPath}) {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    return _loadModelWithProgress(
        loadFunction: () => _streamAsset(
              fullPath,
              _modelPath,
            ),
        postLoadFunction: loraPath != null ? () => _loadAsset(loraPath, _loraPath) : null);
  }

  @override
  Stream<int> loadNetworkModelWithProgress({required String url, String? loraUrl}) {
    return _loadModelWithProgress(
        loadFunction: () => _streamNetwork(
              url,
              _modelPath,
            ),
        postLoadFunction: loraUrl != null ? () => _loadNetwork(loraUrl, _loraPath) : null);
  }
}

class MobileInferenceModel extends InferenceModel {
  final VoidCallback onClose;
  bool _isClosed = false;

  MobileInferenceModel({required this.onClose});

  void _assertNotClosed() {
    if (_isClosed) {
      throw Exception('Model is closed. Create a new instance to use it again');
    }
  }

  @override
  Future<String> getResponse({required String prompt}) async {
    _assertNotClosed();
    final response = await methodChannel.invokeMethod<String>(
      'getGemmaResponse',
      {'prompt': prompt},
    );
    if (response == null) {
      throw Exception('Response is null. This should not happen');
    }
    return response;
  }

  @override
  Stream<String> getResponseAsync({required String prompt}) {
    final StreamController<String> controller = StreamController<String>();

    eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map && event.containsKey('code') && event['code'] == "ERROR") {
          controller.addError(Exception(event['message'] ?? 'Unknown async error occurred'));
        } else if (event is String) {
          controller.add(event);
        } else {
          controller.addError(Exception('Unknown event type: $event'));
        }
      },
      onError: (error, st) {
        controller.addError(error, st);
      },
      onDone: controller.close,
    );

    methodChannel.invokeMethod('getGemmaResponseAsync', {'prompt': prompt}).catchError((error) {
      if (error is PlatformException) {
        controller.addError(Exception('Platform error: ${error.message}'));
      } else {
        controller.addError(Exception('Unknown invoke error: $error'));
      }
    });

    return controller.stream;
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    onClose();
    await methodChannel.invokeMethod('close');
  }
}
