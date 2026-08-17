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
library;

export 'src/litert_embedding_backend_stub.dart'
    if (dart.library.ffi) 'src/litert_embedding_backend.dart';

// The runtime-agnostic `ForwardPass` seam (design doc §2, §11 D3/D4): pure
// Dart, no engine dependency. Engine packages (flutter_gemma_litertlm,
// flutter_gemma_onnx) implement `EmbeddingForwardPass` and build a
// `ForwardPassDescriptor` from a top-level factory tear-off to plug into the
// common embedder. Unconditional export — these files have no dart:io/web
// split, unlike the backend above.
export 'src/forward_pass.dart';
export 'src/pooling.dart';
