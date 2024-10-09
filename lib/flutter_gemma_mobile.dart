import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';

import 'flutter_gemma.dart';

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
  Future<bool> get isLoaded async => _loadCompleter != null ? await _loadCompleter!.future : false;

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
  }) {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _loadCompleter = Completer<bool>();
      final stream = loadFunction().asBroadcastStream()
        ..listen(
          (_) {},
          onDone: () {
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
  Future<void> loadAssetModel({required String fullPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError("Method loadAssetModel should not be used in the release build");
    }
    return _loadModel(
      loadFunction: () => _largeFileHandler.copyAssetToLocalStorage(
        assetName: fullPath,
        targetPath: 'model.bin',
      ),
    );
  }

  @override
  Future<void> loadNetworkModel({required String url}) async {
    return _loadModel(
      loadFunction: () => _largeFileHandler.copyNetworkAssetToLocalStorage(
        assetUrl: url,
        targetPath: 'model.bin',
      ),
    );
  }

  @override
  Stream<int> loadAssetModelWithProgress({required String fullPath}) {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    return _loadModelWithProgress(
      loadFunction: () => _largeFileHandler.copyAssetToLocalStorageWithProgress(
        assetName: fullPath,
        targetPath: 'model.bin',
      ),
    );
  }

  @override
  Stream<int> loadNetworkModelWithProgress({required String url}) {
    return _loadModelWithProgress(
      loadFunction: () => _largeFileHandler.copyNetworkAssetToLocalStorageWithProgress(
        assetUrl: url,
        targetPath: 'model.bin',
      ),
    );
  }

  @override
  Future<void> init({
    int maxTokens = 1024,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 1,
  }) async {
    if (_loadCompleter != null && _loadCompleter!.isCompleted) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final result = await methodChannel.invokeMethod<bool>(
              'init',
              {
                'modelPath': '${directory.path}/model.bin',
                'maxTokens': maxTokens,
                'temperature': temperature,
                'randomSeed': randomSeed,
                'topK': topK,
              },
            ) ??
            false;

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
      return await methodChannel.invokeMethod<String>('getGemmaResponse', {'prompt': prompt});
    } else {
      throw Exception('Gemma is not initialized yet');
    }
  }

  @override
  Stream<String?> getResponseAsync({required String prompt}) {
    if (_initCompleter.isCompleted) {
      methodChannel.invokeMethod('getGemmaResponseAsync', {'prompt': prompt});
      return eventChannel.receiveBroadcastStream().map<String?>((event) => event as String?);
    } else {
      throw Exception('Gemma is not initialized yet');
    }
  }
}
