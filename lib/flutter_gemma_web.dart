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

  InferenceModel? _initializedModel;

  @override
  Future<InferenceModel> createModel({
    required bool isInstructionTuned,
    int maxTokens = 1024,
    List<int>? supportedLoraRanks,
  }) {
    final model = _initializedModel ??= WebInferenceModel(
      maxTokens: maxTokens,
      supportedLoraRanks: supportedLoraRanks,
      modelManager: modelManager,
      onClose: () {
        _initializedModel = null;
      },
    );
    return Future.value(model);
  }
}

class WebInferenceModel extends InferenceModel {
  final VoidCallback onClose;
  final int maxTokens;
  final List<int>? supportedLoraRanks;
  final WebModelManager modelManager;
  Completer<InferenceModelSession>? _initCompleter;
  @override
  InferenceModelSession? session;

  WebInferenceModel({
    required this.onClose,
    required this.maxTokens,
    this.supportedLoraRanks,
    required this.modelManager,
  });

  @override
  Future<InferenceModelSession> createSession({
    temperature = .8,
    randomSeed = 1,
    topK = 1,
  }) async {
    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      final fileset = await promiseToFuture<FilesetResolver>(
        FilesetResolver.forGenAiTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm'),
      );
      final llmInference = await promiseToFuture<LlmInference>(
        LlmInference.createFromOptions(
          fileset,
          jsify({
            'baseOptions': {'modelAssetPath': modelManager._path},
            'maxTokens': maxTokens,
            'randomSeed': randomSeed,
            'topK': topK,
            'temperature': temperature,
            if (modelManager._loraPath != null) ...{
              'supportedLoraRanks': supportedLoraRanks,
              'loraPath': modelManager._loraPath,
            },
          }),
        ),
      );
      final session = this.session = WebModelSession(
        llmInference: llmInference,
        onClose: onClose,
      );
      completer.complete(session);
      return session;
    } catch (e) {
      throw Exception("Failed to create session: $e");
    }
  }

  @override
  Future<void> close() async {
    await session?.close();
  }
}

class WebModelSession extends InferenceModelSession {
  final LlmInference llmInference;
  final VoidCallback onClose;
  StreamController<String>? _controller;

  WebModelSession({required this.llmInference, required this.onClose});

  @override
  Future<String> getResponse(String prompt) async {
    return await promiseToFuture<String>(llmInference.generateResponse(prompt, null));
  }

  @override
  Stream<String> getResponseAsync(String prompt) {
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

class WebModelManager extends ModelFileManager {
  Completer<bool>? _loadCompleter;
  String? _path;
  String? _loraPath;

  @override
  Future<bool> get isModelInstalled async =>
      _loadCompleter != null ? await _loadCompleter!.future : false;

  @override
  Future<bool> get isLoraInstalled async => await isModelInstalled;

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
  Future<void> installLoraWeightsFromAsset(String path) async {
    _loraPath = 'assets/$path';
  }

  @override
  Future<void> downloadLoraWeightsFromNetwork(String loraUrl) async {
    _loraPath = loraUrl;
  }

  @override
  Future<void> installModelFromAsset(String path, {String? loraPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    await _loadModel('assets/$path', loraPath != null ? 'assets/$loraPath' : null);
  }

  @override
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl}) async {
    await _loadModel(url, loraUrl);
  }

  @override
  Stream<int> downloadModelFromNetworkWithProgress(String url, {String? loraUrl}) {
    return _loadModelWithProgress(url, loraUrl);
  }

  @override
  Stream<int> installModelFromAssetWithProgress(String path, {String? loraPath}) {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    return _loadModelWithProgress('assets/$path', loraPath != null ? 'assets/$loraPath' : null);
  }

  @override
  Future<void> deleteModel() {
    _path = null;
    _loadCompleter = null;
    return Future.value();
  }

  @override
  Future<void> deleteLoraWeights() {
    _loraPath = null;
    return Future.value();
  }

  @override
  Future<void> setLoraWeightsPath(String path) {
    _loraPath = path;
    return Future.value();
  }

  @override
  Future<void> setModelPath(String path, {String? loraPath}) {
    _path = path;
    _loraPath = loraPath;
    return Future.value();
  }
}
