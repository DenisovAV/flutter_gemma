import 'dart:async';

import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
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

  /// Returns [InferenceModel] instance created by [init] method.
  InferenceModel? get initializedModel;

  /// Initialize loaded model and return [InferenceModel] instance.
  ///
  /// [InferenceModel] should be used to get responses from the model.
  /// It can be obtained from the [initializedModel] getter after initialization.
  ///
  /// Only one model can be initialized at a time.
  /// To initialize a new model, call [InferenceModel.close] first.
  Future<InferenceModel> init({
    int maxTokens,
    double temperature,
    int randomSeed,
    int topK,
  });
}

abstract class ModelFileManager {
  Future<bool> get isModelLoaded;

  Future<bool> get isLoraLoaded;

  /// Sets the path to the model and lora weights files.
  /// Use this method to manage the files manually.
  ///
  /// {@macro gemma.load_model}
  Future<void> setModelPath(String path, {String? loraPath});

  /// Sets the path to the lora weights file.
  /// Use this method to manage the lora weights file manually.
  ///
  /// {@macro gemma.load_weights}
  Future<void> setLoraWeightsPath(String path);

  /// Loads the model and lora weights from the network.
  ///
  /// {@template gemma.load_model}
  /// Model should be loaded before initialization.
  ///
  /// This method can be safely called multiple times. Model and lora weights will be loaded only if they doesn't exist.
  ///
  /// To reload the model, call [deleteModel] first. To reload the lora weights, call [deleteLoraWeights] first.
  /// {@endtemplate}
  Future<void> loadModelFromNetwork(String url, {String? loraUrl});

  /// Loads the model and lora weights from the network with progress.
  ///
  /// {@macro gemma.load_model}
  Stream<int> loadModelFromNetworkWithProgress(String url, {String? loraUrl});

  /// Loads the lora weights from the network.
  ///
  /// {@template gemma.load_weights}
  /// This method can be safely called multiple times. Lora weights will be loaded only if they doesn't exist.
  ///
  /// To reload the lora weights, call [deleteLoraWeights] first.
  /// {@endtemplate}
  Future<void> loadLoraWeightsFromNetwork(String loraUrl);

  /// Loads the model and lora weights from the asset.
  ///
  /// {@macro gemma.load_model}
  ///
  /// {@template gemma.asset_model}
  /// This method should be used only for development purpose.
  /// Never embed neither model nor lora weights in the production app.
  /// {@endtemplate}
  Future<void> loadModelFromAsset(String path, {String? loraPath});

  /// Loads the lora weights from the asset.
  ///
  /// {@macro gemma.load_weights}
  ///
  /// {@macro gemma.asset_model}
  Future<void> loadLoraWeightsFromAsset(String path);

  /// Loads the model and lora weights from the asset with progress.
  ///
  /// {@macro gemma.load_model}
  ///
  /// {@macro gemma.asset_model}
  Stream<int> loadModelFromAssetWithProgress(String path, {String? loraPath});

  /// Deletes the loaded model. Nothing happens if the model is not loaded.
  ///
  /// Also, closes the inference if it is initialized.
  Future<void> deleteModel();

  /// Deletes the loaded lora weights. Nothing happens if the lora weights are not loaded.
  ///
  /// Also, closes the inference if it is initialized.
  Future<void> deleteLoraWeights();
}

/// Inference model for generating responses from the LLM.
abstract class InferenceModel {
  /// Generates a response for the given prompt.
  ///
  /// {@template gemma.response}
  /// Only one response can be generated at a time.
  /// But it is safe to call this method multiple times. It will wait for the previous response to be generated.
  /// {@endtemplate}
  Future<String> getResponse({required String prompt, bool isChat});

  /// Generates a response for the given prompt. Returns a stream of tokens as they are generated.
  ///
  /// Stream will be closed when the response is generated.
  ///
  /// {@macro gemma.response}
  Stream<String> getResponseAsync({required String prompt, bool isChat});

  /// Closes and cleans up the llm inference.
  ///
  /// Call this method when the inference is no longer needed or to stop the response generation.
  ///
  /// [FlutterGemmaPlugin.init] should be called again to use a new [InferenceModel].
  Future<void> close();
}
