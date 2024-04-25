// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js_util';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_gemma.dart';
import 'llm_inference_web.dart';

class Gemma extends GemmaPlugin {
  Gemma();

  static void registerWith(Registrar registrar) {
    GemmaPlugin.instance = Gemma();
  }

  LlmInference? llmInference;
  StreamController<String?>? _controller;

  final Completer<bool> _initCompleter = Completer<bool>();

  @override
  Future<bool> get isInitialized => _initCompleter.future;

  @override
  Future<void> init({
    int maxTokens = 1024,
    temperature = 1.0,
    randomSeed = 1,
    topK = 1,
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
              'baseOptions': {'modelAssetPath': 'model.bin'},
              'maxTokens': maxTokens,
              'randomSeed': randomSeed,
              'topK': topK,
              'temperature': temperature
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
