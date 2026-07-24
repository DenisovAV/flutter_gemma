// Synchronous, isolate-agnostic native core for LiteRT speech-to-text.
//
// Owns the LiteRT C API handles (environment, model, options, compiled
// model) and the HF tokenizer. `transcribe()` runs the blocking encode +
// autoregressive decode forward passes synchronously on the calling thread —
// it is meant to be driven from a background isolate (see `stt_worker.dart`)
// so the UI isolate stays free, mirroring `litert_embedding_core.dart`
// (#299).
//
// Generic over [SttModelProfile] — NOT model-specific. Only the
// `rawPcm`+`seq2seq` arm (moonshine-tiny) is implemented; it is a VERBATIM
// port of the verified recipe in
// `docs/superpowers/notes/stt-transcript-recipe.md`:
//   - mask convention C (padding-only additive mask: 0.0 if j<len else
//     -1e9, applied identically to every query row — NO causal triangle);
//   - decoder start token BOS=1;
//   - argmax taken at tensor row `len - 1` (the position just written);
//   - stop at EOS=2 or `profile.maxDecodeTokens`.
// `logMel`/`ctc` profiles throw `UnimplementedError` (follow-on — needs a
// mel/DSP frontend). Do NOT "improve" the mask into a causal triangle — the
// recipe found that degrades output; see the note's "What NOT to do".
//
// Buffer create/lock/write/run/read/unlock sequence mirrors
// `litert_embedding_core.dart`'s forward-pass pattern, generalized to the
// encoder→decoder pair of signatures moonshine-style seq2seq models use.
// Tensor shapes not fixed by [SttModelProfile] (encoder hidden dims, decode
// vocab size) are auto-detected from the compiled model's tensor layouts —
// this is what keeps the core generic instead of hardcoding moonshine's
// `[1,207,288]`/`32768`.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
// Public, native-only bindings library (not the package barrel): this file
// is native-only — never reached on web — so it always needs the real FFI
// bindings. See the equivalent comment in `litert_embedding_core.dart` for
// why this import (not the `if (dart.library.ffi)` barrel) is correct here.
import 'package:flutter_gemma_litertlm/litert_bindings.dart';

import '../model/stt_model_profile.dart';
import '../tokenizer/hf_tokenizer.dart';

/// Decoder start token (`<s>`), verified working on the first try — see the
/// recipe's "Mask convention that worked" section.
const int sttDecodeBosId = 1;

/// End-of-sequence token (`</s>`) — stops the greedy decode loop.
const int sttDecodeEosId = 2;

/// Pad with zeros or trim [samples] to exactly [windowSamples], per the
/// verified recipe's fixed-window step (moonshine: the first 80000 samples
/// = 5.000 s @ 16 kHz; zero-padded if the clip is shorter).
Float32List padOrTrimToWindow(Float32List samples, int windowSamples) {
  if (samples.length == windowSamples) return samples;
  final windowed = Float32List(windowSamples);
  final n = samples.length < windowSamples ? samples.length : windowSamples;
  windowed.setRange(0, n, samples);
  return windowed;
}

/// Index of the largest value in [values]. Ties keep the first (lowest
/// index) match — a standard greedy argmax.
int argmax(Float32List values) {
  var bestIndex = 0;
  var bestValue = values[0];
  for (var i = 1; i < values.length; i++) {
    if (values[i] > bestValue) {
      bestValue = values[i];
      bestIndex = i;
    }
  }
  return bestIndex;
}

/// Whether the greedy decode loop should stop: EOS was just generated, or
/// [generatedLength] has reached [maxDecodeTokens]. Pure — mirrors the
/// verified recipe's stop condition without touching native state.
bool shouldStopDecoding(
  int lastGeneratedId,
  int generatedLength,
  int maxDecodeTokens,
) {
  return lastGeneratedId == sttDecodeEosId ||
      generatedLength >= maxDecodeTokens;
}

int _acceleratorFor(PreferredBackend? backend) {
  switch (backend) {
    case PreferredBackend.gpu:
      return kLiteRtHwAcceleratorGpu;
    case PreferredBackend.npu:
      return kLiteRtHwAcceleratorNpu;
    case PreferredBackend.cpu:
    case null:
      return kLiteRtHwAcceleratorCpu;
  }
}

/// The encoder's output tensor (`decode_args_0` for every decode step),
/// plus the auto-detected shape needed to describe it to LiteRT again.
class _EncoderOutput {
  _EncoderOutput(this.alloc, this.frames, this.dim);
  final AlignedAlloc alloc;
  final int frames;
  final int dim;
}

/// Synchronous native STT core. NOT safe to share across isolates — the FFI
/// handles it holds are owned by the isolate that called [load].
class SttCore {
  SttCore._({
    required this._bindings,
    required this._environment,
    required this._model,
    required this._options,
    required this._compiledModel,
    required this._tokenizer,
    required this._profile,
  });

  final LiteRtBindings _bindings;
  final LiteRtEnvironment _environment;
  final LiteRtModel _model;
  final LiteRtOptions _options;
  final LiteRtCompiledModel _compiledModel;
  final HfTokenizer _tokenizer;
  final SttModelProfile _profile;

  bool _disposed = false;

  /// Load a `.tflite` STT model + its HF tokenizer and compile the model for
  /// [backend]. Heavy — call once, from a background isolate.
  static Future<SttCore> load({
    required String modelPath,
    required String tokenizerPath,
    required SttModelProfile profile,
    PreferredBackend? backend,
  }) async {
    if (profile.inputType != SttInputType.rawPcm ||
        profile.decodeType != SttDecodeType.seq2seq) {
      throw UnimplementedError(
        'SttCore: only rawPcm+seq2seq profiles are implemented '
        '(logMel/ctc are follow-ons; see the design spec).',
      );
    }

    final bindings = LiteRtBindings.open();
    final tokenizer = await HfTokenizer.fromFile(tokenizerPath);

    // Track native handles as they are created so a failure partway through
    // frees everything already allocated instead of leaking it — the LiteRT
    // native heap is process-global and is NOT reclaimed by the isolate
    // dying. Mirrors `EmbeddingCore.load`.
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

      final pathC = modelPath.toNativeUtf8();
      final modelPtr = calloc<LiteRtModel>();
      try {
        bindings
            .createModelFromFile(environment, pathC, modelPtr)
            .check('LiteRtCreateModelFromFile($modelPath)');
      } finally {
        calloc.free(pathC);
      }
      model = modelPtr.value;
      calloc.free(modelPtr);

      final optsPtr = calloc<LiteRtOptions>();
      bindings.createOptions(optsPtr).check('LiteRtCreateOptions');
      options = optsPtr.value;
      calloc.free(optsPtr);
      bindings
          .setOptionsHardwareAccelerators(options, _acceleratorFor(backend))
          .check('LiteRtSetOptionsHardwareAccelerators');

      final compiledPtr = calloc<LiteRtCompiledModel>();
      bindings
          .createCompiledModel(environment, model, options, compiledPtr)
          .check('LiteRtCreateCompiledModel');
      compiled = compiledPtr.value;
      calloc.free(compiledPtr);

      gemmaLog('[SttCore] loaded: backend=$backend');

      return SttCore._(
        bindings: bindings,
        environment: environment,
        model: model,
        options: options,
        compiledModel: compiled,
        tokenizer: tokenizer,
        profile: profile,
      );
    } catch (_) {
      if (compiled != null) bindings.destroyCompiledModel(compiled);
      if (options != null) bindings.destroyOptions(options);
      if (model != null) bindings.destroyModel(model);
      if (environment != null) bindings.destroyEnvironment(environment);
      rethrow;
    }
  }

  /// Transcribe one fixed window of audio: pad/trim to
  /// `profile.windowSamples`, run the encoder (signature 0), then the
  /// greedy autoregressive decode loop (signature 1) until EOS or
  /// `profile.maxDecodeTokens`, then detokenize.
  String transcribe(Float32List samples) {
    if (_disposed) {
      throw StateError('SttCore is disposed');
    }
    final windowed = padOrTrimToWindow(samples, _profile.windowSamples);
    final hidden = _encode(windowed);
    try {
      final ids = _decodeLoop(hidden);
      return _tokenizer.detokenize(ids);
    } finally {
      calloc.free(hidden.alloc.raw);
    }
  }

  /// Run the encoder (signature index 0): `f32[1, windowSamples]` →
  /// `f32[1, frames, dim]`. `frames`/`dim` are auto-detected from the
  /// compiled model's output tensor layout — generic over the profile, no
  /// hardcoded moonshine dimensions. The returned allocation's raw memory
  /// (the encoder hidden state) is kept alive by the caller: it becomes
  /// `decode_args_0`'s backing store for every decode step.
  _EncoderOutput _encode(Float32List samples) {
    final windowSamples = samples.length;

    final outLayout = LiteRtLayoutView.calloc();
    int frames, dim;
    try {
      _bindings
          .getOutputTensorLayouts(
            _compiledModel,
            0,
            1,
            outLayout.pointer,
            false,
          )
          .check('LiteRtGetCompiledModelOutputTensorLayouts(encode)');
      if (outLayout.rank < 3) {
        throw StateError(
          'STT encoder output has rank=${outLayout.rank}, expected 3',
        );
      }
      frames = outLayout.dimension(1);
      dim = outLayout.dimension(2);
    } finally {
      outLayout.free();
    }

    final inType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeFloat32
      ..rank = 2
      ..setDimension(0, 1)
      ..setDimension(1, windowSamples);
    final inAlloc = allocAligned(windowSamples * 4);
    final inBufPtr = calloc<LiteRtTensorBuffer>();
    var inBufCreated = false;

    final outType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeFloat32
      ..rank = 3
      ..setDimension(0, 1)
      ..setDimension(1, frames)
      ..setDimension(2, dim);
    final outAlloc = allocAligned(frames * dim * 4);
    final outBufPtr = calloc<LiteRtTensorBuffer>();
    var outBufCreated = false;
    // On success outAlloc.raw is intentionally kept alive (it backs
    // decode_args_0); on ANY throw before the return it must be freed here or
    // it leaks native heap permanently (~frames*dim*4 bytes per failed encode).
    var returning = false;

    try {
      final inHost = inAlloc.aligned.cast<Float>();
      for (var i = 0; i < windowSamples; i++) {
        inHost[i] = samples[i];
      }

      _bindings
          .createTensorBufferFromHostMemory(
            inType.pointer,
            inAlloc.aligned.cast(),
            windowSamples * 4,
            nullptr,
            inBufPtr,
          )
          .check('CreateTensorBufferFromHostMemory(encode in)');
      inBufCreated = true;

      _bindings
          .createTensorBufferFromHostMemory(
            outType.pointer,
            outAlloc.aligned.cast(),
            frames * dim * 4,
            nullptr,
            outBufPtr,
          )
          .check('CreateTensorBufferFromHostMemory(encode out)');
      outBufCreated = true;

      _bindings
          .runCompiledModel(_compiledModel, 0, 1, inBufPtr, 1, outBufPtr)
          .check('LiteRtRunCompiledModel(encode)');

      // Lock(Read) triggers the device→host sync on GPU/NPU. Read the hidden
      // state THROUGH the locked pointer: on GPU/NPU the accelerator writes
      // into device memory and Lock(Read) exposes a host-accessible copy that
      // may NOT be outAlloc — copying from lockedPtr into outAlloc (which
      // backs decode_args_0) guarantees the hidden state is materialized.
      // On CPU lockedPtr is the same host memory (a no-op self-copy, skipped).
      // Without this the host buffer stays zero on GPU → decode runs on zeros
      // → silent empty transcript. Mirrors litert_embedding_core.dart.
      final lockedPtr = calloc<Pointer<Void>>();
      try {
        _bindings
            .lockTensorBuffer(
              outBufPtr.value,
              lockedPtr,
              kLiteRtTensorBufferLockModeRead,
            )
            .check('LiteRtLockTensorBuffer(encode out)');
        final locked = lockedPtr.value.cast<Float>();
        final dst = outAlloc.aligned.cast<Float>();
        if (locked.address != dst.address) {
          for (var i = 0; i < frames * dim; i++) {
            dst[i] = locked[i];
          }
        }
        _bindings
            .unlockTensorBuffer(outBufPtr.value)
            .check('LiteRtUnlockTensorBuffer(encode out)');
      } finally {
        calloc.free(lockedPtr);
      }

      returning = true;
      return _EncoderOutput(outAlloc, frames, dim);
    } finally {
      if (inBufCreated) _bindings.destroyTensorBuffer(inBufPtr.value);
      // Destroying the tensor buffer WRAPPER does not free outAlloc's raw
      // host memory — that memory is kept alive and reused as
      // decode_args_0's backing store (freed by the caller after decode).
      if (outBufCreated) _bindings.destroyTensorBuffer(outBufPtr.value);
      calloc.free(inBufPtr);
      calloc.free(outBufPtr);
      calloc.free(inAlloc.raw);
      if (!returning) calloc.free(outAlloc.raw);
      inType.free();
      outType.free();
    }
  }

  /// Greedy autoregressive decode (signature index 1). `decode_args_0`
  /// (the encoder hidden state) is created once from [hidden] and reused
  /// unchanged for every step; `decode_args_1` (token ids) and
  /// `decode_args_2` (mask) are rewritten and recreated fresh each step.
  List<int> _decodeLoop(_EncoderOutput hidden) {
    final maxTokens = _profile.maxDecodeTokens;

    // Discover the decode output vocab size (dimension 2 of
    // f32[1, maxTokens, vocab]) — generic over the profile. Done BEFORE
    // creating the hidden TensorBuffer so a failure here leaks no native
    // handle (the buffer + its destroy-in-finally are set up only after this).
    final outLayout = LiteRtLayoutView.calloc();
    int vocabSize;
    try {
      _bindings
          .getOutputTensorLayouts(
            _compiledModel,
            1,
            1,
            outLayout.pointer,
            false,
          )
          .check('LiteRtGetCompiledModelOutputTensorLayouts(decode)');
      if (outLayout.rank < 3) {
        throw StateError(
          'STT decode output has rank=${outLayout.rank}, expected 3',
        );
      }
      vocabSize = outLayout.dimension(2);
    } finally {
      outLayout.free();
    }

    // decode_args_0: the encoder hidden state, wrapped once and reused every
    // step. Created after vocab discovery so it is always covered by the
    // try/finally below that destroys it.
    final hiddenType = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeFloat32
      ..rank = 3
      ..setDimension(0, 1)
      ..setDimension(1, hidden.frames)
      ..setDimension(2, hidden.dim);
    final hiddenBufPtr = calloc<LiteRtTensorBuffer>();
    _bindings
        .createTensorBufferFromHostMemory(
          hiddenType.pointer,
          hidden.alloc.aligned.cast(),
          hidden.frames * hidden.dim * 4,
          nullptr,
          hiddenBufPtr,
        )
        .check('CreateTensorBufferFromHostMemory(decode hidden)');
    hiddenType.free();

    final tokensAlloc = allocAligned(maxTokens * 4);
    final maskAlloc = allocAligned(maxTokens * maxTokens * 4);
    final decodeOutAlloc = allocAligned(maxTokens * vocabSize * 4);

    try {
      final tokensHost = tokensAlloc.aligned.cast<Int32>();
      final maskHost = maskAlloc.aligned.cast<Float>();

      final generated = <int>[sttDecodeBosId];
      while (true) {
        final len = generated.length;

        // decode_args_1: i32[1, maxTokens] — token ids so far, right-padded
        // with 0.
        for (var i = 0; i < maxTokens; i++) {
          tokensHost[i] = i < len ? generated[i] : 0;
        }

        // decode_args_2: f32[1,1,maxTokens,maxTokens] — mask convention C
        // (verified recipe): padding-only additive mask, identical across
        // every query row — NO causal triangle. Do not change this to a
        // causal mask (convention A) or a multiplicative mask (B) — both
        // produced worse or garbage output; see the recipe's "What NOT to
        // do".
        for (var r = 0; r < maxTokens; r++) {
          final rowBase = r * maxTokens;
          for (var j = 0; j < maxTokens; j++) {
            maskHost[rowBase + j] = j < len ? 0.0 : -1e9;
          }
        }

        final tokType = LiteRtRankedTensorTypeView.calloc()
          ..elementType = kLiteRtElementTypeInt32
          ..rank = 2
          ..setDimension(0, 1)
          ..setDimension(1, maxTokens);
        final maskType = LiteRtRankedTensorTypeView.calloc()
          ..elementType = kLiteRtElementTypeFloat32
          ..rank = 4
          ..setDimension(0, 1)
          ..setDimension(1, 1)
          ..setDimension(2, maxTokens)
          ..setDimension(3, maxTokens);
        final outType = LiteRtRankedTensorTypeView.calloc()
          ..elementType = kLiteRtElementTypeFloat32
          ..rank = 3
          ..setDimension(0, 1)
          ..setDimension(1, maxTokens)
          ..setDimension(2, vocabSize);

        final tokBufPtr = calloc<LiteRtTensorBuffer>();
        final maskBufPtr = calloc<LiteRtTensorBuffer>();
        final outBufPtr = calloc<LiteRtTensorBuffer>();
        var tokCreated = false, maskCreated = false, outCreated = false;
        int bestId;
        var nanLogit = false;

        try {
          _bindings
              .createTensorBufferFromHostMemory(
                tokType.pointer,
                tokensAlloc.aligned.cast(),
                maxTokens * 4,
                nullptr,
                tokBufPtr,
              )
              .check('CreateTensorBufferFromHostMemory(decode tokens)');
          tokCreated = true;

          _bindings
              .createTensorBufferFromHostMemory(
                maskType.pointer,
                maskAlloc.aligned.cast(),
                maxTokens * maxTokens * 4,
                nullptr,
                maskBufPtr,
              )
              .check('CreateTensorBufferFromHostMemory(decode mask)');
          maskCreated = true;

          _bindings
              .createTensorBufferFromHostMemory(
                outType.pointer,
                decodeOutAlloc.aligned.cast(),
                maxTokens * vocabSize * 4,
                nullptr,
                outBufPtr,
              )
              .check('CreateTensorBufferFromHostMemory(decode out)');
          outCreated = true;

          // Exact input order: decode_args_0 (hidden), decode_args_1
          // (tokens), decode_args_2 (mask).
          final inputs = calloc<LiteRtTensorBuffer>(3);
          inputs[0] = hiddenBufPtr.value;
          inputs[1] = tokBufPtr.value;
          inputs[2] = maskBufPtr.value;
          try {
            _bindings
                .runCompiledModel(_compiledModel, 1, 3, inputs, 1, outBufPtr)
                .check('LiteRtRunCompiledModel(decode)');
          } finally {
            calloc.free(inputs);
          }

          final lockedPtr = calloc<Pointer<Void>>();
          try {
            _bindings
                .lockTensorBuffer(
                  outBufPtr.value,
                  lockedPtr,
                  kLiteRtTensorBufferLockModeRead,
                )
                .check('LiteRtLockTensorBuffer(decode out)');
            // Argmax is taken at tensor row `len - 1` (0-indexed) — the
            // position of the token that was just written into the padded
            // sequence, NOT row 0 and NOT the last row.
            final row = len - 1;
            final logits = lockedPtr.value.cast<Float>().asTypedList(
              maxTokens * vocabSize,
            );
            final rowLogits = logits.sublist(
              row * vocabSize,
              (row + 1) * vocabSize,
            );
            bestId = argmax(rowLogits);
            // A NaN top logit means the backend produced invalid output (e.g.
            // a GPU/accelerator failure, cf. #214). argmax then collapses to
            // id 0 (<unk>), which detokenizes to '' and would be returned as a
            // "successful" empty transcript indistinguishable from a silent
            // clip. Flag it here and fail loudly after cleanup instead.
            nanLogit = rowLogits[bestId].isNaN;
            _bindings
                .unlockTensorBuffer(outBufPtr.value)
                .check('LiteRtUnlockTensorBuffer(decode out)');
          } finally {
            calloc.free(lockedPtr);
          }
        } finally {
          if (tokCreated) _bindings.destroyTensorBuffer(tokBufPtr.value);
          if (maskCreated) _bindings.destroyTensorBuffer(maskBufPtr.value);
          if (outCreated) _bindings.destroyTensorBuffer(outBufPtr.value);
          calloc.free(tokBufPtr);
          calloc.free(maskBufPtr);
          calloc.free(outBufPtr);
          tokType.free();
          maskType.free();
          outType.free();
        }

        if (nanLogit) {
          throw StateError(
            'STT decode produced NaN logits at step $len — the model backend '
            'returned invalid output; transcription aborted rather than '
            'silently returning an empty result.',
          );
        }

        generated.add(bestId);
        if (shouldStopDecoding(bestId, generated.length, maxTokens)) {
          return generated;
        }
      }
    } finally {
      _bindings.destroyTensorBuffer(hiddenBufPtr.value);
      calloc.free(hiddenBufPtr);
      calloc.free(tokensAlloc.raw);
      calloc.free(maskAlloc.raw);
      calloc.free(decodeOutAlloc.raw);
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
