/// qdrant-edge on-device RAG vector store for flutter_gemma (native FFI).
///
/// Opt-in package, native platforms only. Add it to pubspec.yaml and pass an
/// instance to `FlutterGemma.initialize(vectorStore: ...)`:
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
///
/// await FlutterGemma.initialize(vectorStore: QdrantVectorStore());
/// ```
library flutter_gemma_rag_qdrant;

// The QdrantVectorStore export is added in Task 5 (after the impl moves).
