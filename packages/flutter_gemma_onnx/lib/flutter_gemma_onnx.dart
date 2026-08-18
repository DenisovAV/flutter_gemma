/// ONNX Runtime on-device engines for flutter_gemma: text generation
/// (`OnnxEngine`, macOS-first host arm — Phase 3) and embeddings
/// (`OnnxEmbeddingBackend`, productionized — Phase 2).
///
/// Opt-in. Add to pubspec.yaml and pass instances to
/// `FlutterGemma.initialize(...)`.
///
/// **Inference (`OnnxEngine`) — macOS-first host arm (v1 slice)** — see
/// [OnnxEngine]'s doc comment: text-only, greedy decoding, one session at a
/// time, over ORT-GenAI via `dart:ffi` (`GenAiFfiClient`, a long-lived
/// worker isolate — no FFI handle ever crosses an isolate boundary).
/// Android/iOS device work stays behind the D2 throughput/RAM go/no-go gate.
///
/// **Embeddings (`OnnxEmbeddingBackend`) — productionized (Phase 2)**: a
/// plain ONNX Runtime forward pass (`dart:ffi`, no ORT GenAI) over an
/// `.onnx`/`.ort` embedding model directory — MiniLM-family (WordPiece) and
/// EmbeddingGemma-300M-ONNX (SentencePiece) both route through one factory,
/// see `OnnxEmbeddingBackend`'s doc comment.
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';
///
/// await FlutterGemma.initialize(
///   inferenceEngines: [OnnxEngine()],
///   embeddingBackends: [OnnxEmbeddingBackend()],
/// );
///
/// await FlutterGemma.installEmbedder()
///     .modelFromAsset('assets/models/all-MiniLM-L6-v2.onnx')
///     .tokenizerFromAsset('assets/models/tokenizer.json')
///     .install();
/// ```
library;

export 'src/onnx_engine.dart';
export 'src/onnx_inference_model.dart';
export 'src/onnx_session.dart';
export 'src/ffi/gen_ai_client.dart'
    show GenAiClient, GenAiFfiClient, GenAiTurn, GenAiGenerationStats;
export 'src/embedding/onnx_embedding_backend.dart';

// Exposed for advanced/test use — direct construction of the pass or a
// custom `OrtClient` (fakes for unit tests, or a non-default client).
export 'src/embedding/onnx_embedding_forward_pass.dart';
export 'src/embedding/onnx_tokenizer_loader.dart';
export 'src/embedding/ort_client.dart';
