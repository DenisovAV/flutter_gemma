import 'dart:async';

import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/model_file_manager_interface.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mobile/flutter_gemma_mobile.dart';

const supportedLoraRanks = [4, 8, 16];

/// Interface for the FlutterGemma plugin.
abstract class FlutterGemmaPlugin extends PlatformInterface {
  FlutterGemmaPlugin() : super(token: _token);

  static final Object _token = Object();
  static FlutterGemmaPlugin _instance = FlutterGemma();

  static FlutterGemmaPlugin get instance => _instance;

  static set instance(FlutterGemmaPlugin instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  ModelFileManager get modelManager;

  InferenceModel? get initializedModel;

  /// Creates and returns a new [InferenceModel] instance.
  ///
  /// [modelType] — model type to create.
  /// [maxTokens] — maximum context length for the model.
  /// [preferredBackend] — backend preference (e.g., CPU, GPU).
  /// [loraRanks] — optional supported LoRA ranks.
  /// [maxNumImages] — maximum number of images (for multimodal models).
  /// [supportImage] — whether the model supports images.
  Future<InferenceModel> createModel({
    required ModelType modelType,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages, // Добавляем поддержку изображений
    bool supportImage = false, // Добавляем флаг поддержки изображений
  });
}

/// Represents an LLM model instance.
abstract class InferenceModel {
  InferenceModelSession? get session;

  InferenceChat? chat;

  int get maxTokens;

  /// Creates a new [InferenceModelSession] for generation.
  ///
  /// [temperature], [randomSeed], [topK], [topP] — parameters for sampling.
  /// [loraPath] — optional path to LoRA model.
  /// [enableVisionModality] — enable vision modality for multimodal models.
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Добавляем поддержку vision модальности
  });

  /// Creates a chat interface wrapping [InferenceChat].
  ///
  /// [temperature], [randomSeed], [topK], [topP] — parameters for sampling.
  /// [loraPath] — optional path to LoRA model.
  /// [tokenBuffer] — token buffer size for chat for not to exceed max tokens.
  /// [enableVisionModality] — enable vision modality for multimodal models.
  /// [supportImage] — whether the chat should support images.
  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP, // Optional topP for chat too
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage, // Добавляем поддержку изображений в чате
  }) async {
    chat = InferenceChat(
      sessionCreator: () => createSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? false,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? false, // Передаем поддержку изображений
    );
    await chat!.initSession();
    return chat!;
  }

  Future<void> close();
}

/// Session managing response generation from the model.
abstract class InferenceModelSession {
  Future<String> getResponse();

  Stream<String> getResponseAsync();

  Future<int> sizeInTokens(String text);

  Future<void> addQueryChunk(Message message);

  Future<void> close();
}