// ORT-GenAI text generation over `dart:ffi`, driven from a long-lived worker
// isolate — the productionized form of the throughput spike at
// `scratchpad/ort_genai_spike/bin/main.dart` (hardened plan Phase 3, Task 1).
//
// Why a long-lived worker and not `Isolate.run` per call (mirrors
// `EmbeddingWorker`'s doc, `flutter_gemma_embeddings/lib/src/embedding_worker.dart`):
//   - Model + tokenizer load costs hundreds of ms and must happen once.
//   - FFI `Pointer`/`DynamicLibrary` cannot cross isolate boundaries — every
//     native handle (model, tokenizer, generator) is created and used
//     entirely inside the worker; only sendable values (strings, ints,
//     bools, plain data classes) cross the port. This resolves D4 by
//     construction: no FFI handle ever crosses an isolate.
//   - ORT-GenAI has no native stream callback (unlike LiteRT-LM's
//     `stream_proxy`), so the decode loop is Dart-driven. Reloading the
//     model+tokenizer on every `Isolate.run` call (~hundreds of ms) would
//     dwarf the ~18ms/token decode cost this is trying to measure/serve.
//
// GOTCHA (verified in the spike, and load-bearing here): on this GenAI
// version the prompt forward pass (prefill) runs INSIDE
// `OgaGenerator_AppendTokenSequences`, not the first `GenerateNextToken`.
// Every timing/stop-flag decision below assumes that.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:mutex/mutex.dart';

import 'ort_genai_bindings.g.dart';

/// Env var override for host tests / macOS dev: a directory containing both
/// `libonnxruntime` and `libonnxruntime-genai` (platform-specific names) —
/// mirrors `ort_ffi_client.dart`'s `FLUTTER_GEMMA_ORT_LIBRARY` for the plain
/// ORT embedding arm. Production app builds never set this; `hook/build.dart`
/// (Task 4) resolves the CodeAsset bundle instead once it lands.
const genAiLibsDirEnvVar = 'FLUTTER_GEMMA_ORT_GENAI_LIBS';

/// One user turn to generate a response for. [GenAiFfiClient] applies the
/// model's own chat template (`OgaTokenizerApplyChatTemplate`) inside the
/// worker — callers (`OnnxSession`) pass raw content, never pre-formatted
/// turn markers (Task 3: onnx routes through the SDK-owns-templates path).
///
/// Must stay a plain sendable data class — it crosses the isolate port.
class GenAiTurn {
  const GenAiTurn({
    required this.userContent,
    this.systemInstruction,
    this.isFirstTurn = false,
    this.maxOutputTokens,
  });

  /// Raw user-turn content (tool responses are already folded into plain
  /// text by `Message._formatToolResponseContent` upstream, via the
  /// raw-mode `transformToChatPrompt`).
  final String userContent;

  /// System role content. Only sent (as a `system` message) on
  /// [isFirstTurn] — later turns rely on the persistent generator's KV
  /// cache to remember it, matching every other raw-mode engine's posture.
  final String? systemInstruction;

  /// True for the first turn of a session: destroys any live generator and
  /// creates a fresh one (fresh KV cache) instead of reusing it.
  final bool isFirstTurn;

  /// Cap on GENERATED tokens for this turn — distinct from the model's
  /// context-window `max_length`, which is set once when the generator is
  /// created (see [GenAiClient.load]'s `contextWindow`).
  final int? maxOutputTokens;
}

/// Prompt/decode counters for the most recently completed [GenAiClient.generate]
/// call — read via [GenAiClient.lastGenerationStats] for
/// [InferenceModelSession.getSessionMetrics].
class GenAiGenerationStats {
  const GenAiGenerationStats({
    required this.promptTokens,
    required this.generatedTokens,
    required this.decodeMs,
  });

  final int promptTokens;
  final int generatedTokens;

  /// Wall time of the decode loop only (excludes model load and prefill).
  final int decodeMs;

  double? get tokensPerSecond =>
      decodeMs > 0 ? generatedTokens * 1000.0 / decodeMs : null;
}

/// The `dart:ffi` seam for ORT-GenAI text generation. [GenAiFfiClient] is the
/// only implementation that touches native handles — see this file's doc for
/// why they live entirely inside a worker isolate. [OnnxSession] /
/// [OnnxInferenceModel] depend on this abstract type so unit tests can inject
/// a fake with zero dlopen (hardened plan Task 6).
abstract class GenAiClient {
  /// Loads the model + tokenizer from [modelDir] (an ORT-GenAI model
  /// directory: `genai_config.json` + `.onnx`(+`.onnx_data`) + tokenizer
  /// files). [contextWindow] sizes the persistent generator's `max_length` —
  /// the model's whole KV-cache budget (same number as
  /// `InferenceModel.maxTokens`), NOT the per-turn output cap (that's
  /// [GenAiTurn.maxOutputTokens]).
  Future<void> load(String modelDir, {int contextWindow = 1024});

  /// Streams decoded text for [turn]. Only one `generate()` call may be
  /// in-flight at a time — concrete clients serialize with a mutex; a second
  /// concurrent caller's stream doesn't start until the first completes.
  Stream<String> generate(GenAiTurn turn);

  /// Token count for [text] via the tokenizer's own encoder (no chat
  /// template applied) — used for [InferenceModelSession.sizeInTokens].
  Future<int> countTokens(String text);

  /// Stops the currently in-flight [generate] stream (no-op if none is
  /// active). Deliberately NOT covered by the `generate`/`countTokens`
  /// mutex — it must be able to interrupt a call that's holding it.
  Future<void> stopGeneration();

  /// Destroys the current generator so the NEXT [generate] call starts a
  /// fresh conversation (fresh KV cache) instead of continuing the live one.
  /// [OnnxSession.close] calls this so a superseded session never bleeds
  /// its history into whatever session is created next — the ORT-GenAI
  /// sibling of the `.litertlm` FFI engine's "close previous conversation
  /// before creating a new one" rule.
  Future<void> resetSession();

  /// Frees every native handle (generator, tokenizer, model) and kills the
  /// worker isolate. Idempotent.
  Future<void> shutdown();

  /// Stats from the most recently completed [generate] call, or `null`
  /// before the first one finishes.
  GenAiGenerationStats? get lastGenerationStats;
}

// ---------------------------------------------------------------------------
// Isolate message protocol. Every class here must be plain-data (no
// closures, no FFI pointers) to survive `SendPort.send`.
// ---------------------------------------------------------------------------

class _WorkerInit {
  _WorkerInit({
    required this.replyTo,
    required this.modelDir,
    required this.contextWindow,
    required this.libsDir,
    required this.logLevel,
  });
  final SendPort replyTo;
  final String modelDir;
  final int contextWindow;
  final String? libsDir;
  final GemmaLogLevel logLevel;
}

class _Ready {
  _Ready(this.commandPort);
  final SendPort commandPort;
}

class _GenerateRequest {
  _GenerateRequest(this.id, this.turn);
  final int id;
  final GenAiTurn turn;
}

class _Chunk {
  _Chunk(this.id, this.text);
  final int id;
  final String text;
}

class _GenerateDone {
  _GenerateDone(
    this.id,
    this.stopped,
    this.promptTokens,
    this.generatedTokens,
    this.decodeMs,
  );
  final int id;
  final bool stopped;
  final int promptTokens;
  final int generatedTokens;
  final int decodeMs;
}

class _GenerateError {
  _GenerateError(this.id, this.error);
  final int id;
  final String error;
}

class _StopSignal {
  const _StopSignal();
}

class _ResetSessionRequest {
  const _ResetSessionRequest();
}

class _ResetSessionAck {
  const _ResetSessionAck();
}

class _CountTokensRequest {
  _CountTokensRequest(this.id, this.text);
  final int id;
  final String text;
}

class _CountTokensReply {
  _CountTokensReply(this.id, this.count, this.error);
  final int id;
  final int? count;
  final String? error;
}

class _Close {
  const _Close();
}

class _CloseAck {
  const _CloseAck();
}

/// Main-isolate handle to the ORT-GenAI worker. Spawns the isolate, performs
/// the load handshake, and multiplexes concurrent requests by id. See this
/// file's top doc for why native handles never cross the port.
class GenAiFfiClient implements GenAiClient {
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _fromWorker;
  StreamSubscription? _sub;

  /// Serializes `generate`/`countTokens` calls. [stopGeneration] is
  /// deliberately NOT gated by this — see its doc.
  final Mutex _mutex = Mutex();

  bool _loaded = false;
  bool _closed = false;

  int _nextId = 0;
  final Map<int, StreamController<String>> _activeStreams = {};
  final Map<int, Completer<void>> _streamDone = {};
  final Map<int, Completer<int>> _countPending = {};
  Completer<void>? _closeAck;
  Completer<void>? _resetAck;

  GenAiGenerationStats? _lastStats;
  @override
  GenAiGenerationStats? get lastGenerationStats => _lastStats;

  @override
  Future<void> load(String modelDir, {int contextWindow = 1024}) async {
    if (_closed) {
      throw StateError('GenAiFfiClient is closed');
    }
    if (_loaded) {
      throw StateError('GenAiFfiClient is already loaded');
    }

    final fromWorker = ReceivePort();
    final readyCompleter = Completer<_Ready>();

    late final StreamSubscription sub;
    sub = fromWorker.listen((msg) {
      if (msg is _Ready) {
        if (!readyCompleter.isCompleted) readyCompleter.complete(msg);
      } else if (msg is String) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError(msg));
        }
      } else if (msg == null) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
            StateError('ONNX GenAI worker isolate exited during load'),
          );
        }
      }
    });

    final envLibsDir = Platform.environment[genAiLibsDirEnvVar];
    final isolate = await Isolate.spawn(
      _workerEntry,
      _WorkerInit(
        replyTo: fromWorker.sendPort,
        modelDir: modelDir,
        contextWindow: contextWindow,
        libsDir: (envLibsDir != null && envLibsDir.isNotEmpty)
            ? envLibsDir
            : null,
        logLevel: gemmaLogLevel,
      ),
      onExit: fromWorker.sendPort,
      debugName: 'onnx-genai-worker',
    );

    final _Ready ready;
    try {
      ready = await readyCompleter.future;
    } catch (_) {
      await sub.cancel();
      fromWorker.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }

    _isolate = isolate;
    _fromWorker = fromWorker;
    _commandPort = ready.commandPort;
    _loaded = true;
    sub.onData(_dispatch);
    _sub = sub;
  }

  void _dispatch(dynamic msg) {
    if (msg is _Chunk) {
      _activeStreams[msg.id]?.add(msg.text);
    } else if (msg is _GenerateDone) {
      _lastStats = GenAiGenerationStats(
        promptTokens: msg.promptTokens,
        generatedTokens: msg.generatedTokens,
        decodeMs: msg.decodeMs,
      );
      final controller = _activeStreams.remove(msg.id);
      unawaited(controller?.close());
      _streamDone.remove(msg.id)?.complete();
    } else if (msg is _GenerateError) {
      final controller = _activeStreams.remove(msg.id);
      controller?.addError(StateError(msg.error));
      unawaited(controller?.close());
      _streamDone.remove(msg.id)?.complete();
    } else if (msg is _CountTokensReply) {
      final completer = _countPending.remove(msg.id);
      if (completer == null) return;
      if (msg.error != null) {
        completer.completeError(StateError(msg.error!));
      } else {
        completer.complete(msg.count!);
      }
    } else if (msg is _ResetSessionAck) {
      if (_resetAck case final ack? when !ack.isCompleted) ack.complete();
    } else if (msg is _CloseAck) {
      if (_closeAck case final ack? when !ack.isCompleted) ack.complete();
    } else if (msg == null) {
      // Worker died unexpectedly (onExit signal). Fail everything in-flight
      // rather than leave callers hanging forever.
      final err = StateError('ONNX GenAI worker isolate exited unexpectedly');
      for (final id in _activeStreams.keys.toList()) {
        final controller = _activeStreams.remove(id);
        controller?.addError(err);
        unawaited(controller?.close());
        _streamDone.remove(id)?.complete();
      }
      for (final c in _countPending.values) {
        if (!c.isCompleted) c.completeError(err);
      }
      _countPending.clear();
      _closed = true;
      if (_closeAck case final ack? when !ack.isCompleted) ack.complete();
      if (_resetAck case final ack? when !ack.isCompleted) ack.complete();
    }
  }

  @override
  Stream<String> generate(GenAiTurn turn) {
    // If the consumer cancels its subscription (a plain `break` out of
    // `await for`, or a voice-loop barge-in) WITHOUT calling
    // [stopGeneration] itself, nothing would otherwise tell the worker to
    // stop decoding — it would keep generating to `max_length` while
    // `_runGenerateGuarded` sits on `done.future`, wedging `_mutex` for the
    // whole abandoned decode. Mirrors the litertlm engine's "StreamController
    // onCancel -> native cancel" fix (commit 93a5298). `stopGeneration` is
    // idempotent/cheap when the turn already finished normally.
    final controller = StreamController<String>(
      onCancel: () => unawaited(stopGeneration()),
    );
    unawaited(_runGenerateGuarded(controller, turn));
    return controller.stream;
  }

  Future<void> _runGenerateGuarded(
    StreamController<String> controller,
    GenAiTurn turn,
  ) async {
    if (_closed || !_loaded) {
      controller.addError(StateError('GenAiFfiClient is not loaded'));
      await controller.close();
      return;
    }
    await _mutex.acquire();
    final id = _nextId++;
    final done = _streamDone[id] = Completer<void>();
    _activeStreams[id] = controller;
    try {
      _commandPort!.send(_GenerateRequest(id, turn));
      await done.future;
    } catch (e) {
      if (_activeStreams.containsKey(id)) {
        controller.addError(e);
        _activeStreams.remove(id);
        await controller.close();
      }
    } finally {
      _streamDone.remove(id);
      _mutex.release();
    }
  }

  @override
  Future<int> countTokens(String text) {
    if (_closed || !_loaded) {
      throw StateError('GenAiFfiClient is not loaded');
    }
    return _mutex.protect(() {
      final id = _nextId++;
      final completer = Completer<int>();
      _countPending[id] = completer;
      _commandPort!.send(_CountTokensRequest(id, text));
      return completer.future;
    });
  }

  @override
  Future<void> stopGeneration() async {
    if (_commandPort == null) return;
    _commandPort!.send(const _StopSignal());
  }

  @override
  Future<void> resetSession() async {
    if (_closed || _commandPort == null) return;
    final ack = _resetAck = Completer<void>();
    _commandPort!.send(const _ResetSessionRequest());
    try {
      await ack.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timed out or the worker died — fall through, nothing more to do.
    }
  }

  @override
  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    if (_commandPort == null) {
      // Never loaded (or load failed) — nothing native to tear down.
      return;
    }
    final ack = _closeAck = Completer<void>();
    _commandPort!.send(const _Close());
    try {
      await ack.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timed out or the worker already died — fall through to a forced kill.
    }
    await _sub?.cancel();
    _fromWorker?.close();
    _isolate?.kill(priority: Isolate.beforeNextEvent);

    final err = StateError('GenAiFfiClient shut down');
    for (final id in _activeStreams.keys.toList()) {
      final controller = _activeStreams.remove(id);
      controller?.addError(err);
      unawaited(controller?.close());
      _streamDone.remove(id)?.complete();
    }
    for (final c in _countPending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _countPending.clear();
  }
}

// ---------------------------------------------------------------------------
// Worker isolate entry point.
// ---------------------------------------------------------------------------

/// Candidate paths/names to try opening [libraryName] (bare, no `lib`
/// prefix/extension) with, in priority order, for the current platform.
///
/// On macOS/iOS the FIRST candidate is the CodeAsset's framework leaf name
/// (`hook/build.dart` registers each dylib under a bare asset name; Flutter's
/// macOS build wraps every CodeAsset in its own `<name>.framework`, renaming
/// the binary inside to `<name>.framework/<name>`) — Task 4's framework-wrap
/// risk: GenAI dlopens `libonnxruntime.dylib` by BARE LEAF NAME at runtime,
/// which does not automatically resolve to an already-loaded framework-wrapped
/// image unless something opens it by its real (framework) path FIRST, putting
/// it in dyld's loaded-image set before GenAI's own lookup runs. The bare
/// `lib<name>.dylib` names are a fallback for host runs that bypass the
/// CodeAsset bundle (`flutter test`, the macOS host smoke test's `libsDir`
/// override takes priority over all of this — see [_openGenAiLibraries]).
List<String> _candidateNames(String libraryName) {
  if (Platform.isMacOS || Platform.isIOS) {
    return ['$libraryName.framework/$libraryName', 'lib$libraryName.dylib'];
  }
  if (Platform.isLinux || Platform.isAndroid) return ['lib$libraryName.so'];
  if (Platform.isWindows) return ['$libraryName.dll'];
  throw UnsupportedError(
    'ONNX GenAI is not available on ${Platform.operatingSystem}',
  );
}

ffi.DynamicLibrary _openFirst(List<String> candidates) {
  Object? lastError;
  for (final path in candidates) {
    try {
      return ffi.DynamicLibrary.open(path);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError('Could not open any of $candidates. Last error: $lastError');
}

(ffi.DynamicLibrary, ffi.DynamicLibrary) _openGenAiLibraries(String? libsDir) {
  final ffi.DynamicLibrary ortLib;
  final ffi.DynamicLibrary genaiLib;
  if (libsDir != null) {
    // Host-test override (FLUTTER_GEMMA_ORT_GENAI_LIBS / the macOS host
    // smoke test): exact spike layout, bare platform-default names in one
    // directory — bypasses the CodeAsset bundle entirely.
    final ortName = _candidateNames('onnxruntime').last;
    final genaiName = _candidateNames('onnxruntime-genai').last;
    ortLib = ffi.DynamicLibrary.open('$libsDir/$ortName');
    genaiLib = ffi.DynamicLibrary.open('$libsDir/$genaiName');
  } else {
    ortLib = _openFirst(_candidateNames('onnxruntime'));
    genaiLib = _openFirst(_candidateNames('onnxruntime-genai'));
  }

  // Preload ORT first (full path/framework), then GenAI — GenAI internally
  // dlopen()s "libonnxruntime.dylib" (etc.) by BARE NAME at runtime, not as
  // a load-time dependency. Loading the exact dylib first lets the bare-name
  // lookup resolve to the already-loaded image. Exact spike order.
  ortLib.providesSymbol('OrtGetApiBase'); // keep ortLib reachable/loaded
  return (ortLib, genaiLib);
}

Future<void> _workerEntry(_WorkerInit init) async {
  gemmaLogLevel = init.logLevel;

  late final OrtGenAiBindings oga;

  void check(ffi.Pointer<OgaResult> result, String step) {
    if (result == ffi.nullptr) return;
    final errPtr = oga.OgaResultGetError(result);
    final message = errPtr == ffi.nullptr
        ? '<no message>'
        : errPtr.cast<pkg_ffi.Utf8>().toDartString();
    oga.OgaDestroyResult(result);
    throw StateError('ORT-GenAI $step failed: $message');
  }

  ffi.Pointer<OgaModel>? model;
  ffi.Pointer<OgaTokenizer>? tokenizer;
  ffi.Pointer<OgaGenerator>? generator;

  try {
    final (ortLib, genaiLib) = _openGenAiLibraries(init.libsDir);
    // ignore: unused_local_variable — kept reachable so the image isn't GC'd.
    final keepOrtLibLoaded = ortLib;
    oga = OrtGenAiBindings(genaiLib);

    final configPathC = init.modelDir.toNativeUtf8();
    final modelOut = pkg_ffi.calloc<ffi.Pointer<OgaModel>>();
    try {
      check(oga.OgaCreateModel(configPathC.cast(), modelOut), 'OgaCreateModel');
      model = modelOut.value;
    } finally {
      pkg_ffi.calloc.free(configPathC);
      pkg_ffi.calloc.free(modelOut);
    }

    final tokenizerOut = pkg_ffi.calloc<ffi.Pointer<OgaTokenizer>>();
    try {
      check(oga.OgaCreateTokenizer(model, tokenizerOut), 'OgaCreateTokenizer');
      tokenizer = tokenizerOut.value;
    } finally {
      pkg_ffi.calloc.free(tokenizerOut);
    }
  } catch (e, st) {
    gemmaLog('[GenAiFfiClient/worker] load failed: $e\n$st');
    if (model != null) {
      try {
        oga.OgaDestroyModel(model);
      } catch (_) {}
    }
    init.replyTo.send('ONNX GenAI worker failed to load: $e');
    return;
  }

  final commandPort = ReceivePort();
  init.replyTo.send(_Ready(commandPort.sendPort));

  var stopRequested = false;

  /// The in-flight [runGenerate] call, if any — the command loop below is
  /// `unawaited` on purpose (so a queued `_StopSignal` can interleave via the
  /// decode loop's per-token yield), but that also means a teardown message
  /// arriving while a generation is still running would otherwise race it:
  /// `_ResetSessionRequest`/`_Close` destroy `generator`/`tokenizer`/`model`
  /// out from under the suspended decode loop, which then resumes and hands
  /// the freed pointer straight to native calls (use-after-free). Every
  /// teardown branch below sets [stopRequested] (so the decode loop unwinds
  /// promptly, bounded to ~one token) and awaits this future FIRST, so
  /// `runGenerate`'s own `finally` (which destroys its `tokenizerStream`) has
  /// already run before any generator/tokenizer/model handle is freed.
  Future<void>? activeGeneration;

  /// Runs one turn: (re)creates the generator if needed, applies the chat
  /// template, prefills, then decodes token-by-token, streaming pieces back
  /// as they arrive. Deliberately NOT awaited by the command loop below —
  /// the `await Future(() {})` yield inside the decode loop is what lets a
  /// queued `_StopSignal` interleave and flip [stopRequested].
  Future<void> runGenerate(int id, GenAiTurn turn) async {
    stopRequested = false;
    ffi.Pointer<OgaTokenizerStream>? tokenizerStream;
    try {
      if (turn.isFirstTurn && generator != null) {
        oga.OgaDestroyGenerator(generator!);
        generator = null;
      }

      if (generator == null) {
        final paramsOut = pkg_ffi.calloc<ffi.Pointer<OgaGeneratorParams>>();
        final ffi.Pointer<OgaGeneratorParams> params;
        try {
          check(
            oga.OgaCreateGeneratorParams(model!, paramsOut),
            'OgaCreateGeneratorParams',
          );
          params = paramsOut.value;
        } finally {
          pkg_ffi.calloc.free(paramsOut);
        }
        final maxLengthNameC = 'max_length'.toNativeUtf8();
        try {
          check(
            oga.OgaGeneratorParamsSetSearchNumber(
              params,
              maxLengthNameC.cast(),
              init.contextWindow.toDouble(),
            ),
            'OgaGeneratorParamsSetSearchNumber(max_length)',
          );
          final genOut = pkg_ffi.calloc<ffi.Pointer<OgaGenerator>>();
          try {
            check(
              oga.OgaCreateGenerator(model, params, genOut),
              'OgaCreateGenerator',
            );
            generator = genOut.value;
          } finally {
            pkg_ffi.calloc.free(genOut);
          }
        } finally {
          pkg_ffi.calloc.free(maxLengthNameC);
          oga.OgaDestroyGeneratorParams(params);
        }
      }

      // --- Chat template (SDK-owns-templates, Task 3) ----------------------
      final messages = <Map<String, String>>[
        if (turn.isFirstTurn && (turn.systemInstruction?.isNotEmpty ?? false))
          {'role': 'system', 'content': turn.systemInstruction!},
        {'role': 'user', 'content': turn.userContent},
      ];
      final messagesJsonC = jsonEncode(messages).toNativeUtf8();
      final templatedOut = pkg_ffi.calloc<ffi.Pointer<ffi.Char>>();
      final String templated;
      try {
        check(
          oga.OgaTokenizerApplyChatTemplate(
            tokenizer!,
            ffi.nullptr, // template_str: use the tokenizer's own built-in
            messagesJsonC.cast(),
            ffi.nullptr, // tools
            true, // add_generation_prompt
            templatedOut,
          ),
          'OgaTokenizerApplyChatTemplate',
        );
        templated = templatedOut.value.cast<pkg_ffi.Utf8>().toDartString();
      } finally {
        pkg_ffi.calloc.free(messagesJsonC);
        if (templatedOut.value != ffi.nullptr) {
          oga.OgaDestroyString(templatedOut.value);
        }
        pkg_ffi.calloc.free(templatedOut);
      }

      // --- Encode + prefill (AppendTokenSequences) -------------------------
      // Prefill runs INSIDE AppendTokenSequences on this GenAI version, not
      // the first GenerateNextToken (verified spike gotcha).
      final sequencesOut = pkg_ffi.calloc<ffi.Pointer<OgaSequences>>();
      final ffi.Pointer<OgaSequences> sequences;
      try {
        check(oga.OgaCreateSequences(sequencesOut), 'OgaCreateSequences');
        sequences = sequencesOut.value;
      } finally {
        pkg_ffi.calloc.free(sequencesOut);
      }
      final promptC = templated.toNativeUtf8();
      final int promptTokens;
      try {
        check(
          oga.OgaTokenizerEncode(tokenizer, promptC.cast(), sequences),
          'OgaTokenizerEncode',
        );
        promptTokens = oga.OgaSequencesGetSequenceCount(sequences, 0);
        check(
          oga.OgaGenerator_AppendTokenSequences(generator!, sequences),
          'OgaGenerator_AppendTokenSequences (prefill)',
        );
      } finally {
        pkg_ffi.calloc.free(promptC);
        oga.OgaDestroySequences(sequences);
      }

      final streamOut = pkg_ffi.calloc<ffi.Pointer<OgaTokenizerStream>>();
      try {
        check(
          oga.OgaCreateTokenizerStream(tokenizer, streamOut),
          'OgaCreateTokenizerStream',
        );
        tokenizerStream = streamOut.value;
      } finally {
        pkg_ffi.calloc.free(streamOut);
      }

      var generatedCount = 0;
      final cap = turn.maxOutputTokens;

      void decodeAndEmit() {
        final outPtr = pkg_ffi.calloc<ffi.Pointer<ffi.Int32>>();
        final outCount = pkg_ffi.calloc<ffi.Size>();
        final int token;
        try {
          check(
            oga.OgaGenerator_GetNextTokens(generator!, outPtr, outCount),
            'OgaGenerator_GetNextTokens',
          );
          token = outPtr.value[outCount.value - 1];
        } finally {
          pkg_ffi.calloc.free(outPtr);
          pkg_ffi.calloc.free(outCount);
        }
        final decodedOut = pkg_ffi.calloc<ffi.Pointer<ffi.Char>>();
        try {
          check(
            oga.OgaTokenizerStreamDecode(tokenizerStream!, token, decodedOut),
            'OgaTokenizerStreamDecode',
          );
          // `out` from OgaTokenizerStreamDecode is owned by the stream — do
          // NOT OgaDestroyString it (unlike OgaTokenizerDecode's out_string).
          final piece = decodedOut.value == ffi.nullptr
              ? ''
              : decodedOut.value.cast<pkg_ffi.Utf8>().toDartString();
          if (piece.isNotEmpty) init.replyTo.send(_Chunk(id, piece));
        } finally {
          pkg_ffi.calloc.free(decodedOut);
        }
        generatedCount++;
      }

      // Prefill above is one long synchronous FFI call with no `await` in
      // it — a `_StopSignal` sent while it was running sits unprocessed in
      // the isolate's mailbox the whole time (the outer command loop can't
      // dispatch it until this function yields), so it would otherwise
      // ALWAYS survive to force one unconditional token out of the
      // just-primed generator. Yield once here, mirroring the decode loop's
      // own per-token yield below, so that already-queued stop lands before
      // (not after) the first token is spent.
      await Future<void>(() {});
      if (!stopRequested) {
        check(
          oga.OgaGenerator_GenerateNextToken(generator!),
          'OgaGenerator_GenerateNextToken (first token)',
        );
        decodeAndEmit();
      }

      // Timed separately from prefill+first-token, matching the spike: the
      // first token's forward pass rides along with AppendTokenSequences.
      final swDecode = Stopwatch()..start();
      while (!oga.OgaGenerator_IsDone(generator!) &&
          (cap == null || generatedCount < cap)) {
        // Yield one event-loop turn per token so a queued _StopSignal can
        // flip `stopRequested` before the next token is generated.
        await Future<void>(() {});
        if (stopRequested) break;
        check(
          oga.OgaGenerator_GenerateNextToken(generator!),
          'OgaGenerator_GenerateNextToken (decode)',
        );
        decodeAndEmit();
      }
      swDecode.stop();

      init.replyTo.send(
        _GenerateDone(
          id,
          stopRequested,
          promptTokens,
          generatedCount,
          swDecode.elapsedMilliseconds,
        ),
      );
    } catch (e, st) {
      gemmaLog('[GenAiFfiClient/worker] generate failed: $e\n$st');
      init.replyTo.send(_GenerateError(id, e.toString()));
    } finally {
      if (tokenizerStream != null) {
        oga.OgaDestroyTokenizerStream(tokenizerStream);
      }
      stopRequested = false;
    }
  }

  try {
    await for (final msg in commandPort) {
      if (msg is _GenerateRequest) {
        final future = runGenerate(msg.id, msg.turn);
        activeGeneration = future;
        unawaited(
          future.whenComplete(() {
            if (identical(activeGeneration, future)) activeGeneration = null;
          }),
        );
      } else if (msg is _CountTokensRequest) {
        try {
          final sequencesOut = pkg_ffi.calloc<ffi.Pointer<OgaSequences>>();
          final ffi.Pointer<OgaSequences> sequences;
          try {
            check(oga.OgaCreateSequences(sequencesOut), 'OgaCreateSequences');
            sequences = sequencesOut.value;
          } finally {
            pkg_ffi.calloc.free(sequencesOut);
          }
          final textC = msg.text.toNativeUtf8();
          try {
            check(
              oga.OgaTokenizerEncode(tokenizer, textC.cast(), sequences),
              'OgaTokenizerEncode',
            );
            final count = oga.OgaSequencesGetSequenceCount(sequences, 0);
            init.replyTo.send(_CountTokensReply(msg.id, count, null));
          } finally {
            pkg_ffi.calloc.free(textC);
            oga.OgaDestroySequences(sequences);
          }
        } catch (e) {
          init.replyTo.send(_CountTokensReply(msg.id, null, e.toString()));
        }
      } else if (msg is _StopSignal) {
        stopRequested = true;
      } else if (msg is _ResetSessionRequest) {
        // Unwind any in-flight decode loop (bounded — one more token at
        // most) and wait for its `finally` to finish BEFORE freeing the
        // generator it's still holding a reference to. See [activeGeneration]'s
        // doc.
        stopRequested = true;
        if (activeGeneration case final active?) await active;
        if (generator != null) {
          oga.OgaDestroyGenerator(generator!);
          generator = null;
        }
        init.replyTo.send(const _ResetSessionAck());
      } else if (msg is _Close) {
        // Same race as `_ResetSessionRequest` above, but for the full
        // tokenizer/model teardown in this function's own `finally` below —
        // without this await, a generation suspended on its per-token yield
        // would resume and touch `generator`/`tokenizer` handles freed by
        // that `finally` right after `break`.
        stopRequested = true;
        if (activeGeneration case final active?) await active;
        commandPort.close();
        break;
      }
    }
  } finally {
    if (generator != null) oga.OgaDestroyGenerator(generator!);
    oga.OgaDestroyTokenizer(tokenizer);
    oga.OgaDestroyModel(model);
    init.replyTo.send(const _CloseAck());
  }
}
