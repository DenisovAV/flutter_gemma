// Inflect-Nano-v2 TTS synthesis core — a VITS-style pipeline over two LiteRT
// graphs, run through the shared FFI helpers in `litert_graph.dart` (the same
// create -> run -> lock(Read) -> copy -> unlock -> destroy path `TtsCore` uses).
//
// Pipeline (a verbatim port of the reference `bench.py`/`say.py` from
// huggingface.co/sasha-denisov/inflect-nano-v2-litert):
//   1. text-encoder: tokens[1,N] (phoneme-symbol ids) -> three outputs, in the
//      model's declared order: m_p[1,N,128], logs_p[1,N,128], logw[1,N,1].
//   2. host-side length regulator: durations = ceil(exp(logw)); repeat encoder
//      frame t of m_p/logs_p durations[t] times -> [1,T,128] each (T = sum).
//   3. z_p = m_p_exp + noise * exp(logs_p_exp) * NOISE_SCALE.
//   4. decoder: z_p[1,T,128] -> waveform[1, T*HOP] (24 kHz, no separate
//      vocoder — the decoder emits samples directly).
//   5. float32 [-1,1] -> 16-bit little-endian PCM.
//
// Determinism / verification: VITS is stochastic — the `noise` term is a random
// realization, so any fixed seed produces valid speech (a DIFFERENT noise
// instance changes the waveform's fine structure completely: sample-correlation
// against a reference generated with a different RNG is ~0, not ~1). The product
// path uses a fixed-seed Box-Muller Gaussian ([_defaultSeed]) so a given text is
// byte-reproducible run-to-run. To verify the FFI graphs + host math byte-exact
// against a reference WITHOUT reimplementing numpy's Mersenne-Twister, pass the
// reference's exported noise via [synthesize]'s `noiseOverride` — that removes
// the RNG as a variable and makes the whole chain reproducible.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma_litertlm/litert_bindings.dart';

import '../model/tts_model_profile.dart';
import '../tts/neural_g2p_decode.dart';
import '../tts/tts_text_frontend.dart' show NeuralG2pResolver;
import 'litert_graph.dart';

/// Inflect output sample rate (Hz).
const int inflectSampleRate = 24000;

/// Waveform samples the decoder emits per z_p frame (upsampling factor).
const int _hop = 256;

/// Upper bound on a single phoneme's duration (frames) — a guard against
/// degenerate model output driving `tFrames` into an OOM allocation. At
/// 24 kHz / hop 256 (~94 frames/s) this is ~11 s for one phoneme: far beyond
/// anything legitimate, so it only ever clamps garbage.
const int _maxFramesPerPhoneme = 1024;

/// VITS prior noise scale (`--variation` default in `say.py`).
const double _noiseScale = 0.667;

/// Fixed default RNG seed for the product path (byte-reproducible per text).
const int _defaultSeed = 7;

int _acceleratorFor(PreferredBackend? backend) => switch (backend) {
  PreferredBackend.gpu => kLiteRtHwAcceleratorGpu,
  PreferredBackend.npu => kLiteRtHwAcceleratorNpu,
  _ => kLiteRtHwAcceleratorCpu,
};

String _artifactPath(Map<String, String> paths, String file) {
  final p = paths[file];
  if (p == null) {
    throw StateError('InflectTtsCore: bundle is missing "$file" in paths');
  }
  return p;
}

/// One standard-normal draw via Box-Muller (mirrors `tts_core.dart`'s
/// `nextGaussian`), kept local so this core has no dependency on the Matcha
/// pipeline file.
double _nextGaussian(math.Random r) {
  final u1 = 1.0 - r.nextDouble();
  final u2 = 1.0 - r.nextDouble();
  return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
}

/// The neural OOV G2P (dp_g2p graph + its `g2p_meta.json` framing/vocab),
/// loaded only when the bundle carries it. Shared verbatim with Matcha's
/// `dp_g2p` — same graph, same meta.
class _InflectG2p {
  _InflectG2p(
    this.graph,
    this.char2idx,
    this.idx2ph,
    this.charRepeats,
    this.start,
    this.end,
    this.maxT,
    this.nPhonemes,
  );
  final LoadedGraph graph;
  final Map<String, int> char2idx;
  final Map<int, String> idx2ph;
  final int charRepeats;
  final int start;
  final int end;
  final int maxT;
  final int nPhonemes;
}

/// Synchronous native Inflect TTS core. NOT safe to share across isolates — the
/// FFI handles are process-global; create + use + [dispose] on one isolate.
class InflectTtsCore {
  InflectTtsCore._({
    required LiteRtBindings bindings,
    required LiteRtEnvironment environment,
    required LoadedGraph textEncoder,
    required LoadedGraph decoder,
    _InflectG2p? g2p,
  }) : _bindings = bindings, // ignore: prefer_initializing_formals
       _environment = environment, // ignore: prefer_initializing_formals
       _textEncoder = textEncoder, // ignore: prefer_initializing_formals
       _decoder = decoder, // ignore: prefer_initializing_formals
       _g2p = g2p; // ignore: prefer_initializing_formals

  final LiteRtBindings _bindings;
  final LiteRtEnvironment _environment;
  final LoadedGraph _textEncoder;
  final LoadedGraph _decoder;
  final _InflectG2p? _g2p;

  /// Neural OOV G2P resolver (dp_g2p), or null if the bundle didn't include it
  /// — pass to `InflectTextFrontend` so out-of-dictionary words resolve instead
  /// of throwing. Mirrors `TtsCore.neuralG2p`.
  NeuralG2pResolver? get neuralG2p {
    final g = _g2p;
    if (g == null) return null;
    return (word) {
      final x = encodeG2pInput(
        word,
        g.char2idx,
        charRepeats: g.charRepeats,
        start: g.start,
        end: g.end,
        maxT: g.maxT,
      );
      final logits = runLiteRtGraph(
        _bindings,
        g.graph.compiledModel,
        0,
        [
          F32Input([1, g.maxT], x),
        ],
        [
          [1, g.maxT, g.nPhonemes],
        ],
      )[0];
      final argmax = List<int>.generate(g.maxT, (t) {
        var best = 0;
        var bestV = logits[t * g.nPhonemes];
        for (var p = 1; p < g.nPhonemes; p++) {
          final v = logits[t * g.nPhonemes + p];
          if (v > bestV) {
            bestV = v;
            best = p;
          }
        }
        return best;
      });
      return decodeG2pOutput(argmax, g.idx2ph, end: g.end);
    };
  }

  /// Output sample rate.
  int get sampleRate => inflectSampleRate;

  /// Compiles the two Inflect graphs (text-encoder + decoder) for [backend].
  /// Heavy — call once, from a background isolate. [artifactPaths] is
  /// filename -> on-disk path for the bundle (from `RuntimeConfig`).
  static Future<InflectTtsCore> load({
    required TtsModelProfile profile,
    required Map<String, String> artifactPaths,
    PreferredBackend? backend,
  }) async {
    if (profile.pipeline != TtsPipelineKind.inflectVits) {
      throw UnimplementedError(
        'InflectTtsCore: only TtsPipelineKind.inflectVits is implemented here',
      );
    }
    final bindings = LiteRtBindings.open();
    final accelerator = _acceleratorFor(backend);

    // Track handles as they're created so a partial failure frees everything
    // already allocated (the LiteRT native heap is process-global). Mirrors
    // `TtsCore.load`.
    LiteRtEnvironment? environment;
    final loaded = <LoadedGraph>[];
    try {
      final envPtr = calloc<LiteRtEnvironment>();
      bindings
          .createEnvironment(0, nullptr, envPtr)
          .check('LiteRtCreateEnvironment');
      environment = envPtr.value;
      calloc.free(envPtr);

      final textEncoder = loadLiteRtGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, profile.textEncoderFile),
        accelerator,
      );
      loaded.add(textEncoder);

      final decoder = loadLiteRtGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, profile.decoderFile),
        accelerator,
      );
      loaded.add(decoder);

      // Optional neural OOV G2P — only when the bundle carries dp_g2p + its
      // meta (Matcha's shared G2P). Absent (e.g. the enc+dec-only verification
      // harness) → neuralG2p is null and the frontend needs dictionary-covered
      // input.
      _InflectG2p? g2p;
      if (profile.g2pFile.isNotEmpty &&
          artifactPaths.containsKey(profile.g2pFile) &&
          artifactPaths.containsKey(profile.g2pMetaFile)) {
        final dpG2p = loadLiteRtGraph(
          bindings,
          environment,
          _artifactPath(artifactPaths, profile.g2pFile),
          accelerator,
        );
        loaded.add(dpG2p);
        final meta =
            jsonDecode(
                  await File(
                    _artifactPath(artifactPaths, profile.g2pMetaFile),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        g2p = _InflectG2p(
          dpG2p,
          (meta['char2idx'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ),
          (meta['idx2ph'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(int.parse(k), v as String),
          ),
          (meta['char_repeats'] as num).toInt(),
          (meta['start'] as num).toInt(),
          (meta['end'] as num).toInt(),
          (meta['MAXT'] as num).toInt(),
          (meta['n_phonemes'] as num).toInt(),
        );
      }

      gemmaLog(
        '[InflectTtsCore] loaded: backend=$backend, ${loaded.length} graphs '
        'compiled (neuralG2p=${g2p != null})',
      );
      return InflectTtsCore._(
        bindings: bindings,
        environment: environment,
        textEncoder: textEncoder,
        decoder: decoder,
        g2p: g2p,
      );
    } catch (_) {
      for (final g in loaded) {
        bindings.destroyCompiledModel(g.compiledModel);
        bindings.destroyOptions(g.options);
        bindings.destroyModel(g.model);
      }
      if (environment != null) bindings.destroyEnvironment(environment);
      rethrow;
    }
  }

  /// Synthesize [phonemeIds] (VITS/Tacotron symbol ids) to 16-bit LE PCM at
  /// [inflectSampleRate]. [noiseOverride] (length `T*128`, row-major
  /// frame-major) replaces the internal Gaussian — used by verification to
  /// inject the reference RNG stream; production omits it and draws from a
  /// fixed [seed].
  Uint8List synthesize(
    List<int> phonemeIds, {
    int seed = _defaultSeed,
    Float32List? noiseOverride,
  }) {
    final n = phonemeIds.length;
    if (n == 0) return Uint8List(0);
    final ids = Int32List.fromList(phonemeIds);

    // 1. Text encoder — outputs in declared order: m_p, logs_p, logw.
    final enc = runLiteRtGraph(
      _bindings,
      _textEncoder.compiledModel,
      0,
      [
        I32Input([1, n], ids),
      ],
      [
        [1, n, 128],
        [1, n, 128],
        [1, n, 1],
      ],
    );
    final mP = enc[0]; // [N*128]
    final logsP = enc[1]; // [N*128]
    final logw = enc[2]; // [N]

    // 2. Durations + length regulator (repeat each encoder frame).
    // Defensive vs garbage model output (e.g. #214 GPU output-garbage): a
    // non-finite logw would make exp().ceil() THROW ('Infinity or NaN toInt'),
    // and a large-but-finite logw would explode tFrames into an OOM Float32List
    // (Matcha survives both via .ceilToDouble() + its MAX_MEL chunk cap; this
    // pipeline has no chunk cap). Clamp each frame to [1, _maxFramesPerPhoneme]
    // so a degenerate frame degrades that phoneme instead of crashing the turn.
    var clamped = false;
    final durations = List<int>.generate(n, (t) {
      final e = math.exp(logw[t]);
      if (!e.isFinite || e > _maxFramesPerPhoneme) {
        clamped = true;
        return e.isFinite ? _maxFramesPerPhoneme : 1;
      }
      return e.ceil();
    });
    if (clamped) {
      gemmaLog(
        '[InflectTtsCore] clamped a non-finite/oversized duration frame — '
        'model output looks degenerate; audio may be distorted for that span.',
      );
    }
    var tFrames = 0;
    for (final d in durations) {
      tFrames += d;
    }
    if (tFrames == 0) return Uint8List(0);

    final total = tFrames * 128;
    final mExp = Float32List(total);
    final lsExp = Float32List(total);
    var f = 0;
    for (var t = 0; t < n; t++) {
      final base = t * 128;
      for (var r = 0; r < durations[t]; r++) {
        final off = f * 128;
        for (var c = 0; c < 128; c++) {
          mExp[off + c] = mP[base + c];
          lsExp[off + c] = logsP[base + c];
        }
        f++;
      }
    }

    // 3. z_p = m_p_exp + noise * exp(logs_p_exp) * NOISE_SCALE.
    final zp = Float32List(total);
    if (noiseOverride != null) {
      if (noiseOverride.length != total) {
        throw ArgumentError(
          'noiseOverride length ${noiseOverride.length} != expected $total',
        );
      }
      for (var i = 0; i < total; i++) {
        zp[i] = mExp[i] + noiseOverride[i] * math.exp(lsExp[i]) * _noiseScale;
      }
    } else {
      final rnd = math.Random(seed);
      for (var i = 0; i < total; i++) {
        zp[i] = mExp[i] + _nextGaussian(rnd) * math.exp(lsExp[i]) * _noiseScale;
      }
    }

    // 4. Decoder: z_p[1,T,128] -> waveform[1, T*HOP].
    final samples = tFrames * _hop;
    final dec = runLiteRtGraph(
      _bindings,
      _decoder.compiledModel,
      0,
      [
        F32Input([1, tFrames, 128], zp),
      ],
      [
        [1, samples],
      ],
    );
    final wav = dec[0];

    // 5. float32 [-1,1] -> 16-bit little-endian PCM.
    final pcm = Uint8List(wav.length * 2);
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i < wav.length; i++) {
      var s = wav[i];
      // NaN passes BOTH comparisons (all NaN comparisons are false), so it
      // would reach .round() and throw 'Infinity or NaN toInt'. Map a
      // non-finite sample to silence instead of crashing the whole utterance.
      if (s.isNaN) {
        s = 0.0;
      } else if (s > 1.0) {
        s = 1.0;
      } else if (s < -1.0) {
        s = -1.0;
      }
      bd.setInt16(i * 2, (s * 32767).round(), Endian.little);
    }
    return pcm;
  }

  /// Destroys the compiled graphs' handles + the shared environment.
  void dispose() {
    final g2p = _g2p;
    for (final g in [_textEncoder, _decoder, if (g2p != null) g2p.graph]) {
      _bindings.destroyCompiledModel(g.compiledModel);
      _bindings.destroyOptions(g.options);
      _bindings.destroyModel(g.model);
    }
    _bindings.destroyEnvironment(_environment);
  }
}
