import 'dart:async';

import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_gemma_mobile.dart';

const supportedLoraRanks = [4, 8, 16];

abstract class FlutterGemmaPlugin extends PlatformInterface {
  /// Constructs a FlutterGemmaPlatform.
  FlutterGemmaPlugin() : super(token: _token);

  static final Object _token = Object();

  static FlutterGemmaPlugin _instance = FlutterGemma();

  Future<bool> get isInitialized;

  Future<bool> get isLoaded;

  Future<bool> get isLoraLoaded;

  /// The default instance of [FlutterGemmaPlugin] to use.
  ///
  /// Defaults to [FlutterGemma].
  static FlutterGemmaPlugin get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterGemmaPlugin] when
  /// they register themselves.
  static set instance(FlutterGemmaPlugin instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> loadAssetModel({required String fullPath, String? loraPath});

  Future<void> loadAssetLoraWeights({required String loraPath});

  Future<void> loadNetworkModel({required String url, String? loraUrl});

  Future<void> loadNetworkLoraWeights({required String loraUrl});

  Stream<int> loadAssetModelWithProgress({required String fullPath, String? loraPath});

  Stream<int> loadNetworkModelWithProgress({required String url, String? loraUrl});

  Future<void> init({
    int maxTokens,
    double temperature,
    int randomSeed,
    int topK,
  });

  Future<String?> getResponse({required String prompt});

  Stream<String?> getResponseAsync({required String prompt});

  //These methods works fine with instruction tuned models only
  Future<String?> getChatResponse({required Iterable<Message> messages, int chatContextLength = 3}) =>
      getResponse(prompt: messages.transformToChatPrompt(contextLength: chatContextLength));

  Stream<String?> getChatResponseAsync({required Iterable<Message> messages, int chatContextLength = 3}) {
    return getResponseAsync(prompt: messages.transformToChatPrompt(contextLength: chatContextLength));
  }

  /// Closes and cleans up the llm inference.
  /// This method should be called when the inference is no longer needed.
  /// [init] should be called again to use the inference.
  Future<void> close();
}
