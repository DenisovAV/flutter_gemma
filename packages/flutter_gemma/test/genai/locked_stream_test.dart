import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/genai.dart';
import 'package:flutter_test/flutter_test.dart';

/// A no-engine [InferenceChat] whose staging (addQueryChunk) and generation
/// (generateChatResponseAsync) are driven by the test, so `_lockedStream`'s
/// mutex/cancel state machine can be exercised deterministically.
class _FakeChat extends InferenceChat {
  _FakeChat() : super(sessionCreator: null, maxTokens: 1024);

  Duration stageDelay = Duration.zero;
  final staged = <String>[];
  int stopGenerationCalls = 0;
  StreamController<ModelResponse>? lastGen;

  @override
  Future<void> addQueryChunk(
    Message message, [
    bool noTool = false,
    bool prefix = false,
  ]) async {
    if (stageDelay > Duration.zero) await Future<void>.delayed(stageDelay);
    staged.add(message.text);
  }

  @override
  Stream<ModelResponse> generateChatResponseAsync() {
    final c = StreamController<ModelResponse>();
    lastGen = c;
    return c.stream;
  }

  @override
  Future<void> stopGeneration() async {
    stopGenerationCalls++;
  }
}

String _text(ChatMessage m) =>
    m.parts.whereType<TextPart>().map((p) => p.text).join();

void main() {
  test(
    'cancel during stage keeps the lock held until stage() finishes',
    () async {
      // The C1 bug: onCancel releases the mutex mid-stage, while stage() is still
      // mutating shared session state — so a second turn can interleave.
      final chat = _FakeChat()..stageDelay = const Duration(milliseconds: 120);
      final sub = chat.sendMessageStream(ChatMessage.user('hi')).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(chat.genaiLock.isLocked, isTrue, reason: 'lock held during stage');

      await sub.cancel(); // cancel while stage() still has ~100ms to run
      expect(
        chat.genaiLock.isLocked,
        isTrue,
        reason: 'lock must NOT be released mid-stage',
      );

      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(
        chat.genaiLock.isLocked,
        isFalse,
        reason: 'lock released once stage() completes',
      );
    },
  );

  test(
    'a queued turn cancelled before acquiring never stages (no lock theft)',
    () async {
      // C1 variant: a stream cancelled while queued on acquire() must not
      // release() the lock the running turn owns. If it did, this turn would be
      // granted the stolen lock and proceed to stage() — an empty `staged`
      // proves it stayed queued and never ran a critical section.
      final chat = _FakeChat();
      await chat.genaiLock
          .acquire(); // turn A holds the lock, does nothing else

      final sub = chat.sendMessageStream(ChatMessage.user('B')).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20)); // B queued
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        chat.staged,
        isEmpty,
        reason: 'a queued+cancelled turn must not steal the lock and stage',
      );
      expect(chat.genaiLock.isLocked, isTrue, reason: 'A still holds the lock');
    },
  );

  test(
    'normal completion yields mapped chunks and releases the lock',
    () async {
      final chat = _FakeChat();
      final chunks = <ChatMessage>[];
      final done = Completer<void>();
      chat
          .sendMessageStream(ChatMessage.user('hi'))
          .listen(chunks.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      chat.lastGen!.add(const TextResponse('a'));
      chat.lastGen!.add(const TextResponse('b'));
      await chat.lastGen!.close();
      await done.future;

      expect(chunks.map(_text).toList(), ['a', 'b']);
      expect(chat.genaiLock.isLocked, isFalse, reason: 'lock released on done');
    },
  );

  test(
    'error mid-stream forwards it, stops generation, releases the lock',
    () async {
      final chat = _FakeChat();
      Object? err;
      final done = Completer<void>();
      chat
          .sendMessageStream(ChatMessage.user('hi'))
          .listen(
            (_) {},
            onError: (Object e) => err = e,
            onDone: done.complete,
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      chat.lastGen!.addError(StateError('boom'));
      await done.future;

      expect(err, isA<StateError>());
      expect(chat.stopGenerationCalls, greaterThan(0));
      expect(
        chat.genaiLock.isLocked,
        isFalse,
        reason: 'lock released on error',
      );
    },
  );

  test('cancel during generation stops it and releases the lock', () async {
    final chat = _FakeChat();
    final sub = chat.sendMessageStream(ChatMessage.user('hi')).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    chat.lastGen!.add(const TextResponse('a')); // generation is live
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await sub.cancel();
    expect(chat.stopGenerationCalls, greaterThan(0));
    expect(chat.genaiLock.isLocked, isFalse, reason: 'lock released on cancel');
  });
}
