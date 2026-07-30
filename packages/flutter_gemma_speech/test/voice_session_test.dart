import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_gemma/flutter_gemma.dart'
    show SpeechRecognizer, SpeechSynthesizer;
import 'package:flutter_gemma_speech/src/voice/voice_event.dart';
import 'package:flutter_gemma_speech/src/voice/voice_responder.dart';
import 'package:flutter_gemma_speech/src/voice/voice_session.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- Fakes ----
class _FakeRecognizer implements SpeechRecognizer {
  _FakeRecognizer(this.text);
  final String text;
  int calls = 0;
  @override
  Future<String> transcribe(Uint8List pcm) async {
    calls++;
    return text;
  }

  @override
  void addCloseListener(void Function() listener) {}
  @override
  Future<void> close() async {}
}

class _FakeSynth implements SpeechSynthesizer {
  _FakeSynth({this.gate});
  final Completer<void>? gate; // if set, synthesize blocks until completed
  int calls = 0;
  @override
  int get sampleRate => 22050;
  @override
  Future<Uint8List> synthesize(String text) async {
    calls++;
    if (gate != null) await gate!.future;
    return Uint8List.fromList([9, 9, 9]);
  }

  @override
  void addCloseListener(void Function() listener) {}
  @override
  Future<void> close() async {}
}

/// A responder whose reply stream the test drives via [ctrl]; `stop` closes it
/// (the contract: stop must end the respond stream). Records stop calls.
class _FakeResponder {
  final ctrl = StreamController<String>();
  int stopCalls = 0;
  bool stopThrows = false;
  int respondCalls = 0;

  VoiceResponder build() => VoiceResponder(
    respond: (userText) {
      respondCalls++;
      return ctrl.stream;
    },
    stop: () async {
      stopCalls++;
      if (stopThrows) throw StateError('stop boom');
      if (!ctrl.isClosed) await ctrl.close();
    },
  );
}

Uint8List _pcm() => Uint8List.fromList([1, 2, 3, 4]);

void main() {
  test(
    'happy path emits Transcript → ReplyText(s) → ReplyAudio → Complete',
    () async {
      final r = _FakeResponder();
      final synth = _FakeSynth();
      final session = VoiceSession.custom(
        recognizer: _FakeRecognizer('hello there'),
        responder: r.build(),
        synthesizer: synth,
      );
      final events = <VoiceEvent>[];
      final sub = session.runTurn(_pcm()).listen(events.add);
      await Future<void>.delayed(Duration.zero); // let transcribe resolve
      r.ctrl.add('Hi');
      r.ctrl.add(' there');
      await r.ctrl.close();
      await sub.asFuture<void>();

      expect(events.map((e) => e.runtimeType).toList(), [
        VoiceTranscriptEvent,
        VoiceReplyTextEvent,
        VoiceReplyTextEvent,
        VoiceReplyAudioEvent,
        VoiceTurnCompleteEvent,
      ]);
      final complete = events.last as VoiceTurnCompleteEvent;
      expect(complete.transcript, 'hello there');
      expect(complete.replyText, 'Hi there');
      expect((events[3] as VoiceReplyAudioEvent).sampleRate, 22050);
      expect(synth.calls, 1);
    },
  );

  test('empty transcript ends the turn with no LLM/TTS call', () async {
    final r = _FakeResponder();
    final synth = _FakeSynth();
    final session = VoiceSession.custom(
      recognizer: _FakeRecognizer('   '),
      responder: r.build(),
      synthesizer: synth,
    );
    final events = await session.runTurn(_pcm()).toList();
    expect(events.map((e) => e.runtimeType).toList(), [
      VoiceTranscriptEvent,
      VoiceTurnCompleteEvent,
    ]);
    expect((events.last as VoiceTurnCompleteEvent).replyText, '');
    expect(r.respondCalls, 0);
    expect(synth.calls, 0);
  });

  test('empty reply ends the turn with no TTS call', () async {
    final r = _FakeResponder();
    final synth = _FakeSynth();
    final session = VoiceSession.custom(
      recognizer: _FakeRecognizer('hi'),
      responder: r.build(),
      synthesizer: synth,
    );
    final fut = session.runTurn(_pcm()).toList();
    await Future<void>.delayed(Duration.zero);
    await r.ctrl.close(); // no tokens
    final events = await fut;
    expect(events.map((e) => e.runtimeType).toList(), [
      VoiceTranscriptEvent,
      VoiceTurnCompleteEvent,
    ]);
    expect(synth.calls, 0);
  });

  test('second runTurn while in flight throws StateError synchronously', () {
    final r = _FakeResponder();
    final session = VoiceSession.custom(
      recognizer: _FakeRecognizer('hi'),
      responder: r.build(),
      synthesizer: _FakeSynth(),
    );
    session.runTurn(_pcm()).listen((_) {});
    expect(() => session.runTurn(_pcm()), throwsStateError);
  });

  test(
    'interrupt during reply: stop called once, audio skipped, Interrupted carries partial',
    () async {
      final r = _FakeResponder();
      final synth = _FakeSynth();
      final session = VoiceSession.custom(
        recognizer: _FakeRecognizer('hi'),
        responder: r.build(),
        synthesizer: synth,
      );
      final events = <VoiceEvent>[];
      session.runTurn(_pcm()).listen(events.add);
      await Future<void>.delayed(Duration.zero);
      r.ctrl.add('par');
      await Future<void>.delayed(Duration.zero);
      await session.interrupt();

      expect(r.stopCalls, 1);
      expect(synth.calls, 0);
      expect(events.last, isA<VoiceTurnInterruptedEvent>());
      final it = events.last as VoiceTurnInterruptedEvent;
      expect(it.transcript, 'hi');
      expect(it.partialReplyText, 'par');
    },
  );

  test('interrupt during synthesis suppresses audio', () async {
    final r = _FakeResponder();
    final gate = Completer<void>();
    final synth = _FakeSynth(gate: gate);
    final session = VoiceSession.custom(
      recognizer: _FakeRecognizer('hi'),
      responder: r.build(),
      synthesizer: synth,
    );
    final events = <VoiceEvent>[];
    session.runTurn(_pcm()).listen(events.add);
    await Future<void>.delayed(Duration.zero);
    r.ctrl.add('done');
    await r.ctrl.close(); // LLM finishes naturally → driver enters synthesize()
    await Future<void>.delayed(Duration.zero);
    final interruptFut = session.interrupt(); // lands during synthesize
    gate.complete(); // release synthesize
    await interruptFut;

    expect(events.whereType<VoiceReplyAudioEvent>(), isEmpty);
    expect(events.last, isA<VoiceTurnInterruptedEvent>());
  });

  test('interrupt when idle is a no-op (does not call stop)', () async {
    final r = _FakeResponder();
    final session = VoiceSession.custom(
      recognizer: _FakeRecognizer('hi'),
      responder: r.build(),
      synthesizer: _FakeSynth(),
    );
    await session.interrupt();
    expect(r.stopCalls, 0);
  });

  test('a throwing stop() is caught; interrupt still terminates', () async {
    final r = _FakeResponder()..stopThrows = true;
    final session = VoiceSession.custom(
      recognizer: _FakeRecognizer('hi'),
      responder: r.build(),
      synthesizer: _FakeSynth(),
    );
    final events = <VoiceEvent>[];
    session.runTurn(_pcm()).listen(events.add);
    await Future<void>.delayed(Duration.zero);
    r.ctrl.add('x');
    await Future<void>.delayed(Duration.zero);
    // stop throws AND never closes ctrl → bounded drain must still terminate.
    await session.interrupt();
    expect(events.last, isA<VoiceTurnInterruptedEvent>());
  });

  test(
    'bounded drain: a stop that does not end the stream still terminates within drainTimeout',
    () {
      fakeAsync((async) {
        final ctrl = StreamController<String>();
        // F2: track whether the reply subscription gets cancelled — R1's
        // detach-not-cancel branch must leave it running.
        var cancelled = false;
        ctrl.onCancel = () {
          cancelled = true;
        };
        final responder = VoiceResponder(
          respond: (_) => ctrl.stream,
          stop: () async {}, // does NOT close the stream
        );
        final session = VoiceSession.custom(
          recognizer: _FakeRecognizer('hi'),
          responder: responder,
          synthesizer: _FakeSynth(),
        );
        final events = <VoiceEvent>[];
        session.runTurn(_pcm()).listen(events.add);
        async.flushMicrotasks();
        ctrl.add('x');
        async.flushMicrotasks();
        session.interrupt();
        async.elapse(VoiceSession.drainTimeout + const Duration(seconds: 1));
        expect(events.last, isA<VoiceTurnInterruptedEvent>());
        expect(cancelled, isFalse); // R1: detach, never cancel

        // isClosed guard: a token delivered after detach must not be
        // forwarded into the already-torn-down turn.
        final countAfter = events.length;
        ctrl.add('late');
        async.flushMicrotasks();
        expect(events.length, countAfter);
      });
    },
  );

  test(
    'a stage failure becomes a stream error (no terminal event after)',
    () async {
      final r = _FakeResponder();
      final session = VoiceSession.custom(
        recognizer: _ThrowingRecognizer(),
        responder: r.build(),
        synthesizer: _FakeSynth(),
      );
      Object? caught;
      await session.runTurn(_pcm()).forEach((_) {}).catchError((Object e) {
        caught = e;
      });
      expect(caught, isA<StateError>());
    },
  );

  test(
    'reply stream error is turn-fatal: stream error surfaces, no terminal event follows',
    () async {
      final r = _FakeResponder();
      final session = VoiceSession.custom(
        recognizer: _FakeRecognizer('hi'),
        responder: r.build(),
        synthesizer: _FakeSynth(),
      );
      final events = <VoiceEvent>[];
      Object? caught;
      final streamDone = Completer<void>();
      session
          .runTurn(_pcm())
          .listen(
            events.add,
            onError: (Object e) {
              caught = e;
              if (!streamDone.isCompleted) streamDone.complete();
            },
            onDone: () {
              if (!streamDone.isCompleted) streamDone.complete();
            },
          );
      await Future<void>.delayed(Duration.zero);
      r.ctrl.addError(StateError('llm boom'));
      await streamDone.future;

      expect(caught, isA<StateError>());
      expect(events.whereType<VoiceTurnInterruptedEvent>(), isEmpty);
      expect(events.whereType<VoiceTurnCompleteEvent>(), isEmpty);
    },
  );

  test(
    'interrupt then reply stream errors: error wins, interrupt completes without rethrowing',
    () async {
      final ctrl = StreamController<String>();
      var stopCalls = 0;
      final responder = VoiceResponder(
        respond: (_) => ctrl.stream,
        stop: () async {
          stopCalls++;
          // Does NOT close/error the stream itself — the test triggers the
          // failure separately below, while the bounded drain is pending.
        },
      );
      final session = VoiceSession.custom(
        recognizer: _FakeRecognizer('hi'),
        responder: responder,
        synthesizer: _FakeSynth(),
      );
      final events = <VoiceEvent>[];
      Object? caught;
      final streamDone = Completer<void>();
      session
          .runTurn(_pcm())
          .listen(
            events.add,
            onError: (Object e) {
              caught = e;
              if (!streamDone.isCompleted) streamDone.complete();
            },
            onDone: () {
              if (!streamDone.isCompleted) streamDone.complete();
            },
          );
      await Future<void>.delayed(Duration.zero);
      ctrl.add('par');
      await Future<void>.delayed(Duration.zero);

      final interruptFut = session.interrupt(); // stop() + bounded drain
      await Future<void>.delayed(Duration.zero); // let stop() resolve
      ctrl.addError(StateError('llm boom')); // reply stream fails mid-drain
      await interruptFut; // must complete without rethrowing
      await streamDone.future;

      expect(stopCalls, 1);
      expect(caught, isA<StateError>());
      expect(events.whereType<VoiceTurnInterruptedEvent>(), isEmpty);
      expect(events.whereType<VoiceTurnCompleteEvent>(), isEmpty);
    },
  );

  test(
    'N1: interrupt for turn A parked on a slow stop() does not block barge-in on turn B',
    () {
      fakeAsync((async) {
        // Turn A never reaches the LLM stage below (its interrupt() lands at
        // the transcript checkpoint, before responder.respond() is ever
        // called) — only turn B consumes a reply stream.
        final ctrlB = StreamController<String>();
        var respondCalls = 0;
        var stopCalls = 0;
        final stopAGate = Completer<void>();
        final responder = VoiceResponder(
          respond: (_) {
            respondCalls++;
            return ctrlB.stream;
          },
          stop: () async {
            stopCalls++;
            if (stopCalls == 1) {
              await stopAGate.future; // turn A's stop(): parks indefinitely
            }
            // Turn B's stop() (2nd call): resolves immediately and does NOT
            // close ctrlB — the bounded drain below forces turn B's terminal.
          },
        );
        final session = VoiceSession.custom(
          recognizer: _FakeRecognizer('hi'),
          responder: responder,
          synthesizer: _FakeSynth(),
        );

        // ---- Turn A: interrupt() called immediately, parks on the slow
        // stop(). Turn A picks up the interrupt at the earliest checkpoint
        // (right after transcribe(), before ever calling responder.respond())
        // and reaches its terminal while interrupt#1 is STILL parked.
        final eventsA = <VoiceEvent>[];
        session.runTurn(_pcm()).listen(eventsA.add);
        session.interrupt(); // interrupt#1 — parks on stopAGate
        async.flushMicrotasks();
        expect(stopCalls, 1);
        expect(eventsA.last, isA<VoiceTurnInterruptedEvent>());
        expect(respondCalls, 0); // never reached the LLM stage for A

        // ---- Turn B starts + barges in while interrupt#1 is still parked ----
        final eventsB = <VoiceEvent>[];
        session.runTurn(_pcm()).listen(eventsB.add);
        async.flushMicrotasks();
        ctrlB.add('partial-b');
        async.flushMicrotasks();

        session.interrupt(); // interrupt#2 — must target turn B, not no-op
        async.flushMicrotasks();
        // N1: stop() really called again for B — the barge-in was not
        // silently swallowed by a session-scoped in-flight guard.
        expect(stopCalls, 2);

        // Force turn B's bounded drain (ctrlB never closes).
        async.elapse(VoiceSession.drainTimeout + const Duration(seconds: 1));
        expect(eventsB.last, isA<VoiceTurnInterruptedEvent>());
        final itB = eventsB.last as VoiceTurnInterruptedEvent;
        expect(itB.partialReplyText, 'partial-b');

        // Release interrupt#1 so it can settle without leaking timers.
        stopAGate.complete();
        async.flushMicrotasks();
      });
    },
  );
}

class _ThrowingRecognizer implements SpeechRecognizer {
  @override
  Future<String> transcribe(Uint8List pcm) async =>
      throw StateError('stt boom');
  @override
  void addCloseListener(void Function() listener) {}
  @override
  Future<void> close() async {}
}
