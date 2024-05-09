import 'dart:async';

import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_gemma_mobile.dart';

abstract class FlutterGemmaPlugin extends PlatformInterface {
  /// Constructs a FlutterGemmaPlatform.
  FlutterGemmaPlugin() : super(token: _token);

  static final Object _token = Object();

  static FlutterGemmaPlugin _instance = FlutterGemma();

  Future<bool> get isInitialized;

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

  Future<void> init({
    int maxTokens = 1024,
    double temperature = 1.0,
    int randomSeed = 1,
    int topK = 1,
  });

  Future<String?> getResponse({required String prompt});

  Stream<String?> getResponseAsync({required String prompt});

  //These methods works fine with instruction tuned models only
  Future<String?> getChatResponse({required List<Message> messages, int chatContextLength = 4}) =>
      getResponse(prompt: messages.transformToChatPrompt(contextLength: chatContextLength));

  Stream<String?> getChatResponseAsync(
          {required List<Message> messages, int chatContextLength = 4}) {
    print(messages.transformToChatPrompt(contextLength: chatContextLength));
    return getResponseAsync(prompt: messages.transformToChatPrompt(contextLength: chatContextLength));
  }
}
