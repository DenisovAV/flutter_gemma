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

export 'src/qdrant_vector_store_stub.dart'
    if (dart.library.ffi) 'src/qdrant_vector_store.dart';
