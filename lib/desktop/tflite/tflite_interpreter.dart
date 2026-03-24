import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'tflite_bindings.dart';

/// TfLiteStatus codes from the C API.
class TfLiteStatus {
  static const int ok = 0;
  static const int error = 1;
  static const int delegateError = 2;
  static const int applicationError = 3;
}

/// High-level Dart wrapper around the TFLite C API.
///
/// Loads a `.tflite` model and runs inference with Int32 input / Float32 output.
/// Auto-detects input sequence length and output embedding dimension from the model.
class TfLiteInterpreter {
  TfLiteInterpreter._({
    required TfLiteBindings bindings,
    required Pointer<Void> model,
    required Pointer<Void> interpreter,
    required this.inputSequenceLength,
    required this.outputDimension,
  })  : _bindings = bindings,
        _model = model,
        _interpreter = interpreter;

  final TfLiteBindings _bindings;
  final Pointer<Void> _model;
  final Pointer<Void> _interpreter;
  bool _isClosed = false;

  /// Input tensor shape: [1, inputSequenceLength]
  final int inputSequenceLength;

  /// Output tensor shape: [1, outputDimension] (typically 768)
  final int outputDimension;

  /// Create an interpreter from a `.tflite` model file.
  ///
  /// [numThreads] controls CPU parallelism (default: 4).
  static TfLiteInterpreter fromFile(
    String modelPath, {
    int numThreads = 4,
    String? libraryPath,
  }) {
    final bindings = TfLiteBindings.load(libraryPath: libraryPath);

    // Load model
    final pathNative = modelPath.toNativeUtf8();
    final model = bindings.tfLiteModelCreateFromFile(pathNative);
    malloc.free(pathNative);

    if (model == nullptr) {
      throw StateError('Failed to load TFLite model from: $modelPath');
    }
    debugPrint('[TfLite] Model loaded OK: $model');

    // Create options
    final options = bindings.tfLiteInterpreterOptionsCreate();
    if (options == nullptr) {
      bindings.tfLiteModelDelete(model);
      throw StateError('Failed to create TFLite interpreter options');
    }
    bindings.tfLiteInterpreterOptionsSetNumThreads(options, numThreads);

    // Create interpreter (fallback to WithSelectedOps for quantized models)
    debugPrint('[TfLite] Trying TfLiteInterpreterCreate...');
    var interpreter = bindings.tfLiteInterpreterCreate(model, options);
    debugPrint('[TfLite] Result: $interpreter (nullptr: ${interpreter == nullptr})');
    if (interpreter == nullptr) {
      debugPrint('[TfLite] Trying TfLiteInterpreterCreateWithSelectedOps...');
      interpreter =
          bindings.tfLiteInterpreterCreateWithSelectedOps(model, options);
      debugPrint('[TfLite] Result: $interpreter (nullptr: ${interpreter == nullptr})');
    }
    bindings.tfLiteInterpreterOptionsDelete(options);

    if (interpreter == nullptr) {
      bindings.tfLiteModelDelete(model);
      throw StateError('Failed to create TFLite interpreter from: $modelPath');
    }

    // Allocate tensors
    final allocStatus = bindings.tfLiteInterpreterAllocateTensors(interpreter);
    if (allocStatus != TfLiteStatus.ok) {
      bindings.tfLiteInterpreterDelete(interpreter);
      bindings.tfLiteModelDelete(model);
      throw StateError(
          'Failed to allocate tensors (status: $allocStatus)');
    }

    // Auto-detect dimensions from model tensors
    final inputTensor = bindings.tfLiteInterpreterGetInputTensor(interpreter, 0);
    if (inputTensor == nullptr) {
      bindings.tfLiteInterpreterDelete(interpreter);
      bindings.tfLiteModelDelete(model);
      throw StateError('Input tensor not found at index 0');
    }
    final outputTensor =
        bindings.tfLiteInterpreterGetOutputTensor(interpreter, 0);
    if (outputTensor == nullptr) {
      bindings.tfLiteInterpreterDelete(interpreter);
      bindings.tfLiteModelDelete(model);
      throw StateError('Output tensor not found at index 0');
    }

    // Input shape: [1, sequenceLength]
    final inputSeqLen = bindings.tfLiteTensorDim(inputTensor, 1);

    // Output shape: [1, embeddingDimension]
    final outputDim = bindings.tfLiteTensorDim(outputTensor, 1);

    if (inputSeqLen <= 0 || outputDim <= 0) {
      bindings.tfLiteInterpreterDelete(interpreter);
      bindings.tfLiteModelDelete(model);
      throw StateError(
          'Invalid model tensor dimensions: input=$inputSeqLen, output=$outputDim');
    }

    return TfLiteInterpreter._(
      bindings: bindings,
      model: model,
      interpreter: interpreter,
      inputSequenceLength: inputSeqLen,
      outputDimension: outputDim,
    );
  }

  /// Run inference with Int32 token IDs, returns Float32 embedding vector.
  ///
  /// [tokenIds] will be padded/truncated to [inputSequenceLength].
  /// Returns a list of [outputDimension] doubles.
  List<double> run(List<int> tokenIds) {
    _assertNotClosed();

    // Pad/truncate to input sequence length
    final padded = Int32List(inputSequenceLength);
    final copyLen =
        tokenIds.length < inputSequenceLength ? tokenIds.length : inputSequenceLength;
    for (var i = 0; i < copyLen; i++) {
      padded[i] = tokenIds[i];
    }
    // Remaining values are already 0 (PAD token)

    // Copy input data to tensor
    final inputTensor =
        _bindings.tfLiteInterpreterGetInputTensor(_interpreter, 0);
    if (inputTensor == nullptr) {
      throw StateError('Input tensor not available');
    }
    final inputBytes = padded.lengthInBytes;
    final inputPtr = malloc<Int32>(inputSequenceLength);
    try {
      final inputList = inputPtr.asTypedList(inputSequenceLength);
      inputList.setAll(0, padded);

      final status = _bindings.tfLiteTensorCopyFromBuffer(
          inputTensor, inputPtr.cast(), inputBytes);
      if (status != TfLiteStatus.ok) {
        throw StateError('Failed to copy input data (status: $status)');
      }

      // Invoke
      final invokeStatus = _bindings.tfLiteInterpreterInvoke(_interpreter);
      if (invokeStatus != TfLiteStatus.ok) {
        throw StateError('Inference failed (status: $invokeStatus)');
      }

      // Read output
      final outputTensor =
          _bindings.tfLiteInterpreterGetOutputTensor(_interpreter, 0);
      if (outputTensor == nullptr) {
        throw StateError('Output tensor not available');
      }
      final outputPtr = malloc<Float>(outputDimension);
      try {
        final outputStatus = _bindings.tfLiteTensorCopyToBuffer(
            outputTensor, outputPtr.cast(), outputDimension * sizeOf<Float>());
        if (outputStatus != TfLiteStatus.ok) {
          throw StateError('Failed to read output (status: $outputStatus)');
        }

        final outputList = outputPtr.asTypedList(outputDimension);
        return List<double>.from(outputList);
      } finally {
        malloc.free(outputPtr);
      }
    } finally {
      malloc.free(inputPtr);
    }
  }

  /// Release all native resources.
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _bindings.tfLiteInterpreterDelete(_interpreter);
    _bindings.tfLiteModelDelete(_model);
  }

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
          'TfLiteInterpreter is closed. Create a new instance.');
    }
  }
}
