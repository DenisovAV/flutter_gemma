// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_gemma.dart';
import 'llm_inference_web.dart';

class GemmaWeb extends Gemma {
  GemmaWeb();

  static void registerWith(Registrar registrar) {
    Gemma.instance = GemmaWeb();
  }

  LlmInference? llmInference;

  @override
  Future<void> init({
    int maxTokens = 1024,
    temperature = 1.0,
    randomSeed = 1,
    topK = 1,
  }) async {
    final fileset = await FilesetResolver.forGenAiTasks('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm');
    llmInference = await LlmInference.createFromOptions(
        fileset,
        jsify({
          'baseOptions': {'modelAssetPath': 'https://firebasestorage.googleapis.com/v0/b/test-bf329.appspot.com/o/model.bin?alt=media&token=b2264a47-ab39-4282-8b3d-b26e46cec8c1'},
          'maxTokens': maxTokens,
          'randomSeed': randomSeed,
          'topK': topK,
          'temperature': temperature
        }));
  }

  @override
  Future<String?> getResponse({required String prompt}) async {
    if (llmInference != null) {
      return await llmInference!.generateResponse(prompt);
    } else {
      return 'Gemma is not initialized yet';
    }
  }
}
