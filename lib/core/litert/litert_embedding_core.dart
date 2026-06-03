// Synchronous, isolate-agnostic native core for LiteRT text embeddings.
//
// Owns the LiteRT C API handles (environment, model, options, compiled model)
// and the SentencePiece tokenizer. `embed()` runs the blocking forward pass
// synchronously on the calling thread — it is meant to be driven from a
// background isolate (see `litert_embedding_worker.dart`) so the UI isolate
// stays free (issue #299).
//
// This is the native code that used to live inline in `LitertEmbeddingModel`;
// it was extracted unchanged (same pipeline, same special tokens, same
// alignment) so embedding vectors are byte-identical before/after the #299
// refactor.
//
// Pipeline:
//   text → prefix + text
//        → tokenize (dart_sentencepiece_tokenizer)
//        → [BOS=2, ...ids, EOS=1]                    (Gemma convention)
//        → right-pad with 0s to seqLength
//        → Int32 LiteRtTensorBuffer (64-byte aligned host memory)
//        → LiteRtRunCompiledModel signature 0
//        → Float32 LiteRtTensorBuffer of shape [1, dim]
//        → List<double>

import 'dart:ffi';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'litert_bindings.dart';
import 'litert_embedding_worker.dart' show EmbeddingBackend;

/// Gemma special-token IDs. `dart_sentencepiece_tokenizer` defaults to the
/// swapped pair (bosId=1, eosId=2), so we add them manually.
const int _bosId = 2;
const int _eosId = 1;

int _acceleratorFor(EmbeddingBackend backend) {
  switch (backend) {
    case EmbeddingBackend.gpu:
      return kLiteRtHwAcceleratorGpu;
    case EmbeddingBackend.npu:
      return kLiteRtHwAcceleratorNpu;
    case EmbeddingBackend.cpu:
      return kLiteRtHwAcceleratorCpu;
  }
}

/// Synchronous native embedding core. NOT safe to share across isolates — the
/// FFI handles it holds are owned by the isolate that called [load].
class EmbeddingCore {
  EmbeddingCore._({
    required LiteRtBindings bindings,
    required LiteRtEnvironment environment,
    required LiteRtModel model,
    required LiteRtOptions options,
    required LiteRtCompiledModel compiledModel,
    required this.tokenizer,
    required this.inputSequenceLength,
    required this.outputDimension,
  })  : _bindings = bindings,
        _environment = environment,
        _model = model,
        _options = options,
        _compiledModel = compiledModel;

  final LiteRtBindings _bindings;
  final LiteRtEnvironment _environment;
  final LiteRtModel _model;
  final LiteRtOptions _options;
  final LiteRtCompiledModel _compiledModel;

  final SentencePieceTokenizer tokenizer;
  final int inputSequenceLength;
  final int outputDimension;

  bool _disposed = false;

  /// Load a `.tflite` embedding model and compile it for [backend]. Heavy
  /// (compile is ~570-780ms) — call once, from a background isolate.
  static Future<EmbeddingCore> load({
    required String modelPath,
    required String tokenizerPath,
    EmbeddingBackend backend = EmbeddingBackend.cpu,
    int? inputSequenceLength,
    int? outputDimension,
  }) async {
    final bindings = LiteRtBindings.open();

    // Load tokenizer first (file IO; native side hasn't started yet).
    final SentencePieceTokenizer tokenizer;
    if (tokenizerPath.endsWith('.json')) {
      tokenizer = await TokenizerJsonLoader.fromJsonFile(
        tokenizerPath,
        config: const SentencePieceConfig(),
      );
    } else {
      tokenizer = await SentencePieceTokenizer.fromModelFile(
        tokenizerPath,
        config: const SentencePieceConfig(),
      );
    }

    // Track native handles as they are created so a failure partway through
    // (e.g. a bad accelerator, or a non-embedding model with the wrong tensor
    // rank) frees everything already allocated instead of leaking it — the
    // LiteRT native heap is process-global and is NOT reclaimed by the
    // isolate dying.
    LiteRtEnvironment? environment;
    LiteRtModel? model;
    LiteRtOptions? options;
    LiteRtCompiledModel? compiled;
    try {
      final envPtr = calloc<LiteRtEnvironment>();
      bindings
          .createEnvironment(0, nullptr, envPtr)
          .check('LiteRtCreateEnvironment');
      environment = envPtr.value;
      calloc.free(envPtr);

      // Model from .tflite file.
      final pathC = modelPath.toNativeUtf8();
      final modelPtr = calloc<LiteRtModel>();
      try {
        bindings
            .createModelFromFile(pathC, modelPtr)
            .check('LiteRtCreateModelFromFile($modelPath)');
      } finally {
        calloc.free(pathC);
      }
      model = modelPtr.value;
      calloc.free(modelPtr);

      // Compilation options.
      final optsPtr = calloc<LiteRtOptions>();
      bindings.createOptions(optsPtr).check('LiteRtCreateOptions');
      options = optsPtr.value;
      calloc.free(optsPtr);
      bindings
          .setOptionsHardwareAccelerators(options, _acceleratorFor(backend))
          .check('LiteRtSetOptionsHardwareAccelerators');

      // Compile.
      final compiledPtr = calloc<LiteRtCompiledModel>();
      bindings
          .createCompiledModel(environment, model, options, compiledPtr)
          .check('LiteRtCreateCompiledModel');
      compiled = compiledPtr.value;
      calloc.free(compiledPtr);

      // Auto-detect seqLen + dim from compiled tensor layouts unless pinned.
      int seqLen, dim;
      if (inputSequenceLength == null) {
        final inLayout = LiteRtLayoutView.calloc();
        try {
          bindings
              .getInputTensorLayout(compiled, 0, 0, inLayout.pointer)
              .check('LiteRtGetCompiledModelInputTensorLayout');
          if (inLayout.rank < 2) {
            throw StateError(
                'Embedding model input has rank=${inLayout.rank}, expected >=2');
          }
          seqLen = inLayout.dimension(1);
        } finally {
          inLayout.free();
        }
      } else {
        seqLen = inputSequenceLength;
      }

      if (outputDimension == null) {
        final outLayouts = LiteRtLayoutView.calloc();
        try {
          bindings
              .getOutputTensorLayouts(compiled, 0, 1, outLayouts.pointer, false)
              .check('LiteRtGetCompiledModelOutputTensorLayouts');
          if (outLayouts.rank < 2) {
            throw StateError(
                'Embedding model output has rank=${outLayouts.rank}, expected >=2');
          }
          dim = outLayouts.dimension(1);
        } finally {
          outLayouts.free();
        }
      } else {
        dim = outputDimension;
      }

      debugPrint(
          '[EmbeddingCore] loaded: seqLen=$seqLen, dim=$dim, backend=$backend');

      return EmbeddingCore._(
        bindings: bindings,
        environment: environment,
        model: model,
        options: options,
        compiledModel: compiled,
        tokenizer: tokenizer,
        inputSequenceLength: seqLen,
        outputDimension: dim,
      );
    } catch (_) {
      // Free whatever was created, in reverse order, before rethrowing.
      if (compiled != null) bindings.destroyCompiledModel(compiled);
      if (options != null) bindings.destroyOptions(options);
      if (model != null) bindings.destroyModel(model);
      if (environment != null) bindings.destroyEnvironment(environment);
      rethrow;
    }
  }

  /// Tokenize ([prefix] + [text]) with Gemma BOS/EOS and run one forward pass.
  /// Synchronous and blocking — runs on the calling thread.
  List<double> embed(String text, {required String prefix}) {
    if (_disposed) {
      throw StateError('EmbeddingCore is disposed');
    }
    final encoded = tokenizer.encode(prefix + text);
    final tokens = <int>[_bosId, ...encoded.ids, _eosId];
    return _runForward(tokens);
  }

  List<double> _runForward(List<int> tokens) {
    final seq = inputSequenceLength;
    final dim = outputDimension;

    // All allocations live inside the try so a failure in either
    // createTensorBufferFromHostMemory (or runCompiledModel) frees everything
    // that was created instead of leaking it. Buffers are destroyed only if
    // they were actually created (the `*Created` flags).
    final inType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeInt32
      ..rank = 2
      ..setDimension(0, 1)
      ..setDimension(1, seq);
    final inAlloc = allocAligned(seq * 4);
    final inBufPtr = calloc<LiteRtTensorBuffer>();
    final outType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeFloat32
      ..rank = 2
      ..setDimension(0, 1)
      ..setDimension(1, dim);
    final outAlloc = allocAligned(dim * 4);
    final outBufPtr = calloc<LiteRtTensorBuffer>();
    var inBufCreated = false;
    var outBufCreated = false;

    try {
      final inHost = inAlloc.aligned.cast<Int32>();
      for (var i = 0; i < seq; i++) {
        inHost[i] = i < tokens.length ? tokens[i] : 0;
      }

      _bindings
          .createTensorBufferFromHostMemory(inType.pointer,
              inAlloc.aligned.cast(), seq * 4, nullptr, inBufPtr)
          .check('CreateTensorBufferFromHostMemory(input)');
      inBufCreated = true;

      _bindings
          .createTensorBufferFromHostMemory(outType.pointer,
              outAlloc.aligned.cast(), dim * 4, nullptr, outBufPtr)
          .check('CreateTensorBufferFromHostMemory(output)');
      outBufCreated = true;

      _bindings
          .runCompiledModel(_compiledModel, 0, 1, inBufPtr, 1, outBufPtr)
          .check('LiteRtRunCompiledModel');

      final outFloat = outAlloc.aligned.cast<Float>();
      return List<double>.generate(dim, (i) => outFloat[i]);
    } finally {
      if (inBufCreated) _bindings.destroyTensorBuffer(inBufPtr.value);
      if (outBufCreated) _bindings.destroyTensorBuffer(outBufPtr.value);
      calloc.free(inBufPtr);
      calloc.free(outBufPtr);
      calloc.free(inAlloc.raw);
      calloc.free(outAlloc.raw);
      inType.free();
      outType.free();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.destroyCompiledModel(_compiledModel);
    _bindings.destroyOptions(_options);
    _bindings.destroyModel(_model);
    _bindings.destroyEnvironment(_environment);
  }
}
