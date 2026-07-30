import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart'
    show SpeechRecognizer, SpeechSynthesizer, GemmaLogLevel;
import 'package:flutter_gemma/core/utils/gemma_log.dart' show gemmaLog;

import 'voice_event.dart';
import 'voice_responder.dart';

/// On-device voice turn: PCM in → [VoiceEvent]s out. Pure orchestration — owns
/// NO microphone, NO player, and none of the injected components' lifecycles
/// (the caller creates + closes recognizer / chat / synthesizer). See the
/// design spec (`2026-07-29-voice-loop-design.md`) for the full contract.
class VoiceSession {
  /// General constructor — any LLM behind a [VoiceResponder].
  VoiceSession.custom({
    required this.recognizer,
    required this.responder,
    required this.synthesizer,
  });

  final SpeechRecognizer recognizer;
  final VoiceResponder responder;
  final SpeechSynthesizer synthesizer;

  /// Max time interrupt() waits for the LLM reply stream to drain after stop()
  /// before force-terminating the turn and detaching the (still-running)
  /// subscription (§12 B1). The subscription is never cancelled — the chat
  /// epilogue (token accounting + rotation + history append) must run.
  static const Duration drainTimeout = Duration(seconds: 5);

  // ---- Per-turn state (null/reset between turns) ----
  StreamController<VoiceEvent>? _activeController;
  bool _interruptRequested = false;
  Completer<void>? _turnDone; // completes when the turn reaches its terminal
  Completer<void>?
  _replyDrained; // completes when the LLM stream ends or times out
  Timer? _drainTimer;
  bool _drainForced = false; // true if the bounded-drain timeout fired
  bool _interruptInFlight =
      false; // true while a call to interrupt() is running

  /// Sample rate of emitted reply audio (delegates to [synthesizer]).
  int get replySampleRate => synthesizer.sampleRate;

  /// Run one push-to-talk turn on a recorded utterance (16 kHz mono 16-bit LE
  /// PCM — same contract as [SpeechRecognizer.transcribe]).
  ///
  /// v1 sequence: transcribe(pcm) → VoiceTranscriptEvent(final) →
  /// responder.respond(text) streamed as VoiceReplyTextEvent(s) →
  /// synthesize(fullReply) → one VoiceReplyAudioEvent(final) →
  /// VoiceTurnCompleteEvent. A stage failure surfaces as a Dart stream error.
  ///
  /// WARNINGS:
  /// - Cancelling this stream's subscription is NOT a portable stop — to barge
  ///   in, call [interrupt].
  /// - Calling runTurn while a turn is in flight throws StateError.
  /// - STT truncates audio beyond its fixed window (~5 s for moonshine) and can
  ///   hallucinate text on near-silence — both are STT-model properties.
  Stream<VoiceEvent> runTurn(Uint8List pcm16kMono) {
    if (_activeController != null) {
      throw StateError('VoiceSession.runTurn called while a turn is in flight');
    }
    final controller = StreamController<VoiceEvent>();
    _activeController = controller;
    _interruptRequested = false;
    _drainForced = false;
    _turnDone = Completer<void>();
    controller.onListen = () {
      // Fire-and-forget driver — it is the SOLE writer of events (§12 B3).
      _drive(controller, pcm16kMono);
    };
    return controller.stream;
  }

  /// Barge-in. Idempotent (a genuine no-op when idle, and a concurrent second
  /// call while one is already running neither re-calls `stop()` nor re-arms
  /// the drain timer — it just awaits the same terminal via [_interruptInFlight]).
  /// Sets the interrupt flag, calls responder.stop() (caught if it throws),
  /// bounded-drains the reply stream, then awaits the driver's terminal. Never
  /// writes to the controller (§12 B3).
  Future<void> interrupt() async {
    final controller = _activeController;
    if (controller == null) return; // idle
    if (_interruptInFlight) {
      // Concurrent second call: true no-op, just await the in-flight terminal.
      final done = _turnDone;
      if (done != null) await done.future;
      return;
    }
    _interruptInFlight = true;
    try {
      _interruptRequested = true;
      // Capture BEFORE the await responder.stop() below (F1): if the current
      // turn completes naturally while stop() is in flight and the caller
      // immediately starts turn B, reading _replyDrained/_turnDone AFTER the
      // await would attach this drain timer / await to turn B instead of
      // turn A, force-completing B's un-interrupted drain 5s later.
      final drained = _replyDrained;
      final done = _turnDone;
      try {
        await responder.stop();
      } catch (e) {
        gemmaLog(
          'VoiceSession: responder.stop() threw during barge-in: $e',
          level: GemmaLogLevel.info,
        );
      }
      // Bounded drain: give the reply stream drainTimeout to end, else force it.
      if (drained != null && !drained.isCompleted) {
        _drainTimer = Timer(drainTimeout, () {
          if (!drained.isCompleted) {
            _drainForced = true;
            gemmaLog(
              'VoiceSession: barge-in drain exceeded ${drainTimeout.inSeconds}s; '
              'detaching LLM stream (generation finishes in background).',
              level: GemmaLogLevel.info,
            );
            drained.complete();
          }
        });
      }
      if (done != null) await done.future;
    } finally {
      _interruptInFlight = false;
    }
  }

  Future<void> _drive(
    StreamController<VoiceEvent> controller,
    Uint8List pcm,
  ) async {
    void finish(VoiceEvent terminal) {
      controller.add(terminal);
      _teardown(controller);
    }

    try {
      // ---- STT ----
      final transcript = await recognizer.transcribe(pcm);
      controller.add(VoiceTranscriptEvent(transcript, isFinal: true));
      if (_interruptRequested) {
        finish(
          VoiceTurnInterruptedEvent(
            transcript: transcript,
            partialReplyText: '',
          ),
        );
        return;
      }
      if (transcript.trim().isEmpty) {
        finish(const VoiceTurnCompleteEvent('', ''));
        return;
      }

      // ---- LLM (subscription so interrupt() can stop + bounded-drain) ----
      final buffer = StringBuffer();
      final drained = Completer<void>();
      _replyDrained = drained;
      Object? replyError;
      StackTrace? replyStack;
      final sub = responder
          .respond(transcript)
          .listen(
            (token) {
              if (controller.isClosed) return; // detached / torn-down turn
              buffer.write(token);
              controller.add(VoiceReplyTextEvent(token));
            },
            onError: (Object e, StackTrace st) {
              replyError = e;
              replyStack = st;
              if (!drained.isCompleted) drained.complete();
            },
            onDone: () {
              if (!drained.isCompleted) drained.complete();
            },
            cancelOnError: false,
          );
      await drained.future;
      _drainTimer?.cancel();
      // Natural end / fatal error → safe to cancel. Forced timeout → DETACH:
      // never cancel (would skip the chat epilogue → token undercount, R1).
      if (!_drainForced) {
        await sub.cancel();
      }
      final replyText = buffer.toString();

      // Error wins (whether or not interrupted): turn-fatal stream error, no
      // Interrupted/Complete event. interrupt()'s Future still completes (via
      // teardown) without rethrowing.
      if (replyError != null) {
        controller.addError(replyError!, replyStack);
        _teardown(controller);
        return;
      }
      if (_interruptRequested) {
        finish(
          VoiceTurnInterruptedEvent(
            transcript: transcript,
            partialReplyText: replyText,
          ),
        );
        return;
      }
      if (replyText.trim().isEmpty) {
        finish(VoiceTurnCompleteEvent(transcript, ''));
        return;
      }

      // ---- TTS ----
      final pcmOut = await synthesizer.synthesize(replyText);
      if (_interruptRequested) {
        // Barge-in landed during (uncancellable) synthesis → suppress audio.
        finish(
          VoiceTurnInterruptedEvent(
            transcript: transcript,
            partialReplyText: replyText,
          ),
        );
        return;
      }
      controller.add(
        VoiceReplyAudioEvent(
          pcmOut,
          sampleRate: synthesizer.sampleRate,
          isFinal: true,
        ),
      );
      finish(VoiceTurnCompleteEvent(transcript, replyText));
    } catch (e, st) {
      // Stage failure (transcribe/synthesize throw) is turn-fatal (§7).
      if (!controller.isClosed) {
        controller.addError(e, st);
        _teardown(controller);
      }
    }
  }

  void _teardown(StreamController<VoiceEvent> controller) {
    _drainTimer?.cancel();
    _drainTimer = null;
    if (!controller.isClosed) controller.close();
    if (identical(_activeController, controller)) {
      _activeController = null;
      _replyDrained = null;
    }
    final done = _turnDone;
    _turnDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }
}
