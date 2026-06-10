// Long-lived background isolate that owns the entire LiteRT embedding native
// lifecycle (lib open, model compile, forward pass, teardown) and the
// SentencePiece tokenizer. The forward pass (`LiteRtRunCompiledModel`) is a
// blocking synchronous FFI call; running it here keeps the UI isolate's event
// loop free (issue #299).
//
// Why a long-lived worker and not `Isolate.run` per call:
//   - The compiled model costs ~570-780ms to build but only ~80ms to run, so
//     it MUST be compiled once and reused — `Isolate.run` would recompile
//     every call.
//   - FFI `Pointer`/`DynamicLibrary` cannot cross isolate boundaries
//     (flutter/flutter#169431; passing a pointer as an int is officially
//     "risky and unsupported"). Keeping all handles inside the one worker
//     means nothing crosses the boundary, and a (future) GPU command queue —
//     which is thread-affine — is created and used on the same isolate.
//
// Only sendable values cross the port: file paths + backend (setup), text +
// task-type prefix (request), and `List<double>` vectors (reply).

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_gemma/core/utils/gemma_log.dart';

import 'litert_embedding_core.dart';

/// Backend selector mirrored across the isolate boundary as a plain int
/// (the `PreferredBackend` enum lives in pigeon-generated code; we map it to
/// the LiteRT HW accelerator bit in the worker).
enum EmbeddingBackend { cpu, gpu, npu }

/// Handshake payload the worker sends back once the native model is loaded.
class _Ready {
  _Ready(this.commandPort, this.seqLen, this.dim);
  final SendPort commandPort;
  final int seqLen;
  final int dim;
}

/// Request: embed [text] with the given task-type [prefix]. [id] correlates
/// the reply.
class _EmbedRequest {
  _EmbedRequest(this.id, this.text, this.prefix);
  final int id;
  final String text;
  final String prefix;
}

/// Reply carrying the embedding vector (or an error message).
class _EmbedReply {
  _EmbedReply(this.id, this.vector, this.error);
  final int id;
  final List<double>? vector;
  final String? error;
}

/// Sentinel asking the worker to tear down the native model and exit.
class _Close {
  const _Close();
}

/// Ack the worker sends after [EmbeddingCore.dispose] completes, so the main
/// isolate can kill the isolate without racing native teardown.
class _CloseAck {
  const _CloseAck();
}

/// Parameters needed to boot the worker isolate. Must be fully sendable.
class _WorkerInit {
  _WorkerInit({
    required this.replyTo,
    required this.modelPath,
    required this.tokenizerPath,
    required this.backend,
    required this.inputSequenceLength,
    required this.outputDimension,
    required this.logLevel,
  });
  final SendPort replyTo;
  final String modelPath;
  final String tokenizerPath;
  final EmbeddingBackend backend;
  final int? inputSequenceLength;
  final int? outputDimension;
  final GemmaLogLevel logLevel;
}

/// Main-isolate handle to the embedding worker. Spawns the isolate, performs
/// the load handshake, and multiplexes concurrent requests by id.
class EmbeddingWorker {
  EmbeddingWorker._(
    this._isolate,
    this._commandPort,
    this._fromWorker,
    this.inputSequenceLength,
    this.outputDimension,
  );

  final Isolate _isolate;
  final SendPort _commandPort;
  final ReceivePort _fromWorker;

  /// Sequence length the model was compiled for.
  final int inputSequenceLength;

  /// Output embedding dimension.
  final int outputDimension;

  final _pending = <int, Completer<List<double>>>{};
  int _nextId = 0;
  bool _closed = false;
  Completer<void>? _closeAck;

  /// Spawn the worker and wait until the native model is loaded.
  static Future<EmbeddingWorker> spawn({
    required String modelPath,
    required String tokenizerPath,
    EmbeddingBackend backend = EmbeddingBackend.cpu,
    int? inputSequenceLength,
    int? outputDimension,
  }) async {
    final fromWorker = ReceivePort();
    final readyCompleter = Completer<_Ready>();

    // First message from the worker is either _Ready or a String error. A
    // `null` is the isolate's onExit signal — if it arrives before _Ready, the
    // worker died during load (e.g. a native crash compiling a corrupt model),
    // so fail the completer instead of hanging forever.
    late final StreamSubscription sub;
    sub = fromWorker.listen((msg) {
      if (msg is _Ready) {
        readyCompleter.complete(msg);
      } else if (msg is String) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(StateError(msg));
        }
      } else if (msg == null) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(
              StateError('Embedding worker isolate exited during load'));
        }
      }
    });

    final isolate = await Isolate.spawn(
      _workerEntry,
      _WorkerInit(
        replyTo: fromWorker.sendPort,
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        backend: backend,
        inputSequenceLength: inputSequenceLength,
        outputDimension: outputDimension,
        logLevel: gemmaLogLevel,
      ),
      // onExit posts `null` to fromWorker so we never wait on a dead isolate.
      onExit: fromWorker.sendPort,
      debugName: 'litert-embedding-worker',
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

    final worker = EmbeddingWorker._(
      isolate,
      ready.commandPort,
      fromWorker,
      ready.seqLen,
      ready.dim,
    );
    // Re-point the subscription at the steady-state reply handler.
    sub.onData(worker._onReply);
    return worker;
  }

  void _onReply(dynamic msg) {
    if (msg is _EmbedReply) {
      final completer = _pending.remove(msg.id);
      if (completer == null) return;
      if (msg.error != null) {
        completer.completeError(StateError(msg.error!));
      } else {
        completer.complete(msg.vector!);
      }
    } else if (msg is _CloseAck) {
      _closeAck?.complete();
    } else if (msg == null) {
      // onExit: the worker isolate died. If this is part of a normal close,
      // the ack path already handled it; otherwise it's an unexpected crash —
      // fail every in-flight request rather than leave callers hanging.
      _failAllPending('Embedding worker isolate exited unexpectedly');
      _closed = true;
      _closeAck?.complete();
    }
  }

  void _failAllPending(String reason) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError(reason));
    }
    _pending.clear();
  }

  /// Embed one text. The forward runs in the worker; the UI isolate stays free.
  Future<List<double>> embed(String text, {required String prefix}) {
    if (_closed) {
      return Future.error(StateError('EmbeddingWorker is closed'));
    }
    final id = _nextId++;
    final completer = Completer<List<double>>();
    _pending[id] = completer;
    _commandPort.send(_EmbedRequest(id, text, prefix));
    return completer.future;
  }

  /// Tear down the native model and stop the isolate. Waits for the worker to
  /// finish native teardown (a _CloseAck, or the isolate's onExit) before
  /// killing it, so handles are never freed mid-dispose.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closeAck = Completer<void>();
    _commandPort.send(const _Close());
    // Wait for the worker's dispose ack / exit; cap the wait so a wedged
    // native teardown can't hang close() forever.
    try {
      await _closeAck!.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timed out or errored — fall through to a forced kill below.
    }
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _failAllPending('EmbeddingWorker closed mid-request');
  }
}

/// Isolate entry point. Loads the model, then serves requests until _Close.
Future<void> _workerEntry(_WorkerInit init) async {
  // snapshot main-isolate level into this isolate
  gemmaLogLevel = init.logLevel;
  final EmbeddingCore core;
  try {
    core = await EmbeddingCore.load(
      modelPath: init.modelPath,
      tokenizerPath: init.tokenizerPath,
      backend: init.backend,
      inputSequenceLength: init.inputSequenceLength,
      outputDimension: init.outputDimension,
    );
  } catch (e, st) {
    gemmaLog('[EmbeddingWorker] load failed: $e\n$st');
    init.replyTo.send('Embedding worker failed to load: $e');
    return;
  }

  final commandPort = ReceivePort();
  init.replyTo.send(_Ready(
      commandPort.sendPort, core.inputSequenceLength, core.outputDimension));

  try {
    await for (final msg in commandPort) {
      if (msg is _EmbedRequest) {
        try {
          final vector = core.embed(msg.text, prefix: msg.prefix);
          init.replyTo.send(_EmbedReply(msg.id, vector, null));
        } catch (e) {
          init.replyTo.send(_EmbedReply(msg.id, null, e.toString()));
        }
      } else if (msg is _Close) {
        commandPort.close();
        break;
      }
    }
  } finally {
    // Always free native handles, even if the loop exits unexpectedly, then
    // ack so the main isolate can kill us without racing teardown.
    core.dispose();
    init.replyTo.send(const _CloseAck());
  }
}
