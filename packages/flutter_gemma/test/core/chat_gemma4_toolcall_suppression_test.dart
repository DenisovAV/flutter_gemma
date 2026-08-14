import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// The LiteRT-LM C++ runtime streams a Gemma 4 tool-call turn as the raw
/// OpenAI-style `{"role":"assistant","tool_calls":[...]}` JSON (one or more
/// concatenated objects) AND exposes the same JSON via `lastRawResponse`.
///
/// Those raw JSON tokens are protocol, not answer text — they must never reach
/// the text channel (the agent's `TextChunkEvent`, or voice synthesis).
/// Regression from the token-streaming path: the SDK-passthrough format reports
/// "no function call in text", so the funcBuffer never suppressed the JSON and
/// it leaked token-by-token into the UI (tester screenshot). The structured
/// call is still surfaced from `lastRawResponse` at end-of-stream.
class _SdkSession implements InferenceModelSession, RawSdkResponseSession {
  _SdkSession(this.tokens, this.raw);

  final List<String> tokens;
  final String? raw;

  @override
  String? get lastRawResponse => raw;

  @override
  Future<void> addQueryChunk(Message message) async {}
  @override
  Future<String> getResponse() async => tokens.join();
  @override
  Stream<String> getResponseAsync() => Stream.fromIterable(tokens);
  @override
  Future<int> sizeInTokens(String text) async => text.length ~/ 4;
  @override
  Future<void> stopGeneration() async {}
  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();
  @override
  Future<void> close() async {}
}

InferenceChat _gemma4Chat(List<String> tokens, {String? raw}) => InferenceChat(
  sessionCreator: () async => _SdkSession(tokens, raw),
  maxTokens: 1024,
  modelType: ModelType.gemma4,
  supportsFunctionCalls: true,
  tools: [
    const Tool(
      name: 'runIntent',
      description: 'run an intent',
      parameters: {
        'type': 'object',
        'properties': {
          'intent': {'type': 'string', 'description': 'intent'},
        },
      },
    ),
  ],
);

Future<List<ModelResponse>> _streamGemma4(
  List<String> tokens, {
  String? raw,
}) async {
  final chat = _gemma4Chat(tokens, raw: raw);
  await chat.initSession();
  await chat.addQuery(const Message(text: 'hi', isUser: true));
  return chat.generateChatResponseAsync().toList();
}

void main() {
  test(
    'a Gemma 4 tool-call JSON turn never leaks into the text channel',
    () async {
      const raw =
          '{"role":"assistant","tool_calls":[{"type":"function","function":'
          '{"name":"runIntent","arguments":{"intent":"get_current_time"}}}]}';
      // The SDK streams the JSON as text tokens...
      final responses = await _streamGemma4(
        const [
          '{"role":"assistant",',
          '"tool_calls":[{"type":"function",',
          '"function":{"name":"runIntent",',
          '"arguments":{"intent":"get_current_time"}}}]}',
        ],
        raw: raw, // ...and exposes the same JSON via lastRawResponse.
      );

      expect(
        responses.whereType<TextResponse>().map((t) => t.token).join(),
        isEmpty,
        reason: 'raw tool-call JSON must not reach the user as text',
      );
      final calls = responses.whereType<FunctionCallResponse>().toList();
      expect(calls, hasLength(1));
      expect(calls.single.name, 'runIntent');
      expect(calls.single.args['intent'], 'get_current_time');
    },
  );

  test(
    'parallel Gemma 4 calls (concatenated JSON) suppress text, surface all',
    () async {
      // Exactly the tester's screenshot: two back-to-back tool_calls objects.
      const raw =
          '{"role":"assistant","tool_calls":[{"type":"function","function":'
          '{"name":"runIntent","arguments":{"intent":"get_current_time"}}}]}'
          '{"role":"assistant","tool_calls":[{"type":"function","function":'
          '{"name":"runIntent","arguments":{"intent":"get_current_date_and_time"}}}]}';
      // Streamed as one blob token (the whole turn), same content in lastRawResponse.
      final responses = await _streamGemma4(const [raw], raw: raw);

      expect(
        responses.whereType<TextResponse>(),
        isEmpty,
        reason: 'no part of the concatenated tool-call JSON may reach the user',
      );
      final parallel = responses
          .whereType<ParallelFunctionCallResponse>()
          .toList();
      expect(parallel, hasLength(1));
      expect(parallel.single.calls.map((c) => c.args['intent']).toList(), [
        'get_current_time',
        'get_current_date_and_time',
      ]);
    },
  );

  test('a Gemma 4 plain-text reply still streams token-by-token', () async {
    // No tool call → lastRawResponse is null. Plain natural language must NOT be
    // suppressed and must keep its streaming granularity.
    final responses = await _streamGemma4(const [
      'The ',
      'current ',
      'time ',
      'is ',
      '9pm.',
    ], raw: null);

    final text = responses
        .whereType<TextResponse>()
        .map((t) => t.token)
        .toList();
    expect(text.join(), 'The current time is 9pm.');
    expect(text.length, greaterThan(1), reason: 'token-by-token preserved');
    expect(responses.whereType<FunctionCallResponse>(), isEmpty);
  });

  test(
    'a suppressed JSON stream with no parseable call degrades to text',
    () async {
      // Defensive: a `{`-leading blob whose lastRawResponse yields no tool_calls
      // must NOT be silently dropped — surface it as text (pre-fix behavior).
      const blob = '{"weird":"shape","no":"tool_calls"}';
      final responses = await _streamGemma4(const [blob], raw: blob);

      expect(responses.whereType<FunctionCallResponse>(), isEmpty);
      expect(
        responses.whereType<TextResponse>().map((t) => t.token).join(),
        blob,
        reason: 'must not silently drop model output',
      );
    },
  );

  test(
    'leading whitespace before the tool-call JSON is still suppressed',
    () async {
      // Chat templates often prepend a newline/space before the JSON — the probe
      // classifies on the first NON-whitespace char, so this must still swallow.
      const raw =
          '{"role":"assistant","tool_calls":[{"type":"function","function":'
          '{"name":"runIntent","arguments":{"intent":"x"}}}]}';
      final responses = await _streamGemma4(const [
        '\n', // whitespace-only tokens: deferred classification (keep probing)
        '  ',
        '{"role":"assistant",',
        '"tool_calls":[{"type":"function","function":'
            '{"name":"runIntent","arguments":{"intent":"x"}}}]}',
      ], raw: raw);

      expect(
        responses.whereType<TextResponse>(),
        isEmpty,
        reason: 'leading whitespace + the JSON are both suppressed',
      );
      final calls = responses.whereType<FunctionCallResponse>().toList();
      expect(calls, hasLength(1));
      expect(calls.single.args['intent'], 'x');
    },
  );

  test('leading whitespace before a plain-text reply is preserved', () async {
    // Same deferred-classification path, but the first non-whitespace char is
    // NOT '{' → plain text. The probed leading whitespace must survive.
    final responses = await _streamGemma4(const [
      '  ',
      'Hello ',
      'world',
    ], raw: null);

    expect(
      responses.whereType<TextResponse>().map((t) => t.token).join(),
      '  Hello world',
    );
    expect(responses.whereType<FunctionCallResponse>(), isEmpty);
  });

  test(
    'a suppressed JSON stream with a NULL lastRawResponse degrades to text',
    () async {
      // Distinct branch from the non-null-but-empty case above: the end-of-stream
      // `if (raw != null)` guard is skipped entirely, so only the safety net can
      // surface the output. A partial/aborted turn must not be silently dropped.
      const blob = '{"role":"assistant","tool_calls":[]}';
      final responses = await _streamGemma4(const [blob], raw: null);

      expect(responses.whereType<FunctionCallResponse>(), isEmpty);
      expect(
        responses.whereType<TextResponse>().map((t) => t.token).join(),
        blob,
        reason: 'must not silently drop output when lastRawResponse is null',
      );
    },
  );

  test('a suppressed tool-call turn is recorded in chat history', () async {
    // The tool-call must land in history (before the caller's tool-response), or
    // the response is orphaned and corrupts replayed history on session rotation
    // — the reason the end-of-stream block records it explicitly.
    const raw =
        '{"role":"assistant","tool_calls":[{"type":"function","function":'
        '{"name":"runIntent","arguments":{"intent":"x"}}}]}';
    final chat = _gemma4Chat(const [raw], raw: raw);
    await chat.initSession();
    await chat.addQuery(const Message(text: 'hi', isUser: true));
    await chat.generateChatResponseAsync().toList();

    final toolCalls = chat.fullHistory.where(
      (m) => m.type == MessageType.toolCall,
    );
    expect(toolCalls, hasLength(1));
  });

  test(
    'a whitespace-only reply is flushed at end of stream, not dropped',
    () async {
      // The stream ends while still unclassified (only whitespace tokens seen), so
      // neither the swallow nor the tool-call block fires — the end-of-stream flush
      // is the SOLE guard against silently dropping this output.
      final responses = await _streamGemma4(const ['  ', '\n'], raw: null);

      expect(responses.whereType<FunctionCallResponse>(), isEmpty);
      expect(
        responses.whereType<TextResponse>().map((t) => t.token).join(),
        '  \n',
        reason: 'whitespace-only reply must be flushed, not swallowed',
      );
    },
  );
}
