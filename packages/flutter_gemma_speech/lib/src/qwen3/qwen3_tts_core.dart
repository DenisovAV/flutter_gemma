// Qwen3-TTS talker/MTP/codec graph loader + talker KV-cache prefill.
//
// `Qwen3TtsCore.load` opens the 3 LiteRT graphs that make up the Qwen3-TTS
// pipeline (`talker_int4.tflite`, `mtp_fp32.tflite`,
// `codec_decoder_fp32.tflite`), the host embedding tables + text-projection
// MLP (`Qwen3Tables`), and the Qwen2 byte-level BPE text encoder
// (`Qwen2BpeEncoder`); asserts the talker's graph layout against the frozen
// `TalkerLayout` constants; and introspects the MTP/codec graphs' fixed-size
// inputs (`mtpCacheLen`, `mtpKvShape`, `codecChunk`) so later tasks (the MTP
// inner loop, the codec sliding-window decode) don't need to re-open the
// graphs to read them. Ports the constructor of
// `Qwen3TtsPipeline.__init__` (`text_to_speech_lm/python/
// qwen3_tts_pipeline.py:130-171`).
//
// [Qwen3TtsCore.runPrefill] ports `Qwen3TtsPipeline._run_prefill`
// (`qwen3_tts_pipeline.py:315-328`): right-pads the (<=32-row) prompt
// embedding into the talker's fixed 32-row `prefill_32` signature, builds
// the matching causal `mask`, runs it against an all-zero initial KV cache
// (`qwen3_tts_pipeline.py:216-217`), and returns the 56 filled KV tensors —
// this initializes the KV cache the decode loop ([Qwen3TtsCore.runDecode])
// threads forward one step at a time.
//
// [Qwen3TtsCore.runDecode] ports `Qwen3TtsPipeline._run_decode`
// (`qwen3_tts_pipeline.py:330-340`): builds the one-row causal `mask`
// (`mask[...,:pos+1] = 0`, else `qwen3NegInf`) for the current KV-cache
// write position, runs the talker's `decode` signature against the
// threaded-forward KV cache, and splits the `[1,1,4096]` logits output into
// codebook-0 logits (`[:3072]`) and the hidden-state tail (`[3072:]`)
// consumed by the MTP graph (a later task). This is the correctness
// milestone for the whole talker path: prefill -> decode -> KV threading ->
// logit split -> cb0 scoring must reproduce the PyTorch reference's frame-0
// cb0 exactly (see `qwen3_talker_decode_test.dart`'s golden gate).
//
// FFI style + graph load/run machinery: same as `TtsCore`/`SttCore` — see
// `litert_graph.dart`'s file header for the create -> run -> lock(Read) ->
// copy-through-locked-ptr -> unlock -> destroy sequence this delegates to.
// [Qwen3TtsCore.runPrefill]/[Qwen3TtsCore.runDecode] are not truly public
// API (no v1 consumer outside this package calls them directly) but are
// deliberately not name-mangled private either, so `qwen3_prefill_test.dart`
// / `qwen3_talker_decode_test.dart` — different libraries — can drive them
// directly; annotated `@visibleForTesting` to say so, mirroring
// `TtsCore.planMelWindows`/`concatSegments`.

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:meta/meta.dart' show visibleForTesting;
// Public, native-only bindings library (not the package barrel) — see the
// equivalent comment in `tts_core.dart`/`stt_core.dart` for why this import
// (not the `if (dart.library.ffi)` barrel) is correct in a native-only file.
import 'package:flutter_gemma_litertlm/litert_bindings.dart';

import '../litert/litert_graph.dart';
import 'qwen2_bpe_encoder.dart';
import 'qwen3_tables.dart';
import 'qwen3_talker_layout.dart';

/// Mask fill value for "not yet attendable" KV-cache positions — matches
/// `qwen3_tts_pipeline.py`'s module-level `_NEG_INF = -1e9` (used by both
/// `_run_prefill` and `_run_decode`'s causal masks).
const double qwen3NegInf = -1e9;

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
    throw StateError(
      'Qwen3TtsCore: bundle is missing "$file" in artifactPaths',
    );
  }
  return path;
}

/// Reads one input tensor's full shape via the index-based
/// `getInputTensorLayout` accessor — the only per-tensor introspection the
/// bound LiteRT C API offers (see `TalkerLayout`'s file header for the same
/// caveat re: no name-based or bulk-input accessor).
List<int> _readInputShape(
  LiteRtBindings bindings,
  LiteRtCompiledModel graph,
  int signatureIndex,
  int inputIndex,
  String label,
) {
  final layout = LiteRtLayoutView.calloc();
  try {
    bindings
        .getInputTensorLayout(graph, signatureIndex, inputIndex, layout.pointer)
        .check(
          'LiteRtGetCompiledModelInputTensorLayout($label, '
          'sig=$signatureIndex, in=$inputIndex)',
        );
    return [for (var i = 0; i < layout.rank; i++) layout.dimension(i)];
  } finally {
    layout.free();
  }
}

/// Synchronous native core for the Qwen3-TTS talker/MTP/codec pipeline. NOT
/// safe to share across isolates — the FFI handles it holds are owned by the
/// isolate that called [load]. Mirrors `TtsCore`/`SttCore`'s shape.
class Qwen3TtsCore {
  Qwen3TtsCore._({
    required this._bindings,
    required this._environment,
    required this._talker,
    required this._mtp,
    required this._codec,
    required this._tables,
    required this._encoder,
    required this._kvShapes,
    required this.mtpCacheLen,
    required this.mtpKvShape,
    required this.codecChunk,
  });

  final LiteRtBindings _bindings;
  final LiteRtEnvironment _environment;
  final LoadedGraph _talker;
  final LoadedGraph _mtp;
  final LoadedGraph _codec;

  /// Host embedding tables + text-projection MLP — used by the decode loop
  /// (Task 2.3+) to turn codec-token / MTP-residual / text-token ids into
  /// 1024-d talker-space embeddings. Not read by this task's [runPrefill]
  /// (the caller supplies already-embedded prompt rows, e.g. via
  /// `Qwen3Prompt.build`), but loaded here so a single [Qwen3TtsCore] owns
  /// every table the full pipeline needs.
  final Qwen3Tables _tables;

  /// Qwen2 byte-level BPE text encoder — used by the decode loop / a future
  /// frontend to turn raw text into token ids ahead of `Qwen3Prompt.build`.
  /// Same "loaded here, consumed later" rationale as [_tables].
  // ignore: unused_field
  final Qwen2BpeEncoder _encoder;

  /// Each of the talker's 56 KV tensor shapes (`kv_cache_{k,v}_{0..27}`,
  /// positional), read once at load time from the `decode` signature's
  /// inputs 3..58 — identical across all 3 talker signatures (see
  /// `TalkerLayout`'s file header).
  final List<List<int>> _kvShapes;

  /// MTP graph's KV-cache capacity — the last dim of its `args_2` (mask)
  /// input. Expected 17 (16 MTP steps + 1), per the C1 spike.
  final int mtpCacheLen;

  /// MTP graph's `args_3` (k-cache) input shape, read once at load time.
  final List<int> mtpKvShape;

  /// Codec-decoder graph's `args_0` input's last dim — its fixed
  /// frame-chunk width.
  final int codecChunk;

  bool _disposed = false;

  /// Output sample rate (Hz) — fixed for this model family.
  int get sampleRate => 24000;

  /// Opens `LiteRtBindings`, compiles the talker/MTP/codec graphs (see this
  /// file's header), asserts the talker's layout against the frozen
  /// [TalkerLayout] constants, reads the talker's 56 KV tensor shapes,
  /// introspects [mtpCacheLen]/[mtpKvShape]/[codecChunk], and loads the host
  /// tables + text encoder. Heavy — call once, from a background isolate.
  /// [artifactPaths] is filename -> on-disk-path for the model bundle
  /// (talker_int4.tflite, mtp_fp32.tflite, codec_decoder_fp32.tflite,
  /// tokenizer.json, and the 4 `Qwen3Tables` members).
  ///
  /// [talkerFileName] selects which talker artifact to load — defaults to
  /// the int4 runtime name (`talker_int4.tflite`) so every existing caller
  /// is unaffected. The golden cb0 test
  /// (`qwen3_talker_decode_test.dart`) passes `'talker_fp32.tflite'`
  /// instead: the fixtures in `test/golden/qwen3/` were generated by
  /// `gen_qwen3_goldens.py` against the fp32 talker
  /// (`Qwen3TtsPipeline(..., talker_file='talker_fp32.tflite')`) — int4 is
  /// NOT bit-exact vs the PyTorch reference, so only fp32 can reproduce the
  /// golden frame-0 cb0.
  static Future<Qwen3TtsCore> load({
    required Map<String, String> artifactPaths,
    PreferredBackend? backend,
    String talkerFileName = 'talker_int4.tflite',
  }) async {
    final bindings = LiteRtBindings.open();
    final accelerator = _acceleratorFor(backend);

    // Track handles as they're created so a failure partway through (e.g.
    // the codec graph fails to compile after the talker/MTP already
    // loaded) frees everything already allocated instead of leaking it —
    // the LiteRT native heap is process-global and is NOT reclaimed by the
    // isolate dying. Mirrors `TtsCore.load`, generalized to 3 graphs + the
    // tables' open file handle.
    LiteRtEnvironment? environment;
    final loadedGraphs = <LoadedGraph>[];
    Qwen3Tables? tables;
    try {
      final envPtr = calloc<LiteRtEnvironment>();
      bindings
          .createEnvironment(0, nullptr, envPtr)
          .check('LiteRtCreateEnvironment');
      environment = envPtr.value;
      calloc.free(envPtr);

      final talker = loadLiteRtGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, talkerFileName),
        accelerator,
      );
      loadedGraphs.add(talker);

      final mtp = loadLiteRtGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, 'mtp_fp32.tflite'),
        accelerator,
      );
      loadedGraphs.add(mtp);

      final codec = loadLiteRtGraph(
        bindings,
        environment,
        _artifactPath(artifactPaths, 'codec_decoder_fp32.tflite'),
        accelerator,
      );
      loadedGraphs.add(codec);

      // Fails loud at load time if a future model revision has drifted from
      // the C1-spike-frozen talker layout (see `TalkerLayout`'s file
      // header) — do this before trusting any KV-shape introspection below.
      TalkerLayout.assertLayout(bindings, talker.compiledModel);

      // KV tensor shapes are identical across all 3 talker signatures (per
      // TalkerLayout's file header) — read once from `decode`, inputs
      // 3..58 (`kv_cache_{k,v}_{0..27}`, positional).
      final kvShapes = [
        for (var i = 0; i < TalkerLayout.numKvTensors; i++)
          _readInputShape(
            bindings,
            talker.compiledModel,
            TalkerLayout.decodeSig,
            3 + i,
            'talker.kv_cache[$i]',
          ),
      ];

      // MTP/codec are each single-signature graphs (signature index 0);
      // their inputs are positional `args_N` == input index N (recipe
      // `:162-171`).
      final mtpMaskShape = _readInputShape(
        bindings,
        mtp.compiledModel,
        0,
        2,
        'mtp.args_2 (mask)',
      );
      final mtpCacheLen = mtpMaskShape.last;
      final mtpKvShape = _readInputShape(
        bindings,
        mtp.compiledModel,
        0,
        3,
        'mtp.args_3 (k-cache)',
      );
      final codecInShape = _readInputShape(
        bindings,
        codec.compiledModel,
        0,
        0,
        'codec.args_0',
      );
      final codecChunk = codecInShape.last;

      tables = await Qwen3Tables.load(
        codecEmbPath: _artifactPath(artifactPaths, 'codec_embedding_fp32.npy'),
        mtpEmbPath: _artifactPath(artifactPaths, 'mtp_embeddings_fp16.npy'),
        textEmbPath: _artifactPath(artifactPaths, 'text_embedding_fp16.npy'),
        projectionNpzPath: _artifactPath(
          artifactPaths,
          'text_projection_fp32.npz',
        ),
      );

      final encoder = await Qwen2BpeEncoder.fromTokenizerJson(
        _artifactPath(artifactPaths, 'tokenizer.json'),
      );

      gemmaLog(
        '[Qwen3TtsCore] loaded: backend=$backend, 3 graphs compiled, '
        'mtpCacheLen=$mtpCacheLen, mtpKvShape=$mtpKvShape, '
        'codecChunk=$codecChunk',
      );

      return Qwen3TtsCore._(
        bindings: bindings,
        environment: environment,
        talker: talker,
        mtp: mtp,
        codec: codec,
        tables: tables,
        encoder: encoder,
        kvShapes: kvShapes,
        mtpCacheLen: mtpCacheLen,
        mtpKvShape: mtpKvShape,
        codecChunk: codecChunk,
      );
    } catch (_) {
      tables?.dispose();
      for (final graph in loadedGraphs) {
        bindings.destroyCompiledModel(graph.compiledModel);
        bindings.destroyOptions(graph.options);
        bindings.destroyModel(graph.model);
      }
      if (environment != null) bindings.destroyEnvironment(environment);
      rethrow;
    }
  }

  /// All-zero initial KV cache — 56 tensors sized to [_kvShapes]. Port of
  /// `qwen3_tts_pipeline.py:216-217`'s
  /// `kv = {n: np.zeros(shape, np.float32) for n in kv_names}`.
  List<Float32List> _zeroKv() => [
    for (final shape in _kvShapes)
      Float32List(shape.fold<int>(1, (a, b) => a * b)),
  ];

  /// Prefills the talker's KV cache from the (<=32-row) prompt embedding
  /// [prefillEmb] (flat `[promptLen * 1024]`, row-major — e.g.
  /// `Qwen3Prompt.build`'s `prefill`). Port of
  /// `Qwen3TtsPipeline._run_prefill` (`qwen3_tts_pipeline.py:315-328`):
  /// right-pads into the fixed 32-row `prefill_32` signature, builds the
  /// matching causal `mask`, runs against an all-zero initial KV cache
  /// ([_zeroKv]), and returns the 56 filled KV tensors — the new KV state a
  /// caller threads into the first decode step (`runDecode`, Task 2.3).
  ///
  /// Not true public API (no v1 consumer outside this package calls it
  /// directly) — exposed (not underscore-private) so
  /// `qwen3_prefill_test.dart` can drive it, and annotated
  /// [visibleForTesting] to say so, mirroring `TtsCore.planMelWindows`.
  @visibleForTesting
  List<Float32List> runPrefill(Float32List prefillEmb, int promptLen) {
    if (_disposed) {
      throw StateError('Qwen3TtsCore is disposed');
    }
    if (promptLen < 0 || promptLen > 32) {
      throw ArgumentError.value(
        promptLen,
        'promptLen',
        "Qwen3TtsCore.runPrefill: prompt too long for the talker's "
            'prefill_32 signature (must be 0..32)',
      );
    }
    if (prefillEmb.length != promptLen * TalkerLayout.embeddingDim) {
      throw ArgumentError.value(
        prefillEmb.length,
        'prefillEmb.length',
        'Qwen3TtsCore.runPrefill: expected '
            '${promptLen * TalkerLayout.embeddingDim} '
            '(promptLen * ${TalkerLayout.embeddingDim})',
      );
    }

    // buf[1,32,1024]: right-padded prompt (qwen3_tts_pipeline.py:320-321).
    final buf = Float32List(32 * TalkerLayout.embeddingDim);
    buf.setRange(0, prefillEmb.length, prefillEmb);

    // input_pos = arange(32) (qwen3_tts_pipeline.py:326).
    final inputPos = Int32List.fromList([for (var i = 0; i < 32; i++) i]);

    // mask[1,1,32,cacheLen]: causal, `mask[0,0,i,:min(i,p-1)+1] = 0.0` else
    // qwen3NegInf (qwen3_tts_pipeline.py:322-324). Flattened row-major —
    // row i occupies mask[i*cacheLen .. (i+1)*cacheLen).
    final cacheLen = TalkerLayout.cacheLen;
    final mask = Float32List(32 * cacheLen);
    for (var i = 0; i < 32; i++) {
      final lastValid = math.min(i, promptLen - 1);
      final rowBase = i * cacheLen;
      for (var j = 0; j <= lastValid; j++) {
        mask[rowBase + j] = 0.0;
      }
      for (var j = lastValid + 1; j < cacheLen; j++) {
        mask[rowBase + j] = qwen3NegInf;
      }
    }

    final kv = _zeroKv();
    final inputs = <GraphInput>[
      F32Input([1, 32, TalkerLayout.embeddingDim], buf),
      I32Input([32], inputPos),
      F32Input([1, 1, 32, cacheLen], mask),
      for (var i = 0; i < TalkerLayout.numKvTensors; i++)
        F32Input(_kvShapes[i], kv[i]),
    ];

    return runLiteRtGraph(
      _bindings,
      _talker.compiledModel,
      TalkerLayout.prefill32Sig,
      inputs,
      _kvShapes,
    );
  }

  /// Runs one autoregressive talker decode step, threading [kv] (the 56
  /// tensors from the previous [runPrefill]/[runDecode] call) forward one
  /// position. Port of `Qwen3TtsPipeline._run_decode`
  /// (`qwen3_tts_pipeline.py:330-340`).
  ///
  /// [embed] (`[1024]`) is the current step's input embedding — for the
  /// very first decode step this is the last prefill row
  /// (`prefill[0, -1]`, recipe `:219-220`); for later steps (Task 4.2's
  /// loop) it's the assembled next-frame embedding. [pos] is the KV-cache
  /// write position (0-indexed, matching `input_pos` passed to the graph).
  ///
  /// Builds the one-row causal `mask` (`[1,1,1,cacheLen]`,
  /// `mask[...,:pos+1] = 0.0` else [qwen3NegInf]), runs the talker's
  /// `decode` signature, and splits the `[1,1,4096]` `logits` output per
  /// `TalkerLayout`'s frozen layout (file header): `[:3072]` is the
  /// codebook-0 logits the caller scores/picks from ([cb0Logits]), `[3072:]`
  /// is the hidden-state tail the MTP graph consumes ([hidden]). Returns the
  /// 56 updated KV tensors ([newKv]) — the same order as [kv] (KV output
  /// order == KV input order, per `TalkerLayout`) — to thread into the next
  /// call.
  ///
  /// Not true public API (see this file's header) — [visibleForTesting] so
  /// `qwen3_talker_decode_test.dart` can drive it directly, and structured
  /// (single call, explicit `kv`/`pos` in, updated `kv` out) so a later
  /// task's per-frame decode loop can call it repeatedly without needing any
  /// internal state this class doesn't already expose.
  @visibleForTesting
  (Float32List cb0Logits, Float32List hidden, List<Float32List> newKv)
  runDecode(List<Float32List> kv, Float32List embed, int pos) {
    if (_disposed) {
      throw StateError('Qwen3TtsCore is disposed');
    }
    if (kv.length != TalkerLayout.numKvTensors) {
      throw ArgumentError.value(
        kv.length,
        'kv.length',
        'Qwen3TtsCore.runDecode: expected ${TalkerLayout.numKvTensors} KV '
            'tensors',
      );
    }
    if (embed.length != TalkerLayout.embeddingDim) {
      throw ArgumentError.value(
        embed.length,
        'embed.length',
        'Qwen3TtsCore.runDecode: expected ${TalkerLayout.embeddingDim} '
            '(embeddingDim)',
      );
    }
    final cacheLen = TalkerLayout.cacheLen;
    if (pos < 0 || pos >= cacheLen) {
      throw ArgumentError.value(
        pos,
        'pos',
        'Qwen3TtsCore.runDecode: pos must be in [0, $cacheLen)',
      );
    }

    // mask[1,1,1,cacheLen]: mask[...,:pos+1] = 0.0 else qwen3NegInf.
    // qwen3_tts_pipeline.py:330-340 (the decode-step causal mask — every
    // KV-cache slot up to and including `pos` is attendable, everything
    // after is not-yet-written).
    final mask = Float32List(cacheLen);
    for (var j = 0; j <= pos; j++) {
      mask[j] = 0.0;
    }
    for (var j = pos + 1; j < cacheLen; j++) {
      mask[j] = qwen3NegInf;
    }

    final inputs = <GraphInput>[
      F32Input([1, 1, TalkerLayout.embeddingDim], embed),
      I32Input([1], Int32List.fromList([pos])),
      F32Input([1, 1, 1, cacheLen], mask),
      for (var i = 0; i < TalkerLayout.numKvTensors; i++)
        F32Input(_kvShapes[i], kv[i]),
    ];

    // decode's outputs are the 56 KV tensors (same order as the KV inputs)
    // followed by `logits [1,1,4096]` — see `TalkerLayout`'s file header.
    final outputShapes = <List<int>>[
      ..._kvShapes,
      [1, 1, TalkerLayout.logitsWidth],
    ];

    final outputs = runLiteRtGraph(
      _bindings,
      _talker.compiledModel,
      TalkerLayout.decodeSig,
      inputs,
      outputShapes,
    );

    final newKv = outputs.sublist(0, TalkerLayout.numKvTensors);
    final logits = outputs[TalkerLayout.numKvTensors];
    final cb0Logits = logits.sublist(0, TalkerLayout.logitsCodec);
    final hidden = logits.sublist(
      TalkerLayout.logitsCodec,
      TalkerLayout.logitsWidth,
    );

    return (cb0Logits, hidden, newKv);
  }

  /// Destroys the 3 compiled graphs' handles + the shared environment, and
  /// closes [_tables]' open `text_embedding` file handle. Mirrors
  /// `TtsCore.dispose`.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final graph in [_talker, _mtp, _codec]) {
      _bindings.destroyCompiledModel(graph.compiledModel);
      _bindings.destroyOptions(graph.options);
      _bindings.destroyModel(graph.model);
    }
    _bindings.destroyEnvironment(_environment);
    _tables.dispose();
  }
}
