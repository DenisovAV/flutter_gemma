import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart'
    show
        InferenceChat,
        ModelResponse,
        SpeechRecognizer,
        SpeechSynthesizer,
        TextResponse,
        ThinkingResponse,
        FunctionCallResponse,
        Tool;
import 'package:flutter_gemma_speech/src/voice/voice_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopRecognizer implements SpeechRecognizer {
  @override
  Future<String> transcribe(Uint8List pcm) async => '';
  @override
  void addCloseListener(void Function() l) {}
  @override
  Future<void> close() async {}
}

class _NoopSynth implements SpeechSynthesizer {
  @override
  int get sampleRate => 22050;
  @override
  Future<Uint8List> synthesize(String t) async => Uint8List(0);
  @override
  void addCloseListener(void Function() l) {}
  @override
  Future<void> close() async {}
}

void main() {
  test('fromChat with a tools-chat but no onToolCall throws', () {
    final chatWithTools = InferenceChat(
      sessionCreator: null,
      maxTokens: 1024,
      tools: const [Tool(name: 'noop', description: 'noop')],
    );
    expect(
      () => VoiceSession.fromChat(
        recognizer: _NoopRecognizer(),
        chat: chatWithTools,
        synthesizer: _NoopSynth(),
      ),
      throwsArgumentError,
    );
  });

  test('fromChat with a tools-chat AND onToolCall builds a session', () {
    final chatWithTools = InferenceChat(
      sessionCreator: null,
      maxTokens: 1024,
      tools: const [Tool(name: 'noop', description: 'noop')],
    );
    final session = VoiceSession.fromChat(
      recognizer: _NoopRecognizer(),
      chat: chatWithTools,
      synthesizer: _NoopSynth(),
      onToolCall: (c) async => {'result': 'ok'},
    );
    expect(session, isA<VoiceSession>());
  });

  test('fromChat builds a session when the chat is tools-free', () {
    final chat = InferenceChat(sessionCreator: null, maxTokens: 1024);
    final session = VoiceSession.fromChat(
      recognizer: _NoopRecognizer(),
      chat: chat,
      synthesizer: _NoopSynth(),
    );
    expect(session, isA<VoiceSession>());
    expect(session.replySampleRate, 22050);
  });

  test('textTokensOf keeps only TextResponse tokens, in order', () async {
    Stream<ModelResponse> responses() async* {
      yield const ThinkingResponse('...thinking...');
      yield const TextResponse('Hello');
      yield const FunctionCallResponse(name: 'x', args: {});
      yield const TextResponse(' world');
    }

    final tokens = await VoiceSession.textTokensOf(responses()).toList();
    expect(tokens, ['Hello', ' world']);
  });
}
