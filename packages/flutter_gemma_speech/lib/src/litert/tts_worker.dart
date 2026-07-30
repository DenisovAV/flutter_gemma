// Long-lived background isolate that owns the entire Matcha-TTS pipeline:
// both the text frontend (dictionary G2P + host embedding gather, Task 2.2)
// and the native LiteRT core (4 compiled graphs + the CFM/vocoder forward
// passes, Task 2.3). The forward passes are blocking synchronous FFI calls;
// running them (and the frontend's dictionary lookups + 275k-entry load)
// here keeps the UI isolate's event loop free. Direct analog of
// `stt_worker.dart` — see that file's header for the "why a long-lived
// worker and not `Isolate.run`" rationale (FFI handles can't cross isolate
// boundaries; the compiled models are expensive to build but cheap to run).
//
// Unlike `SttWorker` (which owns only `SttCore`, tokenizer included inside
// the core), this worker owns TWO objects: `TtsTextFrontend` and `TtsCore`.
// Setup loads both plus a `TtsTextNormalizer` (for `splitClauses`, needs no
// symbols). Each request splits `text` into clauses so the CFM decoder's
// `MAX_MEL` cap (and its perceptual quality — the model was trained on
// clause-length utterances) doesn't get exceeded by long replies: every
// clause is `frontend.encode`d and `core.synthesize`d with its own CFM seed
// (`ttsCfmSeed + clauseIndex`, so a single-clause request's seed is
// unchanged), and the resulting PCM segments are spliced with a short
// inter-clause silence (`concatPcmWithSilence`, `tts_chunk.dart`). Only
// `TtsCore` holds native handles, so only `core.dispose()` runs in the
// teardown `finally`.
//
// Only sendable values cross the port: file paths + profile + backend
// (setup), a `String` (request), and a `Uint8List` of 16-bit PCM samples
// (reply).

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/utils/gemma_log.dart';

import '../model/tts_model_profile.dart';
import '../tts/tts_text_frontend.dart';
import '../tts/tts_text_normalizer.dart';
import 'tts_chunk.dart';
import 'tts_core.dart';

/// Handshake payload the worker sends back once the frontend + native model
/// are loaded. Carries [sampleRate] (read from `TtsCore` after load) so the
/// facade (Task 2.5) can expose it synchronously without a round-trip.
class _Ready {
  _Ready(this.commandPort, this.sampleRate);
  final SendPort commandPort;
  final int sampleRate;
}

/// Request: synthesize [text]. [id] correlates the reply.
class _SynthRequest {
  _SynthRequest(this.id, this.text);
  final int id;
  final String text;
}

/// Reply carrying the synthesized 16-bit LE mono PCM (or an error message).
class _SynthReply {
  _SynthReply(this.id, this.pcm, this.error);
  final int id;
  final Uint8List? pcm;
  final String? error;
}

/// Sentinel asking the worker to tear down the native model and exit.
class _Close {
  const _Close();
}

/// Ack the worker sends after [TtsCore.dispose] completes, so the main
/// isolate can kill the isolate without racing native teardown.
class _CloseAck {
  const _CloseAck();
}

/// Parameters needed to boot the worker isolate. Must be fully sendable.
class _WorkerInit {
  _WorkerInit({
    required this.replyTo,
    required this.profile,
    required this.artifactPaths,
    required this.backend,
    required this.logLevel,
  });
  final SendPort replyTo;
  final TtsModelProfile profile;
  final Map<String, String> artifactPaths;
  final PreferredBackend? backend;

  /// Snapshot of the main-isolate [gemmaLogLevel] at spawn — the worker
  /// isolate gets its own copy of the per-isolate top-level (default info),
  /// so it must be seeded explicitly.
  final GemmaLogLevel logLevel;
}

/// Main-isolate handle to the TTS worker. Spawns the isolate, performs the
/// load handshake, and multiplexes concurrent requests by id.
class TtsWorker {
  TtsWorker._(
    this._isolate,
    this._commandPort,
    this._fromWorker,
    this._sampleRate,
  );

  final Isolate _isolate;
  final SendPort _commandPort;
  final ReceivePort _fromWorker;
  final int _sampleRate;

  final _pending = <int, Completer<Uint8List>>{};
  int _nextId = 0;
  bool _closed = false;
  Completer<void>? _closeAck;

  /// Spawn the worker and wait until the frontend + native model are loaded.
  static Future<TtsWorker> spawn({
    required TtsModelProfile profile,
    required Map<String, String> artifactPaths,
    PreferredBackend? backend,
  }) async {
    final fromWorker = ReceivePort();
    final readyCompleter = Completer<_Ready>();

    // First message from the worker is either _Ready or a String error. A
    // `null` is the isolate's onExit signal — if it arrives before _Ready,
    // the worker died during load (e.g. a native crash compiling a corrupt
    // model), so fail the completer instead of hanging forever.
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
            StateError('TTS worker isolate exited during load'),
          );
        }
      }
    });

    // Wrap BOTH the spawn and the ready-wait: if Isolate.spawn itself throws
    // (e.g. resource exhaustion) fromWorker/sub would otherwise leak.
    Isolate? isolate;
    final _Ready ready;
    try {
      isolate = await Isolate.spawn(
        _workerEntry,
        _WorkerInit(
          replyTo: fromWorker.sendPort,
          profile: profile,
          artifactPaths: artifactPaths,
          backend: backend,
          logLevel: gemmaLogLevel,
        ),
        // onExit posts `null` to fromWorker so we never wait on a dead isolate.
        onExit: fromWorker.sendPort,
        debugName: 'litert-tts-worker',
      );
      ready = await readyCompleter.future;
    } catch (_) {
      await sub.cancel();
      fromWorker.close();
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    }

    final worker = TtsWorker._(
      isolate,
      ready.commandPort,
      fromWorker,
      ready.sampleRate,
    );
    // Re-point the subscription at the steady-state reply handler.
    sub.onData(worker._onReply);
    return worker;
  }

  /// Output sample rate (Hz), learned from the load handshake.
  int get sampleRate => _sampleRate;

  void _onReply(dynamic msg) {
    if (msg is _SynthReply) {
      final completer = _pending.remove(msg.id);
      if (completer == null) return;
      if (msg.error != null) {
        completer.completeError(StateError(msg.error!));
      } else {
        completer.complete(msg.pcm!);
      }
    } else if (msg is _CloseAck) {
      if (_closeAck?.isCompleted == false) _closeAck?.complete();
    } else if (msg == null) {
      // onExit: the worker isolate died. If this is part of a normal close,
      // the ack path already handled it; otherwise it's an unexpected crash
      // — fail every in-flight request rather than leave callers hanging.
      _failAllPending('TTS worker isolate exited unexpectedly');
      _closed = true;
      if (_closeAck?.isCompleted == false) _closeAck?.complete();
    }
  }

  void _failAllPending(String reason) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError(reason));
    }
    _pending.clear();
  }

  /// Synthesize [text] → 16-bit LE mono PCM. The frontend encode + native
  /// forward passes run in the worker; the UI isolate stays free.
  Future<Uint8List> synthesize(String text) {
    if (_closed) {
      return Future.error(StateError('TtsWorker is closed'));
    }
    final id = _nextId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    _commandPort.send(_SynthRequest(id, text));
    return completer.future;
  }

  /// Tear down the native model + frontend and stop the isolate. Waits for
  /// the worker to finish native teardown (a _CloseAck, or the isolate's
  /// onExit) before killing it, so handles are never freed mid-dispose.
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
      gemmaLog(
        '⚠️  TtsWorker.close(): native teardown ack timed out — forcing kill',
      );
    }
    _fromWorker.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _failAllPending('TtsWorker closed mid-request');
  }
}

/// Isolate entry point. Loads the frontend + model, then serves requests
/// until _Close.
Future<void> _workerEntry(_WorkerInit init) async {
  // Seed this isolate's per-isolate log level from the main-isolate snapshot.
  gemmaLogLevel = init.logLevel;
  final TtsCore core;
  final TtsTextFrontend frontend;
  final TtsTextNormalizer normalizer;
  try {
    // Core loads first: the frontend needs `core.neuralG2p` (the dp_g2p
    // graph) to resolve out-of-vocabulary words that aren't in the
    // dictionary. Loading order doesn't affect output — only which OOV
    // words the frontend can resolve without throwing.
    core = await TtsCore.load(
      profile: init.profile,
      artifactPaths: init.artifactPaths,
      backend: init.backend,
    );
    frontend = await TtsTextFrontend.load(
      init.profile,
      init.artifactPaths,
      neuralG2p: core.neuralG2p,
    );
    // splitClauses only reads punctuation, so an empty symbol set is fine —
    // the normalizer is built purely to reuse the locale-selected clause
    // splitter, not to normalize/encode text (that stays `frontend.encode`).
    // Built inside the try so a future non-`en` locale's UnimplementedError
    // surfaces as a descriptive load-failure reply instead of a bare
    // isolate exit.
    normalizer = TtsTextNormalizer.forLocale(init.profile.locale, {});
  } catch (e, st) {
    gemmaLog('[TtsWorker] load failed: $e\n$st');
    init.replyTo.send('TTS worker failed to load: $e');
    return;
  }

  final commandPort = ReceivePort();
  init.replyTo.send(_Ready(commandPort.sendPort, core.sampleRate));

  try {
    await for (final msg in commandPort) {
      if (msg is _SynthRequest) {
        try {
          final clauses = normalizer.splitClauses(msg.text);
          final units = clauses.isEmpty ? <String>[msg.text] : clauses;
          final segs = <Uint8List>[];
          for (var i = 0; i < units.length; i++) {
            final input = frontend.encode(units[i]);
            if (input.realLen <= 1) continue; // empty chunk → no audio.
            segs.add(core.synthesize(input, seed: ttsCfmSeed + i));
          }
          final pcm = segs.isEmpty
              ? Uint8List(0)
              : concatPcmWithSilence(
                  segs,
                  silenceSamples: (core.sampleRate * 0.12).round(),
                );
          init.replyTo.send(_SynthReply(msg.id, pcm, null));
        } catch (e) {
          init.replyTo.send(_SynthReply(msg.id, null, e.toString()));
        }
      } else if (msg is _Close) {
        commandPort.close();
        break;
      }
    }
  } finally {
    // Only the native core holds handles to free — the frontend is pure
    // Dart (dictionary map + embedding table), nothing to dispose there.
    // Always dispose even if the loop exits unexpectedly, then ack so the
    // main isolate can kill us without racing teardown.
    core.dispose();
    init.replyTo.send(const _CloseAck());
  }
}
