import 'dart:typed_data';

import 'package:flutter_gemma/core/ffi/ffi_inference_model.dart';
import 'package:flutter_gemma/core/ffi/litert_lm_client.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [ConversationHandle] that echoes scripted responses without touching
/// native code. Each fake owns its own response script, so two fakes model
/// two isolated conversations — exactly the property multi-session must
/// preserve. Mirrors the injectable-fake pattern from
/// `backend_preference_test.dart` (PR #288).
class _FakeConversationHandle implements ConversationHandle {
  _FakeConversationHandle(this._scriptedChunks);

  /// Chunks this handle yields on each chat()/chatRaw() call.
  final List<String> _scriptedChunks;

  bool isClosed = false;
  int cancelCount = 0;

  @override
  Stream<String> chat(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) async* {
    for (final c in _scriptedChunks) {
      yield c;
    }
  }

  @override
  Stream<String> chatRaw(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) async* {
    // Raw chunks are full JSON documents in the real path; the fake yields
    // OpenAI-shaped text-content JSON so SdkTextExtractor can pull text out.
    for (final c in _scriptedChunks) {
      yield '{"role":"assistant","content":[{"type":"text","text":"$c"}]}';
    }
  }

  @override
  void cancelGeneration() => cancelCount++;

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  void close() => isClosed = true;
}

void main() {
  group('FfiInferenceModelSession with fake handle', () {
    test('routes getResponse through its own handle (non-Gemma4)', () async {
      final handle = _FakeConversationHandle(['Hello', ' world']);
      final session = FfiInferenceModelSession(
        handle: handle,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );

      await session.addQueryChunk(const Message(text: 'hi', isUser: true));
      final response = await session.getResponse();

      expect(response, 'Hello world');
      // Non-Gemma4 path keeps the raw cache null.
      expect(session.lastRawResponse, isNull);
    });

    test('captures raw response for Gemma 4 tool-call path', () async {
      final handle = _FakeConversationHandle(['Hi']);
      final session = FfiInferenceModelSession(
        handle: handle,
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );

      await session.addQueryChunk(const Message(text: 'hi', isUser: true));
      final response = await session.getResponse();

      // Text extracted from the JSON chunk.
      expect(response, 'Hi');
      // Raw JSON captured so chat.dart can run extractToolCalls.
      expect(session.lastRawResponse, contains('"type":"text"'));
      expect(session.lastRawResponse, contains('Hi'));
    });

    test('two sessions with distinct handles produce isolated outputs',
        () async {
      final handleA = _FakeConversationHandle(['I am A']);
      final handleB = _FakeConversationHandle(['I am B']);

      final sessionA = FfiInferenceModelSession(
        handle: handleA,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );
      final sessionB = FfiInferenceModelSession(
        handle: handleB,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );

      await sessionA.addQueryChunk(const Message(text: 'q', isUser: true));
      await sessionB.addQueryChunk(const Message(text: 'q', isUser: true));

      final respA = await sessionA.getResponse();
      final respB = await sessionB.getResponse();

      expect(respA, 'I am A');
      expect(respB, 'I am B');
    });

    test('close() closes only this session\'s handle and fires onClose',
        () async {
      final handleA = _FakeConversationHandle(['a']);
      final handleB = _FakeConversationHandle(['b']);
      var onCloseACalled = false;

      final sessionA = FfiInferenceModelSession(
        handle: handleA,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () => onCloseACalled = true,
      );
      final sessionB = FfiInferenceModelSession(
        handle: handleB,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );

      await sessionA.close();

      expect(handleA.isClosed, isTrue);
      expect(handleB.isClosed, isFalse, reason: 'B must survive A.close()');
      expect(onCloseACalled, isTrue);
      // B is still usable after A closed.
      await sessionB.addQueryChunk(const Message(text: 'q', isUser: true));
      expect(await sessionB.getResponse(), 'b');
    });

    test('methods throw StateError after close', () async {
      final session = FfiInferenceModelSession(
        handle: _FakeConversationHandle(['x']),
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );

      await session.close();

      expect(
        () => session.addQueryChunk(const Message(text: 'q', isUser: true)),
        throwsStateError,
      );
    });

    test('stopGeneration cancels via the handle', () async {
      final handle = _FakeConversationHandle(['x']);
      final session = FfiInferenceModelSession(
        handle: handle,
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        supportImage: false,
        supportAudio: false,
        onClose: () {},
      );

      await session.stopGeneration();

      expect(handle.cancelCount, 1);
    });
  });

  group('FfiInferenceModel maxConcurrentSessions cap', () {
    test('openSession throws StateError when cap is reached', () async {
      // cap=0 means the very first openSession exceeds the cap. The check
      // runs before any native call, so a bare (uninitialized) client never
      // gets touched. Proves the cap gates openSession.
      final model = FfiInferenceModel(
        ffiClient: LiteRtLmFfiClient(),
        maxTokens: 256,
        modelType: ModelType.gemmaIt,
        activeBackend: null,
        maxConcurrentSessions: 0,
        onClose: () {},
      );

      await expectLater(
        model.openSession(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Max concurrent sessions (0)'),
          ),
        ),
      );
    });

    test('null cap imposes no limit on openSession gate', () {
      // With no cap, the cap check never trips. We can't drive the native
      // path here, but constructing with a null cap and reading the field
      // confirms the default is unlimited (backward-compatible).
      final model = FfiInferenceModel(
        ffiClient: LiteRtLmFfiClient(),
        maxTokens: 256,
        modelType: ModelType.gemmaIt,
        activeBackend: null,
        onClose: () {},
      );

      expect(model.maxConcurrentSessions, isNull);
    });
  });
}
