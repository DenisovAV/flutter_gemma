import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma/core/model.dart';

/// Base interface for all model types (inference and embedding)
abstract class BaseModel {
  /// Unique identifier for the model
  String get name;
  
  /// Display name shown in UI
  String get displayName;
  
  /// File size (e.g., "300MB", "1.2GB")
  String get size;
  
  /// Main model download URL
  String get url;
  
  /// Model filename for local storage
  String get filename;
  
  /// License/info URL (optional)
  String? get licenseUrl;
  
  /// Whether model requires HuggingFace authentication
  bool get needsAuth;
  
  /// Whether this is an embedding model (vs inference model)
  bool get isEmbeddingModel;
}

/// Interface for inference models
abstract class InferenceModelInterface extends BaseModel {
  
  /// Preferred backend (CPU/GPU)
  PreferredBackend get preferredBackend;
  
  /// Model type for MediaPipe
  ModelType get modelType;
  
  /// Whether model is stored locally (in assets)
  bool get localModel;
  
  /// Generation parameters
  double get temperature;
  int get topK;
  double get topP;
  
  /// Capabilities
  bool get supportImage;
  bool get supportsFunctionCalls;
  bool get supportsThinking;
  
  /// Token limits
  int get maxTokens;
  int? get maxNumImages;
}

/// Interface for embedding models  
abstract class EmbeddingModelInterface extends BaseModel {
  
  /// Tokenizer download URL
  String get tokenizerUrl;
  
  /// Tokenizer filename for local storage  
  String get tokenizerFilename;
  
  /// Vector dimension (e.g., 768)
  int get dimension;
}