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

  LlmInference? llmInference;
  StreamController<String?>? _controller;
  String? _path;

  final Completer<bool> _initCompleter = Completer<bool>();
  Completer<bool>? _loadCompleter;

  @override
  Future<bool> get isInitialized => _initCompleter.future;

  @override
  Future<bool> get isLoaded async => _loadCompleter != null ? await _loadCompleter!.future : false;

  Future<void> _loadModel(String path) async {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _path = path;
      _loadCompleter = Completer<bool>();
      _loadCompleter!.complete(true);
    } else {
      throw Exception('Gemma is already loading');
    }
  }

  Stream<int> _loadModelWithProgress(String path) {
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _loadCompleter = Completer<bool>();
      _path = path;
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
  Future<void> loadAssetModel({required String fullPath}) async {
    if (kReleaseMode) {
      throw UnsupportedError("Method loadAssetModelWithProgress should not be used in the release build");
    }
    await _loadModel('assets/$fullPath');
  }

  @override
  Future<void> loadNetworkModel({required String url}) async {
    await _loadModel(url);
  }

  @override
  Stream<int> loadNetworkModelWithProgress({required String url}) {
    return _loadModelWithProgress(url);
  }

  @override
  Stream<int> loadAssetModelWithProgress({required String fullPath}) {
    if (kReleaseMode) {
      throw UnsupportedError("Method loadAssetModelWithProgress should not be used in the release build");
    }
    return _loadModelWithProgress('assets/$fullPath');
  }

  @override
  Future<void> init({
    int maxTokens = 1024,
    temperature = 1.0,
    randomSeed = 1,
    topK = 1,
    int? numOfSupportedLoraRanks,
    List<int>? supportedLoraRanks,
    String? loraPath,
  }) async {
    try {
      final fileset = await promiseToFuture<FilesetResolver>(
        FilesetResolver.forGenAiTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm'),
      );
      llmInference = await promiseToFuture<LlmInference>(
        LlmInference.createFromOptions(
          fileset,
          jsify(
            {
              'baseOptions': {'modelAssetPath': _path},
              'maxTokens': maxTokens,
              'randomSeed': randomSeed,
              'topK': topK,
              'temperature': temperature,
              if (numOfSupportedLoraRanks != null) 'numOfSupportedLoraRanks': numOfSupportedLoraRanks,
              if (supportedLoraRanks != null) 'supportedLoraRanks': supportedLoraRanks,
              if (loraPath != null) 'loraPath': loraPath,
            },
          ),
        ),
      );
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete(true);
      }
    } catch (e) {
      throw Exception("Failed to initialize inference: $e");
    }
  }

  void streamPartialResults(dynamic partialResults, bool complete) {
    if (_controller != null) {
      if (complete) {
        _controller!
          ..add(null)
          ..close();
        _controller = null;
      } else {
        _controller!.add(partialResults);
      }
    }
  }

  @override
  Future<String?> getResponse({required String prompt}) async {
    if (llmInference != null) {
      return await promiseToFuture<String>(llmInference!.generateResponse(prompt, null));
    } else {
      throw Exception("Gemma is not initialized yet");
    }
  }

  @override
  Stream<String?> getResponseAsync({required String prompt}) {
    if (llmInference != null) {
      _controller = StreamController<String?>();
      llmInference!.generateResponse(
        prompt,
        allowInterop(streamPartialResults),
      );
      return _controller!.stream;
    } else {
      throw Exception("Gemma is not initialized yet");
    }
  }
}
