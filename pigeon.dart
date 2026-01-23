import 'package:pigeon/pigeon.dart';
// Command to generate pigeon files: dart run pigeon --input pigeon.dart

enum PreferredBackend {
  cpu,
  gpu,
  npu, // Supported by LiteRT-LM only (Google Tensor, Qualcomm NPU)
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
