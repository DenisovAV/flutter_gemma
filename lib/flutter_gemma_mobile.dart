import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'flutter_gemma.dart';

const _modelPath = 'model.bin';
const _loraPath = 'lora.bin';

class FlutterGemma extends FlutterGemmaPlugin {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_gemma');
  @visibleForTesting
  final eventChannel = const EventChannel('flutter_gemma_stream');

  final Completer<bool> _initCompleter = Completer<bool>();
  Completer<bool>? _loadCompleter;
  final _largeFileHandler = LargeFileHandler();

  @override
  Future<bool> get isInitialized => _initCompleter.future;

  @override
  Future<bool> get isLoaded async =>
      _loadCompleter != null ? await _loadCompleter!.future : await _largeFileHandler.fileExists(targetPath: _modelPath);

  @override
  Future<bool> get isLoraLoaded async => await isLoaded && await _largeFileHandler.fileExists(targetPath: _loraPath);

  Future<void> _loadNetwork(String url, String target) => _largeFileHandler.copyNetworkAssetToLocalStorage(
        assetUrl: url,
        targetPath: target,
      );

  Future<void> _loadAsset(String path, String target) => _largeFileHandler.copyAssetToLocalStorage(
        assetName: path,
        targetPath: target,
      );

  Stream<int> _streamNetwork(String url, String target) => _largeFileHandler.copyNetworkAssetToLocalStorageWithProgress(
        assetUrl: url,
        targetPath: target,
      );

  Stream<int> _streamAsset(String path, String target) => _largeFileHandler.copyAssetToLocalStorageWithProgress(
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
  Future<void> loadNetworkLoraWeights({required String loraUrl}) => _loadNetwork(loraUrl, _loraPath);

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
      throw UnsupportedError("Method loadAssetModelWithProgress should not be used in the release build");
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

  @override
  Future<void> init({
    int maxTokens = 1024,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 1,
  }) async {
    if (await isLoaded) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final loraPath = await isLoraLoaded ? '${directory.path}/$_loraPath' : null;

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

        if (result && !_initCompleter.isCompleted) {
          _initCompleter.complete(true);
        } else if (!_initCompleter.isCompleted) {
          _initCompleter.completeError('Initialization failed');
        }
      } on PlatformException catch (e) {
        if (!_initCompleter.isCompleted) {
          _initCompleter.completeError('Platform error: ${e.message}');
        }
      } catch (e) {
        if (!_initCompleter.isCompleted) {
          _initCompleter.completeError('Error: $e');
        }
      }
    } else {
      throw Exception('Gemma is not loaded yet');
    }
  }

  @override
  Future<String?> getResponse({required String prompt}) async {
    if (_initCompleter.isCompleted) {
      try {
        return await methodChannel.invokeMethod<String>('getGemmaResponse', {'prompt': prompt});
      } on PlatformException catch (e) {
        throw Exception('Platform error: ${e.message}');
      } catch (e) {
        throw Exception('Error: $e');
      }
    } else {
      throw Exception('Gemma is not initialized yet');
    }
  }

  @override
  Stream<String?> getResponseAsync({required String prompt}) {
    if (_initCompleter.isCompleted) {
      final StreamController<String?> controller = StreamController<String?>();

      eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map && event.containsKey('code') && event['code'] == "ERROR") {
            controller.addError(Exception(event['message'] ?? 'Unknown async error occurred'));
          } else {
            controller.add(event as String?);
          }
        },
        onError: (error) {
          controller.addError(Exception('Stream error: $error'));
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
    } else {
      throw Exception('Gemma is not initialized yet');
    }
  }
}
