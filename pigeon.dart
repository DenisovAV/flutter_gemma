import 'package:pigeon/pigeon.dart';
// Command to generate pigeon files:
//   dart run pigeon --input pigeon.dart && dart format lib/pigeon.g.dart
// (the trailing `dart format` is required — pigeon's output doesn't match the
//  Dart formatter, and pub.dev's static-analysis score penalizes the mismatch.)

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
  kotlinOut:
      'android/src/main/kotlin/dev/flutterberlin/flutter_gemma/PigeonInterface.g.kt',
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
    // System instruction for LiteRT-LM native support
    String? systemInstruction,
    // Enable thinking mode (Gemma 4 via extraContext)
    bool? enableThinking,
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

  // === Multi-session (MediaPipe .task path) ===
  // Session-scoped twins of the singleton methods above, keyed by an int
  // [sessionId]. The legacy methods stay the singleton path (one implicit
  // session); these address one of N concurrently-open sessions. The native
  // side holds a Map<sessionId, session>. Generation is serialized in Dart
  // (a Mutex) so only one session generates at a time — concurrent contexts,
  // serialized inference (same model as the .litertlm FFI path). Async
  // results stream over the same `flutter_gemma_stream` EventChannel with a
  // `sessionId` key added to the payload so Dart can demux.

  @async
  void createSessionForId({
    required int sessionId,
    required double temperature,
    required int randomSeed,
    required int topK,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool? enableThinking,
  });

  @async
  void closeSessionId(int sessionId);

  @async
  int sizeInTokensForSession(int sessionId, String prompt);

  @async
  void addQueryChunkToSession(int sessionId, String prompt);

  @async
  void addImageToSession(int sessionId, Uint8List imageBytes);

  @async
  void addAudioToSession(int sessionId, Uint8List audioBytes);

  @async
  String generateResponseForSession(int sessionId);

  @async
  void generateResponseAsyncForSession(int sessionId);

  @async
  void stopGenerationForSession(int sessionId);

  // 0.15.2: embedding methods removed from the pigeon contract — Android
  // and iOS now run embedding inference in Dart via LitertEmbeddingModel
  // (see lib/core/litert/litert_embedding_model.dart). No platform channel
  // hop on either OS.

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

  /// Get all documents with embeddings for HNSW index rebuild
  ///
  /// **Use case:**
  /// Called during initialize() to rebuild in-memory HNSW index
  /// from SQLite persistence layer.
  ///
  /// **Performance:**
  /// - Returns all documents in single call
  /// - Embeddings as `List<double>` (decoded from BLOB)
  ///
  /// Returns empty list if no documents stored.
  @async
  List<DocumentWithEmbedding> getAllDocumentsWithEmbeddings();

  /// Get documents by IDs with full content
  ///
  /// **Use case:**
  /// After HNSW returns candidate IDs, fetch full documents
  /// for final result construction.
  ///
  /// **Parameters:**
  /// - [ids]: List of document IDs to retrieve
  ///
  /// Returns only documents that exist (missing IDs are skipped).
  @async
  List<RetrievalResult> getDocumentsByIds(List<String> ids);
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

/// Document with embedding for HNSW rebuild
///
/// Used by [getAllDocumentsWithEmbeddings] to return documents
/// with their vectors for in-memory index reconstruction.
class DocumentWithEmbedding {
  final String id;
  final String content;
  final List<double> embedding;
  final String? metadata;

  DocumentWithEmbedding({
    required this.id,
    required this.content,
    required this.embedding,
    this.metadata,
  });
}
