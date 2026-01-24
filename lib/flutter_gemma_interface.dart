import 'dart:async';

import 'package:flutter_gemma/core/tool.dart';
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
  static FlutterGemmaPlugin _instance = FlutterGemmaMobile();

  static FlutterGemmaPlugin get instance => _instance;

  static set instance(FlutterGemmaPlugin instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  ModelFileManager get modelManager;

  InferenceModel? get initializedModel;

  EmbeddingModel? get initializedEmbeddingModel;

  /// Creates and returns a new [InferenceModel] instance.
  ///
  /// [modelType] — model type to create.
  /// [maxTokens] — maximum context length for the model.
  /// [preferredBackend] — backend preference (e.g., CPU, GPU).
  /// [loraRanks] — optional supported LoRA ranks.
  /// [maxNumImages] — maximum number of images (for multimodal models).
  /// [supportImage] — whether the model supports images.
  /// [supportAudio] — whether the model supports audio (Gemma 3n E4B only).
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages, // Add image support
    bool supportImage = false, // Add image support flag
    bool supportAudio = false, // Add audio support flag (Gemma 3n E4B)
  });

  /// Creates and returns a new [EmbeddingModel] instance.
  ///
  /// Modern API: If paths are not provided, uses the active embedding model set via
  /// `FlutterGemma.installEmbedder()` or `modelManager.setActiveModel()`.
  ///
  /// Legacy API: Provide explicit paths for backward compatibility.
  ///
  /// [modelPath] — path to the embedding model file (optional if active model set).
  /// [tokenizerPath] — path to the tokenizer file (optional if active model set).
  /// [preferredBackend] — backend preference (e.g., CPU, GPU).
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  });

  /// === RAG functionality ===

  /// Initialize vector store database.
  Future<void> initializeVectorStore(String databasePath);

  /// Add document to vector store with pre-computed embedding.
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  });

  /// Add document to vector store (will compute embedding automatically).
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  });

  /// Search for similar documents.
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
  });

  /// Get vector store statistics.
  Future<VectorStoreStats> getVectorStoreStats();

  /// Clear all documents from vector store.
  Future<void> clearVectorStore();
}

/// Represents an LLM model instance.
abstract class InferenceModel {
  InferenceModelSession? get session;

  InferenceChat? chat;

  int get maxTokens;

  ModelFileType get fileType;

  /// Creates a new [InferenceModelSession] for generation.
  ///
  /// [temperature], [randomSeed], [topK], [topP] — parameters for sampling.
  /// [loraPath] — optional path to LoRA model.
  /// [enableVisionModality] — enable vision modality for multimodal models.
  /// [enableAudioModality] — enable audio modality for Gemma 3n E4B models.
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Add vision modality support
    bool? enableAudioModality, // Add audio modality support (Gemma 3n E4B)
  });

  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false, // Add isThinking parameter
    ModelType? modelType, // Add modelType parameter
  }) async {
    chat = InferenceChat(
      sessionCreator: () => createSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? false,
        enableAudioModality: supportAudio ?? false,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? false,
      supportAudio: supportAudio ?? false,
      supportsFunctionCalls: supportsFunctionCalls ?? false,
      tools: tools,
      isThinking: isThinking, // Pass isThinking parameter
      modelType: modelType ?? ModelType.gemmaIt, // Use provided modelType or default
      fileType: fileType, // Pass fileType from model
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

  Future<void> stopGeneration();

  Future<void> close();
}

/// Represents an embedding model instance.
abstract class EmbeddingModel {
  /// Generate embedding vector for given text.
  Future<List<double>> generateEmbedding(String text);

  /// Generate embedding vectors for multiple texts.
  Future<List<List<double>>> generateEmbeddings(List<String> texts);

  /// Get the dimension of embedding vectors generated by this model.
  Future<int> getDimension();

  /// Close the embedding model and release resources.
  Future<void> close();
}
