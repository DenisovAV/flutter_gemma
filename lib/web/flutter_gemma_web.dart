import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

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
    required ModelType modelType,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
  }) {
    final model = _initializedModel ??= WebInferenceModel(
      modelType: modelType,
      maxTokens: maxTokens,
      loraRanks: loraRanks,
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
  @override
  final int maxTokens;

  final ModelType modelType;
  final List<int>? loraRanks;
  final WebModelManager modelManager;
  Completer<InferenceModelSession>? _initCompleter;
  @override
  InferenceModelSession? session;

  WebInferenceModel({
    required this.modelType,
    required this.onClose,
    required this.maxTokens,
    this.loraRanks,
    required this.modelManager,
  });

  @override
  Future<InferenceModelSession> createSession({
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
  }) async {
    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      final fileset = await FilesetResolver.forGenAiTasks(
              'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm'.toJS)
          .toDart;

      final loraPathToUse = loraPath ?? modelManager._loraPath;
      final hasLoraParams = loraPathToUse != null && loraRanks != null;

      final config = LlmInferenceOptions(
        baseOptions:
            LlmInferenceBaseOptions(modelAssetPath: modelManager._path),
        maxTokens: maxTokens,
        randomSeed: randomSeed,
        topK: topK,
        temperature: temperature,
        topP: topP,
        supportedLoraRanks:
            !hasLoraParams ? null : Int32List.fromList(loraRanks!).toJS,
        loraPath: !hasLoraParams ? null : loraPathToUse,
      );

      final llmInference =
          await LlmInference.createFromOptions(fileset, config).toDart;

      final session = this.session = WebModelSession(
        modelType: modelType,
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
    session = null;
    onClose();
  }
}

class WebModelSession extends InferenceModelSession {
  final ModelType modelType;
  final LlmInference llmInference;
  final VoidCallback onClose;
  StreamController<String>? _controller;
  final List<String> _queryChunks = [];

  WebModelSession({
    required this.llmInference,
    required this.onClose,
    required this.modelType,
  });

  @override
  Future<int> sizeInTokens(String text) async {
    final size = llmInference.sizeInTokens(text.toJS);
    return size.toDartInt;
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    final finalPrompt = message.transformToChatPrompt(type: modelType);
    _queryChunks.add(finalPrompt);
  }

  @override
  Future<String> getResponse() async {
    final String fullPrompt = _queryChunks.join(" ");
    final response =
        (await llmInference.generateResponse(fullPrompt.toJS, null).toDart)
            .toDart;
    await addQueryChunk(Message(text: response, isUser: false));
    return response;
  }

  @override
  Stream<String> getResponseAsync() {
    _controller = StreamController<String>();

    final String fullPrompt = _queryChunks.join(" ");
    final List<String> responseBuffer = [];

    llmInference.generateResponse(
      fullPrompt.toJS,
      ((JSString partialJs, JSAny completeRaw) {
        final complete = completeRaw.parseBool();
        final partial = partialJs.toDart;

        responseBuffer.add(partial);
        _controller?.add(partial);
        if (complete) {
          final String fullResponse = responseBuffer.join("");
          addQueryChunk(Message(text: fullResponse, isUser: false));
          _controller?.close();
          _controller = null;
        }
      }).toJS,
    );

    return _controller!.stream;
  }

  @override
  Future<void> cancelGenerateResponseAsync() async {
    // Dummy implementation for web - cancellation not supported by MediaPipe web SDK yet
  }

  @override
  Future<void> close() async {
    _queryChunks.clear();
    _controller?.close();
    _controller = null;
    onClose();
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
    await _loadModel(
        'assets/$path', loraPath != null ? 'assets/$loraPath' : null);
  }

  @override
  Future<void> downloadModelFromNetwork(String url, {String? loraUrl}) async {
    await _loadModel(url, loraUrl);
  }

  @override
  Stream<int> downloadModelFromNetworkWithProgress(String url,
      {String? loraUrl}) {
    return _loadModelWithProgress(url, loraUrl);
  }

  @override
  Stream<int> installModelFromAssetWithProgress(String path,
      {String? loraPath}) {
    if (kReleaseMode) {
      throw UnsupportedError(
          "Method loadAssetModelWithProgress should not be used in the release build");
    }
    return _loadModelWithProgress(
        'assets/$path', loraPath != null ? 'assets/$loraPath' : null);
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
