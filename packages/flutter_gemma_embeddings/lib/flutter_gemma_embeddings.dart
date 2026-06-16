/// On-device text embeddings for flutter_gemma (LiteRT C API + .tflite).
///
/// Opt-in. Add to pubspec.yaml and pass an instance to
/// `FlutterGemma.initialize(embeddingBackends: [LiteRtEmbeddingBackend()])`.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
///
/// await FlutterGemma.initialize(
///   embeddingBackends: [LiteRtEmbeddingBackend()],
/// );
/// ```
library flutter_gemma_embeddings;

export 'src/litert_embedding_backend_stub.dart'
    if (dart.library.ffi) 'src/litert_embedding_backend.dart';
