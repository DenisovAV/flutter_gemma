/// ONNX Runtime on-device engines for flutter_gemma: text generation
/// (`OnnxEngine`, native macOS/Linux/Windows/Android/iOS arm — web is a
/// fast-follow, see below) and embeddings (`OnnxEmbeddingBackend`,
/// productionized on native + web).
///
/// Opt-in. Add to pubspec.yaml and pass instances to
/// `FlutterGemma.initialize(...)`.
///
/// **Inference (`OnnxEngine`)** — see [OnnxEngine]'s doc comment: text-only,
/// greedy decoding, one session at a time, over ORT-GenAI via `dart:ffi`
/// (`GenAiFfiClient`, a long-lived worker isolate — no FFI handle ever
/// crosses an isolate boundary) on macOS/Linux/Windows/Android/iOS. **Web is
/// NOT yet implemented** — [OnnxEngine.canHandle] always declines there;
/// text generation on web needs Transformers.js, a different
/// model-provisioning story (an HF-repo-id model, not an ORT-GenAI
/// directory) planned as its own fast-follow PR.
///
/// **Embeddings (`OnnxEmbeddingBackend`)** — a plain ONNX Runtime forward
/// pass (no ORT GenAI) over an `.onnx`/`.ort` embedding model directory.
/// Native: `dart:ffi`, both MiniLM-family (WordPiece) and
/// EmbeddingGemma-300M-ONNX (SentencePiece) route through one factory, see
/// `OnnxEmbeddingBackend`'s doc comment. **Web**: `onnxruntime-web`
/// (WebGPU/WASM), WordPiece (MiniLM-family) only in this release —
/// SentencePiece needs a pure-Dart parser that doesn't exist yet (native's
/// `dart_sentencepiece_tokenizer` is `dart:io`/`dart:isolate`-only).
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

// `OnnxEngine`/`OnnxEmbeddingBackend` are conditionally exported so the SAME
// public API compiles on both native (dart:ffi) and web — mirrors
// `flutter_gemma_litertlm`'s barrel exactly. See `src/web/` for the web
// arms and each web file's module doc for what differs from native.
export 'src/web/onnx_engine_web.dart'
    if (dart.library.ffi) 'src/onnx_engine.dart';
export 'src/web/onnx_embedding_backend_web.dart'
    if (dart.library.ffi) 'src/embedding/onnx_embedding_backend.dart';

// Native-only advanced/test surface — direct construction of the ORT-GenAI
// FFI client, the plain-ORT embedding forward pass, or a custom `OrtClient`
// (fakes for unit tests). Exports NO symbols on web — see
// `src/native_exports_stub.dart`'s doc for why (mirrors
// `flutter_gemma_litertlm`'s `litert_bindings_stub.dart`).
export 'src/native_exports_stub.dart'
    if (dart.library.ffi) 'src/native_exports.dart';
