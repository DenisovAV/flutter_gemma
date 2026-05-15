// Shared `EmbeddingModel` implementation backed by the LiteRT C API via
// dart:ffi. Runs on Android, iOS, macOS, Linux, and Windows.
//
// Replaces the per-platform implementations that 0.15.1 shipped:
//   - Android `EmbeddingModel.kt` (localagents-rag JVM lib)
//   - iOS `EmbeddingModel.swift` (TensorFlowLiteC.framework)
//   - Desktop `DesktopEmbeddingModel` (libtensorflowlite_c.{dylib,so,dll})
// All three are deleted in 0.15.2. Web is unchanged (LiteRT.js).
//
// Pipeline (same as the platforms it replaces):
//   text → TaskType.prefix + text
//        → tokenize (dart_sentencepiece_tokenizer)
//        → [BOS=2, ...ids, EOS=1]                    (Gemma convention)
//        → right-pad with 0s to seqLength
//        → Int32 LiteRtTensorBuffer (host memory, 64-byte aligned)
//        → LiteRtRunCompiledModel signature 0
//        → Float32 LiteRtTensorBuffer of shape [1, dim]
//        → List<double>

import 'dart:ffi';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../flutter_gemma_interface.dart' show EmbeddingModel, TaskType;
import 'litert_bindings.dart';

/// Gemma special-token IDs. `dart_sentencepiece_tokenizer` defaults to the
/// swapped pair (bosId=1, eosId=2), so we add them manually.
const int _bosId = 2;
const int _eosId = 1;

class LitertEmbeddingModel extends EmbeddingModel {
  LitertEmbeddingModel._({
    required LiteRtBindings bindings,
    required LiteRtEnvironment environment,
    required LiteRtModel model,
    required LiteRtOptions options,
    required LiteRtCompiledModel compiledModel,
    required this.tokenizer,
    required this.inputSequenceLength,
    required this.outputDimension,
    required this.onClose,
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

  /// Sequence length the model was compiled for (input tensor dim[1]).
  final int inputSequenceLength;

  /// Output embedding dimension (output tensor dim[1] — 768 for Gecko /
  /// EmbeddingGemma).
  final int outputDimension;

  final VoidCallback onClose;
  bool _isClosed = false;

  /// Load a `.tflite` embedding model from disk and prepare it for
  /// inference on CPU.
  ///
  /// [modelPath] points at a `.tflite` file (Gecko 64, EmbeddingGemma 256,
  /// etc.). [tokenizerPath] is the matching SentencePiece `.model` or
  /// exported `.json`. Input sequence length and output dimension are
  /// auto-detected from the compiled model's tensor layouts; pass them
  /// to override (rare).
  ///
  /// Caller owns the returned instance and must call [close] when done.
  static Future<LitertEmbeddingModel> create({
    required String modelPath,
    required String tokenizerPath,
    int? inputSequenceLength,
    int? outputDimension,
    VoidCallback? onClose,
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

    // Environment (CPU; can be extended later for GPU acceleration).
    final envPtr = calloc<LiteRtEnvironment>();
    bindings
        .createEnvironment(0, nullptr, envPtr)
        .check('LiteRtCreateEnvironment');
    final environment = envPtr.value;
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
    final model = modelPtr.value;
    calloc.free(modelPtr);

    // Compilation options: CPU only.
    final optsPtr = calloc<LiteRtOptions>();
    bindings.createOptions(optsPtr).check('LiteRtCreateOptions');
    final options = optsPtr.value;
    calloc.free(optsPtr);
    bindings
        .setOptionsHardwareAccelerators(options, kLiteRtHwAcceleratorCpu)
        .check('LiteRtSetOptionsHardwareAccelerators');

    // Compile.
    final compiledPtr = calloc<LiteRtCompiledModel>();
    bindings
        .createCompiledModel(environment, model, options, compiledPtr)
        .check('LiteRtCreateCompiledModel');
    final compiled = compiledPtr.value;
    calloc.free(compiledPtr);

    // Auto-detect seqLen + dim from compiled tensor layouts unless the
    // caller pinned them. Embedding models we care about all have:
    //   input  shape [1, seqLen]   element_type=int32
    //   output shape [1, dim]      element_type=float32
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

    debugPrint('[LitertEmbeddingModel] loaded: seqLen=$seqLen, dim=$dim');

    return LitertEmbeddingModel._(
      bindings: bindings,
      environment: environment,
      model: model,
      options: options,
      compiledModel: compiled,
      tokenizer: tokenizer,
      inputSequenceLength: seqLen,
      outputDimension: dim,
      onClose: onClose ?? () {},
    );
  }

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
          'LitertEmbeddingModel is closed; create a new instance to use it');
    }
  }

  /// Tokenize with prefix and add Gemma BOS/EOS.
  List<int> _prepareTokens(String text, {required TaskType taskType}) {
    final encoded = tokenizer.encode(taskType.prefix + text);
    return <int>[_bosId, ...encoded.ids, _eosId];
  }

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    _assertNotClosed();
    final tokens = _prepareTokens(text, taskType: taskType);
    return _runForward(tokens);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    _assertNotClosed();
    return texts
        .map((text) => _runForward(_prepareTokens(text, taskType: taskType)))
        .toList();
  }

  @override
  Future<int> getDimension() async {
    _assertNotClosed();
    return outputDimension;
  }

  /// Run one forward pass over an already-tokenized input. Pads/truncates
  /// to [inputSequenceLength] and returns the [outputDimension]-element
  /// embedding as `List<double>`.
  List<double> _runForward(List<int> tokens) {
    final seq = inputSequenceLength;
    final dim = outputDimension;

    // Input tensor type [1, seq] Int32.
    final inType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeInt32
      ..rank = 2
      ..setDimension(0, 1)
      ..setDimension(1, seq);

    // Aligned host memory for input.
    final inAlloc = allocAligned(seq * 4);
    final inHost = inAlloc.aligned.cast<Int32>();
    for (var i = 0; i < seq; i++) {
      inHost[i] = i < tokens.length ? tokens[i] : 0;
    }

    final inBufPtr = calloc<LiteRtTensorBuffer>();
    _bindings
        .createTensorBufferFromHostMemory(inType.pointer,
            inAlloc.aligned.cast(), seq * 4, nullptr, inBufPtr)
        .check('CreateTensorBufferFromHostMemory(input)');

    // Output tensor type [1, dim] Float32.
    final outType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeFloat32
      ..rank = 2
      ..setDimension(0, 1)
      ..setDimension(1, dim);

    final outAlloc = allocAligned(dim * 4);
    final outBufPtr = calloc<LiteRtTensorBuffer>();
    _bindings
        .createTensorBufferFromHostMemory(outType.pointer,
            outAlloc.aligned.cast(), dim * 4, nullptr, outBufPtr)
        .check('CreateTensorBufferFromHostMemory(output)');

    try {
      _bindings
          .runCompiledModel(_compiledModel, 0, 1, inBufPtr, 1, outBufPtr)
          .check('LiteRtRunCompiledModel');

      final outFloat = outAlloc.aligned.cast<Float>();
      return List<double>.generate(dim, (i) => outFloat[i]);
    } finally {
      _bindings.destroyTensorBuffer(inBufPtr.value);
      _bindings.destroyTensorBuffer(outBufPtr.value);
      calloc.free(inBufPtr);
      calloc.free(outBufPtr);
      calloc.free(inAlloc.raw);
      calloc.free(outAlloc.raw);
      inType.free();
      outType.free();
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      _bindings.destroyCompiledModel(_compiledModel);
      _bindings.destroyOptions(_options);
      _bindings.destroyModel(_model);
      _bindings.destroyEnvironment(_environment);
    } finally {
      onClose();
    }
  }
}

/// Signature for the `onClose` callback. Same name Flutter uses.
typedef VoidCallback = void Function();
