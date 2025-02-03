import 'dart:async';
import 'dart:js_util';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_gemma.dart';
import 'llm_inference_web.dart';

class FlutterGemmaWeb extends FlutterGemmaPlugin {
  FlutterGemmaWeb();

  static void registerWith(Registrar registrar) {
    FlutterGemmaPlugin.instance = FlutterGemmaWeb();
  }

  @override
  final WebModelManager modelManager = WebModelManager();
  @override
  InferenceModel? get initializedModel => _initializedModel;

  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;

  @override
  Future<InferenceModel> init({
    int maxTokens = 1024,
    temperature = 1.0,
    randomSeed = 1,
    topK = 1,
    List<int>? supportedLoraRanks,
  }) async {
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModel>();
    try {
      final fileset = await promiseToFuture<FilesetResolver>(
        FilesetResolver.forGenAiTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm'),
      );
      final llmInference = await promiseToFuture<LlmInference>(
        LlmInference.createFromOptions(
          fileset,
          jsify(
            {
              'baseOptions': {'modelAssetPath': modelManager._path},
              'maxTokens': maxTokens,
              'randomSeed': randomSeed,
              'topK': topK,
              'temperature': temperature,
              if (modelManager._loraPath != null) ...{
                'supportedLoraRanks': supportedLoraRanks,
                'loraPath': modelManager._loraPath,
              },
            },
          ),
        ),
      );
      final model = _initializedModel = WebInferenceModel(
        llmInference: llmInference,
        onClose: () {
          _initCompleter = null;
          _initializedModel = null;
        },
      );
      completer.complete(model);
      return model;
    } catch (e) {
      throw Exception("Failed to initialize inference: $e");
    }
  }
}

class WebInferenceModel extends InferenceModel {
  final LlmInference llmInference;
  final VoidCallback onClose;
  StreamController<String>? _controller;

  WebInferenceModel({required this.llmInference, required this.onClose});

  @override
  Future<String> getResponse({required String prompt}) async {
    return await promiseToFuture<String>(llmInference.generateResponse(prompt, null));
  }

  @override
  Stream<String> getResponseAsync({required String prompt}) {
    _controller = StreamController<String>();
    llmInference.generateResponse(
      prompt,
      allowInterop(_streamPartialResults),
    );
    return _controller!.stream;
  }

  void _streamPartialResults(dynamic partialResults, bool complete) {
    if (_controller != null) {
      if (complete) {
        _controller!.close();
        _controller = null;
      } else {
        _controller!.add(partialResults);
      }
    }
  }

  @override
  Future<void> close() {
    onClose();
    throw UnimplementedError();
  }
}

class WebModelManager extends ModelManager {
  Completer<bool>? _loadCompleter;
  String? _path;
  String? _loraPath;

  @override
  Future<bool> get isLoaded async => _loadCompleter != null ? await _loadCompleter!.future : false;

  @override
  Future<bool> get isLoraLoaded async => await isLoaded;

  Future<void> _loadModel(String path, String? loraPath) async {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _path = path;
      _loraPath = loraPath;
      _loadCompleter = Completer<bool>();
      _loadCompleter!.complete(true);
    } else {
      throw Exception('Gemma is already loading');
    }
  }

  Stream<int> _loadModelWithProgress(String path, String? loraPath) {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _loadCompleter = Completer<bool>();
      _path = path;
      _loraPath = loraPath;
      return Stream<int>.periodic(
        const Duration(milliseconds: 10),
        (count) => count + 1,
      ).take(100).map((progress) {
        if (progress == 100 && !_loadCompleter!.isCompleted) {
          _loadCompleter!.complete(true);
        }
        return progress;
      }).asBroadcastStream();
    } else {
      throw Exception('Gemma is already loading');
    }
  }

  @override
  Future<void> loadAssetLoraWeights({required String loraPath}) async {
    _loraPath = 'assets/$loraPath';
  }

  @override
  Future<void> loadNetworkLoraWeights({required String loraUrl}) async {
    _loraPath = loraUrl;
  }

  @override
  Future<void> loadAssetModel({required String fullPath, String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    await _loadModel('assets/$fullPath', loraPath != null ? 'assets/$loraPath' : null);
  }

  @override
  Future<void> loadNetworkModel({required String url, String? loraUrl}) async {
    await _loadModel(url, loraUrl);
  }

  @override
  Stream<int> loadNetworkModelWithProgress({required String url, String? loraUrl}) {
    return _loadModelWithProgress(url, loraUrl);
  }

  @override
  Stream<int> loadAssetModelWithProgress({required String fullPath, String? loraPath}) {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    return _loadModelWithProgress('assets/$fullPath', loraPath != null ? 'assets/$loraPath' : null);
  }

  @override
  Future<void> deleteModel() {
    _loraPath = null;
    _path = null;
    _loadCompleter = null;
    return Future.value();
  }
}
