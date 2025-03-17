import 'dart:async';

import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/model_file_manager_interface.dart';
import 'package:flutter_gemma/preferred_backend.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mobile/flutter_gemma_mobile.dart';

const supportedLoraRanks = [4, 8, 16];

abstract class FlutterGemmaPlugin extends PlatformInterface {
  /// Constructs a FlutterGemmaPlatform.
  FlutterGemmaPlugin() : super(token: _token);

  static final Object _token = Object();

  static FlutterGemmaPlugin _instance = FlutterGemma();

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

  ModelFileManager get modelManager;

  /// Returns [InferenceModel] instance created by [createModel] method.
  InferenceModel? get initializedModel;

  /// Creates installed model and return [InferenceModel] instance.
  ///
  /// [InferenceModel] should be used to get responses from the model.
  /// It can be obtained from the [initializedModel] getter after initialization.
  ///
  /// Only one model can be created at a time.
  /// To create a new model, call [InferenceModel.close] first.
  ///
  /// [isInstructionTuned] should be set to `true` when you use a gemma model specially tuned for instructions.
  /// These models has `it` in their names. For example gemma-2b-**it**-gpu-int8 is an instruction tuned model.
  Future<InferenceModel> createModel({
    required bool isInstructionTuned,
    int maxTokens,
    PreferredBackend preferredBackend = PreferredBackend.defaultBackend,
  });
}

abstract class InferenceModel {
  InferenceModelSession? get session;

  InferenceChat? chat;

  int get maxTokens;

  /// Creates a session for generating responses from the LLM.
  ///
  /// Only one session can be created at a time.
  ///
  /// {@macro gemma.session}
  Future<InferenceModelSession> createSession({
    double temperature,
    int randomSeed,
    int topK,
  });

  /// Creates a chat for generating chat responses from the LLM.
  ///
  /// Only one chat can be created at a time.
  ///
  /// {@macro gemma.chat}
  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    int tokenBuffer = 256,
  }) async {
    chat = InferenceChat(
      sessionCreator: (() => createSession(
            temperature: temperature,
            randomSeed: randomSeed,
            topK: topK,
          )),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
    );
    await chat!.initSession();
    return chat!;
  }

  /// Closes and cleans up the llm inference.
  ///
  /// Call this method when the inference is no longer needed.
  /// To stop the response generation, call [InferenceModelSession.close].
  ///
  /// [FlutterGemmaPlugin.createModel] should be called again to use a new [InferenceModel].
  Future<void> close();
}

/// Session is responsible for generating responses from the installed LLM.
///
/// {@template gemma.session}
/// Session remembers context from previous calls.
/// To clean the context, [close] current session and create a new one.
/// {@endtemplate}
abstract class InferenceModelSession {
  /// Generates a response for the given prompt.
  ///
  /// {@template gemma.response}
  /// Only one response can be generated at a time.
  /// But it is safe to call this method multiple times. It will wait for the previous response to be generated.
  /// {@endtemplate}
  Future<String> getResponse();

  /// Generates a response for the given prompt. Returns a stream of tokens as they are generated.
  ///
  /// Stream will be closed when the response is generated.
  ///
  /// {@macro gemma.response}
  Stream<String> getResponseAsync();

  Future<int> sizeInTokens(String text);

  Future<void> addQueryChunk(Message message);

  /// Closes and cleans up the model session.
  ///
  /// Call this method when the session is no longer needed or to stop the response generation.
  ///
  /// [InferenceModel.createSession] should be called again to use a new [InferenceModelSession].
  Future<void> close();
}
