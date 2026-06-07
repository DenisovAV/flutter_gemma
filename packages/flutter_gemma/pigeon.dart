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
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/pigeon.g.dart',
  kotlinOut:
      'android/src/main/kotlin/dev/flutterberlin/flutter_gemma/PigeonInterface.g.kt',
  kotlinOptions: KotlinOptions(package: 'dev.flutterberlin.flutter_gemma'),
  swiftOut: 'ios/flutter_gemma/Sources/flutter_gemma/PigeonInterface.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'flutter_gemma',
))
enum PreferredBackend {
  cpu,
  gpu,
  npu, // Android only: Qualcomm AI Engine, MediaTek NeuroPilot, Google Tensor
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
