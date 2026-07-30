// Synchronous, isolate-agnostic native core for Matcha-TTS on-device
// synthesis.
//
// Owns the LiteRT C API handles (one environment + 3 compiled graphs:
// text-encoder, CFM decoder, HiFi-GAN vocoder) for a `matchaCfm` pipeline.
// `synthesize()` runs the blocking forward passes + host-side ODE math
// synchronously on the calling thread — like `SttCore.transcribe`, it is
// meant to be driven from a background isolate so the UI isolate stays free.
//
// This is a PORT, not new work. The math (text-encoder -> host duration +
// Glow-TTS-style length regulator -> N-step Euler CFM decoder -> mel denorm
// -> HiFi-GAN vocoder -> 16-bit PCM) is a verbatim line-for-line port of the
// verified reconstruction script `matcha_synth.dart` (`main()` lines
// 505-618, helpers `_searchSortedRight`/`_tSin`/`_nextGaussian`/`runGraph`).
// The FFI STYLE is ported from `stt_core.dart` instead of that script's raw
// `dlopen`: `matcha_synth.dart` opens the dylib directly by path, which does
// NOT work inside this package (the native lib is loaded via Native
// Assets — see `LiteRtBindings.open()`/`_openLiteRt()` in
// `package:flutter_gemma_litertlm/litert_bindings.dart`). So every graph run
// here goes through `LiteRtBindings`'s create -> run -> lock(Read) ->
// copy-through-locked-ptr -> unlock -> destroy tensor-buffer sequence,
// exactly like `SttCore._encode`/`_decodeLoop`, generalized to N inputs / M
// outputs (the multi-input pattern mirrors `SttCore._decodeLoop`'s 3-input
// decode at stt_core.dart:504-527: each buffer is created into its own
// single-slot pointer, then `.value` is copied into a fresh combined array
// right before the run call).
//
// Generic over [TtsModelProfile] — only `TtsPipelineKind.matchaCfm` is
// implemented; kokoro/supertonic profiles are documented follow-ons. The
// `dp_g2p` graph is intentionally NOT loaded here — it's the neural OOV
// fallback, and the dictionary-only `TtsTextFrontend` (Task 2.2) covers the
// golden path; loading it is a Phase-2 residual.
//
// Determinism: the Euler CFM decoder's initial noise is drawn from a FIXED
// seed ([ttsCfmSeed]) via Box-Muller ([nextGaussian]), so [TtsCore.synthesize]
// is byte-reproducible run-to-run — the Phase-3 golden depends on this. Do
// NOT change the seed or the Box-Muller formula without regenerating it.
//
// Leak-safety: buffer create/lock/read/unlock/destroy mirrors
// `litert_embedding_core.dart`'s forward-pass pattern; `load`'s partial-
// failure cleanup mirrors `SttCore.load`, generalized to 3 compiled graphs
// (a failure loading e.g. the decoder frees the already-loaded text-encoder
// + the shared environment before rethrowing).

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
// Public, native-only bindings library (not the package barrel) — see the
// equivalent comment in `stt_core.dart`/`litert_embedding_core.dart` for why
// this import (not the `if (dart.library.ffi)` barrel) is correct in a
// native-only file.
import 'package:flutter_gemma_litertlm/litert_bindings.dart';

import '../model/tts_model_profile.dart';
import '../tts/tts_frontend_input.dart';

/// The Euler CFM decoder's fixed Gaussian-noise seed. Fixed (not
/// time-derived) so [TtsCore.synthesize] is byte-reproducible run-to-run —
/// the Phase-3 golden depends on this. Verified value from
/// `matcha_synth.dart:565`.
const int ttsCfmSeed = 1234;

/// Leftmost `i` such that `cum[i-1] <= v < cum[i]` (numpy `searchsorted`,
/// `side='right'`). Used by the Glow-TTS-style length regulator to look up
/// which text-encoder frame each mel frame belongs to. Verbatim port of
/// `matcha_synth.dart`'s `_searchSortedRight`.
int searchSortedRight(Float64List cum, double v) {
  var lo = 0, hi = cum.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Sinusoidal timestep embedding (length `half * 2`, 160 for Matcha's
/// `half=80`) fed to the CFM decoder at every Euler step. Verbatim port of
/// `matcha_synth.dart`'s `_tSin`.
Float32List tSin(double t, {int half = 80}) {
  final e = Float64List(half);
  for (var i = 0; i < half; i++) {
    e[i] = 1000.0 * t * math.exp(i * (-math.log(10000) / (half - 1)));
  }
  final out = Float32List(half * 2);
  for (var i = 0; i < half; i++) {
    out[i] = math.sin(e[i]);
    out[half + i] = math.cos(e[i]);
  }
  return out;
}

/// One standard-normal sample via Box-Muller, drawn from [r]. Verbatim port
/// of `matcha_synth.dart`'s `_nextGaussian` — used with [ttsCfmSeed] to seed
/// the CFM decoder's initial noise reproducibly.
double nextGaussian(math.Random r) {
  var u1 = r.nextDouble();
  while (u1 <= 1e-12) {
    u1 = r.nextDouble();
  }
  final u2 = r.nextDouble();
  return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
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

String _artifactPath(Map<String, String> artifactPaths, String file) {
  final path = artifactPaths[file];
  if (path == null) {
    throw StateError('TtsCore: bundle is missing "$file" in artifactPaths');
  }
  return path;
}

/// One compiled Matcha graph's handles (model/options/compiledModel), freed
/// together by [TtsCore.dispose] or by [TtsCore.load]'s partial-failure
/// cleanup.
class _LoadedGraph {
  _LoadedGraph(this.model, this.options, this.compiledModel);
  final LiteRtModel model;
  final LiteRtOptions options;
  final LiteRtCompiledModel compiledModel;
}

/// Loads + compiles one `.tflite` graph at [path], mirroring the
/// model/options/compiled sequence `SttCore.load` runs for its single model
/// — generalized so [TtsCore.load] can call it 3 times (text-encoder,
/// decoder, vocoder). On any failure partway through, frees whatever handles
/// it already created for THIS graph before rethrowing; the caller is
/// responsible for freeing any earlier, already-succeeded graphs + the
/// shared environment.
_LoadedGraph _loadGraph(
  LiteRtBindings bindings,
  LiteRtEnvironment environment,
  String path,
  int accelerator,
) {
  LiteRtModel? model;
  LiteRtOptions? options;
  LiteRtCompiledModel? compiled;
  try {
    final pathC = path.toNativeUtf8();
    final modelPtr = calloc<LiteRtModel>();
    try {
      bindings
          .createModelFromFile(environment, pathC, modelPtr)
          .check('LiteRtCreateModelFromFile($path)');
    } finally {
      calloc.free(pathC);
    }
    model = modelPtr.value;
    calloc.free(modelPtr);

    final optsPtr = calloc<LiteRtOptions>();
    bindings.createOptions(optsPtr).check('LiteRtCreateOptions($path)');
    options = optsPtr.value;
    calloc.free(optsPtr);
    bindings
        .setOptionsHardwareAccelerators(options, accelerator)
        .check('LiteRtSetOptionsHardwareAccelerators($path)');

    final compiledPtr = calloc<LiteRtCompiledModel>();
    bindings
        .createCompiledModel(environment, model, options, compiledPtr)
        .check('LiteRtCreateCompiledModel($path)');
    compiled = compiledPtr.value;
    calloc.free(compiledPtr);

    return _LoadedGraph(model, options, compiled);
  } catch (_) {
    if (compiled != null) bindings.destroyCompiledModel(compiled);
    if (options != null) bindings.destroyOptions(options);
    if (model != null) bindings.destroyModel(model);
    rethrow;
  }
}

/// One tensor buffer's raw host allocation + its LiteRT wrapper handle,
/// freed together in `TtsCore._runGraph`'s `finally`. Mirrors
/// `matcha_synth.dart`'s `_TensorHandle`.
class _TensorHandle {
  _TensorHandle(this.raw, this.buffer);
  final Pointer<Uint8> raw;
  final LiteRtTensorBuffer buffer;
}

/// Synchronous native TTS core. NOT safe to share across isolates — the FFI
/// handles it holds are owned by the isolate that called [load].
class TtsCore {
  TtsCore._({
    required this._bindings,
    required this._environment,
    required this._textEncoder,
    required this._decoder,
    required this._vocoder,
    required this._nFeats,
    required this._nChannels,
    required this._maxText,
    required this._maxMel,
    required this._hop,
    required this._sampleRate,
    required this._lengthScale,
    required this._nTimesteps,
    required this._melStd,
    required this._melMean,
  });

  final LiteRtBindings _bindings;
  final LiteRtEnvironment _environment;
  final _LoadedGraph _textEncoder;
  final _LoadedGraph _decoder;
  final _LoadedGraph _vocoder;

  final int _nFeats;
  final int _nChannels;
  final int _maxText;
  final int _maxMel;
  final int _hop;
  final int _sampleRate;
  final double _lengthScale;
  final int _nTimesteps;
  final double _melStd;
  final double _melMean;

  bool _disposed = false;

  /// Loads `config.json` and compiles the 3 Matcha graphs (text-encoder,
  /// decoder, vocoder) for [backend]. Heavy — call once, from a background
  /// isolate. [artifactPaths] is filename -> on-disk-path for the model
  /// bundle (from `RuntimeConfig.artifactPaths`).
  static Future<TtsCore> load({
    required TtsModelProfile profile,
    required Map<String, String> artifactPaths,
    PreferredBackend? backend,
  }) async {
    if (profile.pipeline != TtsPipelineKind.matchaCfm) {
      throw UnimplementedError(
        'TtsCore: only TtsPipelineKind.matchaCfm is implemented '
        '(kokoro/supertonic are follow-ons; see the design spec).',
      );
    }

    final configPath = _artifactPath(artifactPaths, profile.configFile);
    final config =
        jsonDecode(await File(configPath).readAsString())
            as Map<String, dynamic>;
    final nFeats = (config['n_feats'] as num).toInt();
    final nChannels = (config['n_channels'] as num).toInt();
    final maxText = (config['MAX_TEXT'] as num).toInt();
    final maxMel = (config['MAX_MEL'] as num).toInt();
    final hop = (config['hop'] as num).toInt();
    final sampleRate = (config['sample_rate'] as num).toInt();
    final lengthScale = (config['length_scale'] as num).toDouble();
    final nTimesteps = (config['n_timesteps_default'] as num).toInt();
    final melStd = (config['mel_std'] as num).toDouble();
    final melMean = (config['mel_mean'] as num).toDouble();

    final bindings = LiteRtBindings.open();
    final accelerator = _acceleratorFor(backend);

    // Track handles as they're created so a failure partway through (e.g.
    // the decoder graph fails to compile after the text-encoder already
    // loaded) frees everything already allocated instead of leaking it — the
    // LiteRT native heap is process-global and is NOT reclaimed by the
    // isolate dying. Mirrors `SttCore.load`, generalized to 3 graphs.
    LiteRtEnvironment? environment;
    final loadedGraphs = <_LoadedGraph>[];
    try {
      final envPtr = calloc<LiteRtEnvironment>();
      bindings
          .createEnvironment(0, nullptr, envPtr)
          .check('LiteRtCreateEnvironment');
      environment = envPtr.value;
      calloc.free(envPtr);

      final textEncoder = _loadGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, profile.textEncoderFile),
        accelerator,
      );
      loadedGraphs.add(textEncoder);

      final decoder = _loadGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, profile.decoderFile),
        accelerator,
      );
      loadedGraphs.add(decoder);

      final vocoder = _loadGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, profile.vocoderFile),
        accelerator,
      );
      loadedGraphs.add(vocoder);

      // dp_g2p (profile.g2pFile) is intentionally NOT loaded — it's the
      // neural OOV fallback; the dictionary-only TtsTextFrontend (Task 2.2)
      // covers the golden path. Loading it is a documented Phase-2 residual.

      gemmaLog('[TtsCore] loaded: backend=$backend, 3 graphs compiled');

      return TtsCore._(
        bindings: bindings,
        environment: environment,
        textEncoder: textEncoder,
        decoder: decoder,
        vocoder: vocoder,
        nFeats: nFeats,
        nChannels: nChannels,
        maxText: maxText,
        maxMel: maxMel,
        hop: hop,
        sampleRate: sampleRate,
        lengthScale: lengthScale,
        nTimesteps: nTimesteps,
        melStd: melStd,
        melMean: melMean,
      );
    } catch (_) {
      for (final graph in loadedGraphs) {
        bindings.destroyCompiledModel(graph.compiledModel);
        bindings.destroyOptions(graph.options);
        bindings.destroyModel(graph.model);
      }
      if (environment != null) bindings.destroyEnvironment(environment);
      rethrow;
    }
  }

  /// Output sample rate (Hz), read from `config.json`.
  int get sampleRate => _sampleRate;

  /// Runs the full Matcha forward pass for a prepared frontend [input]:
  /// text-encoder -> host duration + Glow-TTS length regulator -> N-step
  /// Euler CFM decoder -> mel denorm -> HiFi-GAN vocoder -> 16-bit PCM.
  /// Verbatim port of `matcha_synth.dart:518-635`'s math; every graph run
  /// goes through [_runGraph] instead of that script's raw-`dlopen`
  /// `runGraph`. Returns 16-bit little-endian mono PCM with NO WAV header
  /// (length `ylen * hop * 2` bytes) — the example's `pcmToWav` adds a
  /// header in Phase 3.
  Uint8List synthesize(MatchaFrontendInput input) {
    if (_disposed) {
      throw StateError('TtsCore is disposed');
    }

    // --- text encoder: symbolEmbeddings[1,maxText,nChannels] +
    //     textMask[1,1,maxText] -> mu[1,nFeats,maxText], logw[1,1,maxText] ---
    final teOut = _runGraph(
      _textEncoder.compiledModel,
      [
        ([1, _maxText, _nChannels], input.symbolEmbeddings),
        ([1, 1, _maxText], input.textMask),
      ],
      [
        [1, _nFeats, _maxText],
        [1, 1, _maxText],
      ],
    );
    final mu = teOut[0]; // feat-major [nFeats*maxText]: mu[f*maxText+pos]
    final logw = teOut[1]; // [maxText]

    // --- duration + Glow-TTS-style length regulator ---
    // w = ceil(exp(logw) * textMask) * lengthScale (verbatim).
    final w = Float64List(_maxText);
    for (var t = 0; t < _maxText; t++) {
      w[t] =
          (math.exp(logw[t]) * input.textMask[t]).ceilToDouble() * _lengthScale;
    }
    final cum = Float64List(_maxText);
    var running = 0.0;
    for (var t = 0; t < _maxText; t++) {
      running += w[t];
      cum[t] = running;
    }
    final rawYlen = cum[_maxText - 1];
    if (rawYlen.ceil() > _maxMel) {
      throw StateError(
        'TtsCore: predicted ${rawYlen.ceil()} mel frames > MAX_MEL $_maxMel '
        '(~${(_maxMel * _hop / _sampleRate).toStringAsFixed(1)}s cap). '
        'Chunk the text into shorter clauses.',
      );
    }
    final ylen = rawYlen.clamp(1.0, _maxMel.toDouble()).toInt();

    final muY = Float32List(_nFeats * _maxMel);
    final ymask = Float32List(_maxMel);
    for (var t = 0; t < ylen; t++) {
      var idx = searchSortedRight(cum, t.toDouble());
      if (idx > _maxText - 1) idx = _maxText - 1;
      for (var f = 0; f < _nFeats; f++) {
        muY[f * _maxMel + t] = mu[f * _maxText + idx];
      }
      ymask[t] = 1.0;
    }

    // --- Euler CFM ODE loop, ttsCfmSeed-fixed Gaussian noise so
    // synthesize() is byte-reproducible run-to-run (the Phase-3 golden
    // depends on this). ---
    final rnd = math.Random(ttsCfmSeed);
    final x = Float32List(_nFeats * _maxMel);
    for (var f = 0; f < _nFeats; f++) {
      for (var t = 0; t < ylen; t++) {
        x[f * _maxMel + t] = nextGaussian(rnd);
      }
    }

    for (var k = 0; k < _nTimesteps; k++) {
      final tEmb = tSin(k / _nTimesteps);
      final decOut = _runGraph(
        _decoder.compiledModel,
        [
          ([1, _nFeats, _maxMel], x), // x / z_t
          ([1, _nFeats, _maxMel], muY),
          ([1, 160], tEmb), // sinusoidal timestep embed
          ([1, 1, _maxMel], ymask),
        ],
        [
          [1, _nFeats, _maxMel],
        ],
      );
      final v = decOut[0];
      for (var i = 0; i < x.length; i++) {
        x[i] += v[i] / _nTimesteps;
      }
    }

    // --- mel denorm ---
    final mel = Float32List(_nFeats * _maxMel);
    for (var f = 0; f < _nFeats; f++) {
      for (var t = 0; t < ylen; t++) {
        mel[f * _maxMel + t] = x[f * _maxMel + t] * _melStd + _melMean;
      }
    }

    // --- vocoder: mel[1,nFeats,maxMel] -> wav[1,1,maxMel*hop] ---
    final vocOut = _runGraph(
      _vocoder.compiledModel,
      [
        ([1, _nFeats, _maxMel], mel),
      ],
      [
        [1, 1, _maxMel * _hop],
      ],
    );
    final wav = vocOut[0];
    final numSamples = ylen * _hop;

    // --- clip[-1,1] -> 16-bit LE mono PCM, NO WAV header. ---
    final pcm = Uint8List(numSamples * 2);
    final pcmView = ByteData.sublistView(pcm);
    for (var i = 0; i < numSamples; i++) {
      var s = wav[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      var q = (s * 32767.0).round();
      if (q > 32767) q = 32767;
      if (q < -32768) q = -32768;
      pcmView.setInt16(i * 2, q, Endian.little);
    }
    return pcm;
  }

  /// Generic multi-input/multi-output f32 forward pass over one compiled
  /// [graph], signature index 0. Mirrors `SttCore._encode`/`_decodeLoop`'s
  /// tensor-buffer create -> run -> lock(Read) -> copy-through-locked-ptr ->
  /// unlock -> destroy sequence, generalized to N inputs / M outputs — this
  /// replaces `matcha_synth.dart`'s raw-`dlopen` `runGraph`. [inputs] and
  /// [outputShapes] must list tensors in the model's declared signature-0
  /// argument order.
  List<Float32List> _runGraph(
    LiteRtCompiledModel graph,
    List<(List<int> shape, Float32List data)> inputs,
    List<List<int>> outputShapes,
  ) {
    final inHandles = <_TensorHandle>[];
    final outHandles = <_TensorHandle>[];
    try {
      for (final (shape, data) in inputs) {
        inHandles.add(_createF32TensorBuffer(shape, data));
      }
      for (final shape in outputShapes) {
        outHandles.add(_createF32TensorBuffer(shape, null));
      }

      // Combined arrays are built fresh right before the call and freed
      // right after, mirroring `SttCore._decodeLoop`'s 3-input decode
      // (stt_core.dart:504-527): each buffer was created into its own
      // single-slot pointer above; only `.value` is copied in here.
      final inPtrs = calloc<LiteRtTensorBuffer>(inHandles.length);
      final outPtrs = calloc<LiteRtTensorBuffer>(outHandles.length);
      try {
        for (var i = 0; i < inHandles.length; i++) {
          inPtrs[i] = inHandles[i].buffer;
        }
        for (var i = 0; i < outHandles.length; i++) {
          outPtrs[i] = outHandles[i].buffer;
        }
        _bindings
            .runCompiledModel(
              graph,
              0,
              inHandles.length,
              inPtrs,
              outHandles.length,
              outPtrs,
            )
            .check('LiteRtRunCompiledModel(tts)');
      } finally {
        calloc.free(inPtrs);
        calloc.free(outPtrs);
      }

      // Lock(Read) triggers the device->host sync on GPU/NPU; read each
      // output THROUGH the locked pointer into an owned Float32List copy
      // before unlocking/destroying the buffer — mirrors
      // `SttCore._encode`'s locked-pointer copy (stt_core.dart:322-351).
      final results = <Float32List>[];
      for (var i = 0; i < outHandles.length; i++) {
        final count = outputShapes[i].fold<int>(1, (a, b) => a * b);
        final lockedPtr = calloc<Pointer<Void>>();
        try {
          _bindings
              .lockTensorBuffer(
                outHandles[i].buffer,
                lockedPtr,
                kLiteRtTensorBufferLockModeRead,
              )
              .check('LiteRtLockTensorBuffer(tts out $i)');
          final locked = lockedPtr.value.cast<Float>();
          results.add(Float32List.fromList(locked.asTypedList(count)));
          _bindings
              .unlockTensorBuffer(outHandles[i].buffer)
              .check('LiteRtUnlockTensorBuffer(tts out $i)');
        } finally {
          calloc.free(lockedPtr);
        }
      }
      return results;
    } finally {
      for (final h in inHandles) {
        _bindings.destroyTensorBuffer(h.buffer);
        calloc.free(h.raw);
      }
      for (final h in outHandles) {
        _bindings.destroyTensorBuffer(h.buffer);
        calloc.free(h.raw);
      }
    }
  }

  _TensorHandle _createF32TensorBuffer(List<int> shape, Float32List? data) {
    final count = shape.fold<int>(1, (a, b) => a * b);
    final bytes = count * 4;
    final type = LiteRtRankedTensorTypeView.calloc()
      ..elementType = kLiteRtElementTypeFloat32
      ..rank = shape.length;
    for (var i = 0; i < shape.length; i++) {
      type.setDimension(i, shape[i]);
    }
    final alloc = allocAligned(bytes);
    if (data != null) {
      final view = alloc.aligned.cast<Float>().asTypedList(count);
      view.setAll(0, data);
    }
    final bufPtr = calloc<LiteRtTensorBuffer>();
    // On success alloc.raw is handed off to the caller inside the returned
    // _TensorHandle — _runGraph frees it once the tensor buffer is destroyed
    // (tts_core.dart:556-563). On ANY throw before the return it must be
    // freed here or it leaks native heap permanently (~bytes per failed
    // call) — mirrors SttCore._encode's `returning` flag (stt_core.dart:288).
    var returning = false;
    try {
      _bindings
          .createTensorBufferFromHostMemory(
            type.pointer,
            alloc.aligned.cast(),
            bytes,
            nullptr,
            bufPtr,
          )
          .check('CreateTensorBufferFromHostMemory(shape=$shape)');
      returning = true;
      return _TensorHandle(alloc.raw, bufPtr.value);
    } finally {
      calloc.free(bufPtr);
      type.free();
      if (!returning) calloc.free(alloc.raw);
    }
  }

  /// Destroys all 3 compiled graphs' handles + the shared environment.
  /// Mirrors `SttCore.dispose`, x3.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final graph in [_textEncoder, _decoder, _vocoder]) {
      _bindings.destroyCompiledModel(graph.compiledModel);
      _bindings.destroyOptions(graph.options);
      _bindings.destroyModel(graph.model);
    }
    _bindings.destroyEnvironment(_environment);
  }
}
