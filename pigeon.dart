import 'package:pigeon/pigeon.dart';
// Command to generate pigeon files: dart run pigeon --input pigeon.dart

/// Hardware backend for model inference.
///
/// Platform support:
/// - [cpu]: All platforms
/// - [gpu]: All platforms (Metal on macOS, DirectX on Windows, Vulkan on Linux, OpenCL on Android)
/// - [npu]: Android only with LiteRT-LM (.litertlm models) - Qualcomm, MediaTek, Google Tensor
///
/// If selected backend is unavailable, engine falls back to GPU, then CPU.
enum PreferredBackend {
  cpu,
  gpu,
  npu, // Android only: Qualcomm AI Engine, MediaTek NeuroPilot, Google Tensor
}

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/pigeon.g.dart',
  kotlinOut: 'android/src/main/kotlin/dev/flutterberlin/flutter_gemma/PigeonInterface.g.kt',
  kotlinOptions: KotlinOptions(package: 'dev.flutterberlin.flutter_gemma'),
  swiftOut: 'ios/Classes/PigeonInterface.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'flutter_gemma',
))
@HostApi()
abstract class PlatformService {
  @async
  void createModel({
    required int maxTokens,
    required String modelPath,
    required List<int>? loraRanks,
    PreferredBackend? preferredBackend,
    // Add image support
    int? maxNumImages,
    // Add audio support (Gemma 3n E4B)
    bool? supportAudio,
  });

  @async
  void closeModel();

  @async
  void createSession({
    required double temperature,
    required int randomSeed,
    required int topK,
    double? topP,
    String? loraPath,
    // Add option to enable vision modality
    bool? enableVisionModality,
    // Add option to enable audio modality (Gemma 3n E4B)
    bool? enableAudioModality,
  });

  @async
  void closeSession();

  @async
  int sizeInTokens(String prompt);

  @async
  void addQueryChunk(String prompt);

  // Add method for adding image
  @async
  void addImage(Uint8List imageBytes);

  // Add method for adding audio (Gemma 3n E4B)
  @async
  void addAudio(Uint8List audioBytes);

  @async
  String generateResponse();

  @async
  void generateResponseAsync();

  @async
  void stopGeneration();

  // === RAG Methods ===

  // RAG Embedding Methods
  @async
  void createEmbeddingModel({
    required String modelPath,
    required String tokenizerPath,
    PreferredBackend? preferredBackend,
  });

  @async
  void closeEmbeddingModel();

  @async
  List<double> generateEmbeddingFromModel(String text);

  @async
  List<Object?> generateEmbeddingsFromModel(List<String> texts);

  @async
  int getEmbeddingDimension();

  // RAG Vector Store Methods
  @async
  void initializeVectorStore(String databasePath);

  @async
  void addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  });

  @async
  List<RetrievalResult> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  });

  @async
  VectorStoreStats getVectorStoreStats();

  @async
  void clearVectorStore();

  @async
  void closeVectorStore();
}

// === RAG Data Classes ===

class RetrievalResult {
  final String id;
  final String content;
  final double similarity;
  final String? metadata;

  RetrievalResult({
    required this.id,
    required this.content,
    required this.similarity,
    this.metadata,
  });
}

class VectorStoreStats {
  final int documentCount;
  final int vectorDimension;

  VectorStoreStats({
    required this.documentCount,
    required this.vectorDimension,
  });
}
