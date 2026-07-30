// Synchronous, isolate-agnostic native core for Matcha-TTS on-device
// synthesis.
//
// Owns the LiteRT C API handles (one environment + 4 compiled graphs:
// text-encoder, CFM decoder, HiFi-GAN vocoder, dp_g2p) for a `matchaCfm`
// pipeline. `synthesize()` runs the blocking forward passes + host-side ODE math
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
// `dp_g2p` graph IS loaded here (4th compiled graph) and exposed via
// `TtsCore.neuralG2p` — it's the neural OOV fallback used when a word is
// missing from the dictionary; the dictionary-only path stays the golden
// path via `TtsTextFrontend` (Task 2.2).
//
// Determinism: the Euler CFM decoder's initial noise is drawn from a FIXED
// seed ([ttsCfmSeed]) via Box-Muller ([nextGaussian]), so [TtsCore.synthesize]
// is byte-reproducible run-to-run — the Phase-3 golden depends on this. Do
// NOT change the seed or the Box-Muller formula without regenerating it.
//
// Leak-safety: buffer create/lock/read/unlock/destroy mirrors
// `litert_embedding_core.dart`'s forward-pass pattern; `load`'s partial-
// failure cleanup mirrors `SttCore.load`, generalized to 4 compiled graphs
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
import 'package:meta/meta.dart' show visibleForTesting;
// Public, native-only bindings library (not the package barrel) — see the
// equivalent comment in `stt_core.dart`/`litert_embedding_core.dart` for why
// this import (not the `if (dart.library.ffi)` barrel) is correct in a
// native-only file.
import 'package:flutter_gemma_litertlm/litert_bindings.dart';

import '../model/tts_model_profile.dart';
import '../tts/neural_g2p_decode.dart';
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
/// — generalized so [TtsCore.load] can call it 4 times (text-encoder,
/// decoder, vocoder, dp_g2p). On any failure partway through, frees whatever
/// handles it already created for THIS graph before rethrowing; the caller
/// is responsible for freeing any earlier, already-succeeded graphs + the
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
    required this._dpG2p,
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
    required this._g2pChar2idx,
    required this._g2pIdx2ph,
    required this._g2pCharRepeats,
    required this._g2pStart,
    required this._g2pEnd,
    required this._g2pMaxT,
    required this._g2pNPhonemes,
  });

  final LiteRtBindings _bindings;
  final LiteRtEnvironment _environment;
  final _LoadedGraph _textEncoder;
  final _LoadedGraph _decoder;
  final _LoadedGraph _vocoder;
  final _LoadedGraph _dpG2p;

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

  // Neural G2P (dp_g2p) vocab + framing params, read from `g2p_meta.json` at
  // load time so `neuralG2p` can stay synchronous (no file I/O per word).
  final Map<String, int> _g2pChar2idx;
  final Map<int, String> _g2pIdx2ph;
  final int _g2pCharRepeats;
  final int _g2pStart;
  final int _g2pEnd;
  final int _g2pMaxT;
  final int _g2pNPhonemes;

  bool _disposed = false;

  /// Loads `config.json` + `g2p_meta.json` and compiles the 4 Matcha graphs
  /// (text-encoder, decoder, vocoder, dp_g2p) for [backend]. Heavy — call
  /// once, from a background isolate. [artifactPaths] is filename ->
  /// on-disk-path for the model bundle (from `RuntimeConfig.artifactPaths`).
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
    // isolate dying. Mirrors `SttCore.load`, generalized to 4 graphs.
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

      final dpG2p = _loadGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, profile.g2pFile),
        accelerator,
      );
      loadedGraphs.add(dpG2p);

      final g2pMetaPath = _artifactPath(artifactPaths, profile.g2pMetaFile);
      final g2pMeta =
          jsonDecode(await File(g2pMetaPath).readAsString())
              as Map<String, dynamic>;
      final g2pChar2idx = (g2pMeta['char2idx'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );
      final g2pIdx2ph = (g2pMeta['idx2ph'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(int.parse(k), v as String),
      );
      final g2pCharRepeats = (g2pMeta['char_repeats'] as num).toInt();
      final g2pStart = (g2pMeta['start'] as num).toInt();
      final g2pEnd = (g2pMeta['end'] as num).toInt();
      final g2pMaxT = (g2pMeta['MAXT'] as num).toInt();
      final g2pNPhonemes = (g2pMeta['n_phonemes'] as num).toInt();

      gemmaLog('[TtsCore] loaded: backend=$backend, 4 graphs compiled');

      return TtsCore._(
        bindings: bindings,
        environment: environment,
        textEncoder: textEncoder,
        decoder: decoder,
        vocoder: vocoder,
        dpG2p: dpG2p,
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
        g2pChar2idx: g2pChar2idx,
        g2pIdx2ph: g2pIdx2ph,
        g2pCharRepeats: g2pCharRepeats,
        g2pStart: g2pStart,
        g2pEnd: g2pEnd,
        g2pMaxT: g2pMaxT,
        g2pNPhonemes: g2pNPhonemes,
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

  /// Runs [word] through the neural dp_g2p graph — the OOV fallback for
  /// words missing from the pronunciation dictionary — and returns its IPA
  /// phoneme string. Synchronous (no file I/O; `g2p_meta.json` was already
  /// parsed in [load]), so it's safe to call per-word from the frontend (the
  /// `NeuralG2pResolver` adapter is `core.neuralG2p`). Framing/decoding is
  /// [encodeG2pInput]/[decodeG2pOutput] (Task 6) — this method only runs the
  /// native forward pass and picks the per-position argmax over the
  /// `n_phonemes`-wide logits.
  String neuralG2p(String word) {
    if (_disposed) {
      throw StateError('TtsCore is disposed');
    }
    final x = encodeG2pInput(
      word,
      _g2pChar2idx,
      charRepeats: _g2pCharRepeats,
      start: _g2pStart,
      end: _g2pEnd,
      maxT: _g2pMaxT,
    );
    final logits = _runGraph(
      _dpG2p.compiledModel,
      [
        ([1, _g2pMaxT], x),
      ],
      [
        [1, _g2pMaxT, _g2pNPhonemes],
      ],
    )[0];
    final argmax = List<int>.generate(_g2pMaxT, (t) {
      var best = 0;
      var bestV = logits[t * _g2pNPhonemes];
      for (var p = 1; p < _g2pNPhonemes; p++) {
        final v = logits[t * _g2pNPhonemes + p];
        if (v > bestV) {
          bestV = v;
          best = p;
        }
      }
      return best;
    });
    return decodeG2pOutput(argmax, _g2pIdx2ph, end: _g2pEnd);
  }

  /// Runs the full Matcha forward pass for a prepared frontend [input]:
  /// text-encoder -> host duration + Glow-TTS length regulator -> partition
  /// into MAX_MEL-sized windows -> per-window N-step Euler CFM decoder ->
  /// mel denorm -> HiFi-GAN vocoder -> 16-bit PCM, concatenated across
  /// windows. Verbatim port of `matcha_synth.dart:518-635`'s math for the
  /// single-window case; every graph run goes through [_runGraph] instead of
  /// that script's raw-`dlopen` `runGraph`. Returns 16-bit little-endian
  /// mono PCM with NO WAV header — the example's `pcmToWav` adds a header in
  /// Phase 3.
  ///
  /// When the predicted duration fits one window (`rawYlen <= _maxMel`, the
  /// common case), this is byte-identical to the pre-chunking implementation
  /// — see [_decodeWindow]. When it doesn't, the phoneme run is split into
  /// contiguous windows (see [planMelWindows]) that are decoded + vocoded
  /// independently and concatenated with no inter-window silence, so
  /// arbitrarily long text no longer throws `predicted N mel frames >
  /// MAX_MEL`.
  ///
  /// [seed] seeds the CFM decoder's initial Gaussian noise (defaults to
  /// [ttsCfmSeed], the golden-reproducible value). The worker's clause
  /// chunker passes `ttsCfmSeed + i` per clause so a single-clause input —
  /// e.g. the `'Hello world.'` golden — still synthesizes with
  /// `seed == ttsCfmSeed`, byte-identical to before this parameter existed.
  /// Multi-window synthesis within a single [synthesize] call uses
  /// `seed + windowIndex` per window.
  Uint8List synthesize(MatchaFrontendInput input, {int seed = ttsCfmSeed}) {
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

    // real phoneme count = highest t with textMask!=0, +1 (mask zeroes
    // padding past the real slot run; w is 0 there too since
    // textMask[t]==0 zeroes the exp(logw) term).
    var realCount = 0;
    for (var t = 0; t < _maxText; t++) {
      if (input.textMask[t] != 0.0) realCount = t + 1;
    }

    final windows = planMelWindows(w, realCount, _maxMel);
    if (windows.isEmpty) {
      // No speech frames -> empty PCM. In practice the worker skips
      // realLen<=1 inputs before they reach here; kept safe regardless.
      return Uint8List(0);
    }
    if (windows.length == 1) {
      // Single window: byte-identical to the pre-chunking implementation
      // (see the equivalence note on [_decodeWindow]).
      final (s, e) = windows.first;
      return _decodeWindow(mu, w, s, e, seed);
    }
    // Multi-window: decode each window (distinct seed per window) and
    // concat PCM with NO inter-window silence — they are one continuous
    // utterance; the worker adds silence only BETWEEN clauses.
    final segs = <Uint8List>[];
    for (var i = 0; i < windows.length; i++) {
      final (s, e) = windows[i];
      segs.add(_decodeWindow(mu, w, s, e, seed + i));
    }
    final total = segs.fold<int>(0, (a, b) => a + b.length);
    final out = Uint8List(total);
    var off = 0;
    for (final seg in segs) {
      out.setRange(off, off + seg.length, seg);
      off += seg.length;
    }
    return out;
  }

  /// Decode ONE window: the contiguous phoneme range `[pStart, pEnd)` of
  /// [mu] (feat-major `[_nFeats*_maxText]`) whose per-phoneme durations are
  /// [w]. The window's summed duration MUST already be `<= _maxMel` (caller
  /// guarantees, via [planMelWindows]). Returns 16-bit LE mono PCM
  /// (`winFrames*_hop*2` bytes).
  ///
  /// Byte-identical to the pre-chunking `synthesize` tail when called with
  /// `pStart=0, pEnd=realPhonemeCount, seed=the original seed` (single
  /// window): `localCum` then equals the old global `cum` over the real
  /// phonemes (w is 0 past `realCount`, so `localCum.last == cum[realCount -
  /// 1] == cum[_maxText - 1]`), so `winFrames` equals the old `ylen`, `muY`
  /// (via `searchSortedRight` on the identical cumulative array) is
  /// identical, and the seed-fixed noise draw, Euler loop, mel denorm,
  /// vocoder call, and PCM quantization are all unchanged.
  Uint8List _decodeWindow(
    Float32List mu,
    Float64List w,
    int pStart,
    int pEnd,
    int seed,
  ) {
    // Local cumulative durations for this window's phonemes (relative to the
    // window start), so muY-expansion and winFrames are window-local. For the
    // single full window (pStart=0), localCum == the old global `cum`.
    final localCum = Float64List(pEnd - pStart);
    var running = 0.0;
    for (var p = pStart; p < pEnd; p++) {
      running += w[p];
      localCum[p - pStart] = running;
    }
    final rawWin = localCum.isEmpty ? 0.0 : localCum[localCum.length - 1];
    final winFrames = rawWin.clamp(1.0, _maxMel.toDouble()).toInt();

    // muY[_nFeats*_maxMel] + ymask[_maxMel] — gather mu at the phoneme each
    // window-local output frame maps to (searchSorted on the LOCAL cum, then
    // offset by pStart). Identical to today for the single-window case.
    final muY = Float32List(_nFeats * _maxMel);
    final ymask = Float32List(_maxMel);
    for (var t = 0; t < winFrames; t++) {
      var idx = pStart + searchSortedRight(localCum, t.toDouble());
      if (idx > _maxText - 1) idx = _maxText - 1;
      for (var f = 0; f < _nFeats; f++) {
        muY[f * _maxMel + t] = mu[f * _maxText + idx];
      }
      ymask[t] = 1.0;
    }

    // Euler CFM ODE — seed-fixed Gaussian noise (byte-reproducible).
    final rnd = math.Random(seed);
    final x = Float32List(_nFeats * _maxMel);
    for (var f = 0; f < _nFeats; f++) {
      for (var t = 0; t < winFrames; t++) {
        x[f * _maxMel + t] = nextGaussian(rnd);
      }
    }
    for (var k = 0; k < _nTimesteps; k++) {
      final tEmb = tSin(k / _nTimesteps);
      final decOut = _runGraph(
        _decoder.compiledModel,
        [
          ([1, _nFeats, _maxMel], x),
          ([1, _nFeats, _maxMel], muY),
          ([1, 160], tEmb),
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

    // mel denorm
    final mel = Float32List(_nFeats * _maxMel);
    for (var f = 0; f < _nFeats; f++) {
      for (var t = 0; t < winFrames; t++) {
        mel[f * _maxMel + t] = x[f * _maxMel + t] * _melStd + _melMean;
      }
    }

    // vocoder -> wav -> 16-bit LE PCM
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
    final numSamples = winFrames * _hop;
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

  /// Partition phoneme indices `[0, realCount)` into contiguous windows whose
  /// summed durations [w] each fit [maxMel]. Greedy: extend a window until
  /// the next phoneme would overflow, then start a new one. Returns window
  /// boundaries as `[start, end)` index pairs.
  ///
  /// Throws if a SINGLE phoneme's duration alone exceeds [maxMel] (one
  /// phoneme longer than the decoder window is genuinely unsynthesizable —
  /// fail loud).
  @visibleForTesting
  static List<(int, int)> planMelWindows(
    Float64List w,
    int realCount,
    int maxMel,
  ) {
    final windows = <(int, int)>[];
    var start = 0;
    var acc = 0.0;
    for (var p = 0; p < realCount; p++) {
      final d = w[p];
      if (d > maxMel) {
        throw StateError(
          'TtsCore: a single phoneme needs ${d.ceil()} mel frames > MAX_MEL '
          '$maxMel and cannot be split.',
        );
      }
      if (p > start && acc + d > maxMel) {
        windows.add((start, p));
        start = p;
        acc = 0.0;
      }
      acc += d;
    }
    if (start < realCount) windows.add((start, realCount));
    return windows;
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

  /// Destroys all 4 compiled graphs' handles + the shared environment.
  /// Mirrors `SttCore.dispose`, x4.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final graph in [_textEncoder, _decoder, _vocoder, _dpG2p]) {
      _bindings.destroyCompiledModel(graph.compiledModel);
      _bindings.destroyOptions(graph.options);
      _bindings.destroyModel(graph.model);
    }
    _bindings.destroyEnvironment(_environment);
  }
}
