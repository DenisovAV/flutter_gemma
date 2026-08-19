/// Runtime-agnostic on-device text embedding pipeline for flutter_gemma.
///
/// This package no longer ships a concrete embedding backend — it owns
/// tokenization, task-type prefixing, the background-isolate worker, and
/// pooling/normalization, over the [EmbeddingForwardPass] seam that engine
/// packages implement.
///
/// To actually run embeddings, add an engine package that provides an
/// `EmbeddingBackendProvider` — e.g. `flutter_gemma_litertlm`'s
/// `LiteRtEmbeddingBackend` — and register it:
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
///
/// await FlutterGemma.initialize(
///   embeddingBackends: [LiteRtEmbeddingBackend()],
/// );
/// ```
///
/// See the embedder decoupling design (docs/superpowers/specs/
/// 2026-08-17-flutter-gemma-onnx-engine-design.md §2, §11 D3/D4) for why the
/// seam exists: it lets `flutter_gemma_litertlm` and (later)
/// `flutter_gemma_onnx` share one tokenizer/worker/pooling implementation
/// instead of each reimplementing the isolate facade.
library;

// The runtime-agnostic `ForwardPass` seam (design doc §2, §11 D3/D4): pure
// Dart, no engine dependency. Engine packages (flutter_gemma_litertlm,
// flutter_gemma_onnx) implement `EmbeddingForwardPass` and build a
// `ForwardPassDescriptor` from a top-level factory tear-off to plug into the
// common embedder below.
export 'src/forward_pass.dart';
export 'src/pooling.dart';
// The tokenizer seam (design D-T1): pure Dart, no engine dependency, no
// native library at all — engine packages implement `EmbeddingTokenizer` and
// build a `ForwardPassDescriptor.tokenizerFactory` from a top-level factory
// tear-off, same shape as `EmbeddingForwardPassFactory` above.
export 'src/tokenizer_adapter.dart';

// NOTE: `src/embedding_tokenizer.dart` and `src/wordpiece_embedding_tokenizer.dart`
// are native-only leaves (`dart:io`, and for the former
// `dart_sentencepiece_tokenizer`, which imports `dart:io`/`dart:isolate`
// unconditionally) — deliberately NOT exported from this barrel so importing
// this package can never break a web build. They're used internally by
// engine backends (reached only via the native-only
// `common_embedding_model.dart` arm below); native-only engine/test code
// that needs them directly imports
// `package:flutter_gemma_embeddings/src/embedding_tokenizer.dart` /
// `package:flutter_gemma_embeddings/src/wordpiece_embedding_tokenizer.dart`.

// The common embedder: background-isolate worker + `EmbeddingModel` facade
// over any `ForwardPassDescriptor`. Conditional export — the real worker
// needs `dart:isolate` semantics that only make sense on native platforms;
// web engine packages build their own `EmbeddingModel` directly (see
// `flutter_gemma_litertlm`'s web arm) and never reach this file.
export 'src/common_embedding_model_stub.dart'
    if (dart.library.ffi) 'src/common_embedding_model.dart';
