import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptChat extends InferenceChat {
  _ScriptChat(this._turns) : super(sessionCreator: null, maxTokens: 1024);
  final List<List<ModelResponse>> _turns;
  int _i = 0;
  final List<Message> fedBack = [];

  @override
  Future<void> addQueryChunk(
    Message m, [
    bool noTool = false,
    bool prefix = false,
  ]) async {
    fedBack.add(m);
  }

  @override
  Stream<ModelResponse> generateChatResponseAsync() async* {
    final turn = _i < _turns.length
        ? _turns[_i++]
        : const <ModelResponse>[TextResponse('done')];
    for (final r in turn) {
      yield r;
    }
  }

  @override
  Future<void> stopGeneration() async {}
  @override
  Future<void> close() async {}
}

void main() {
  test(
    'runs onToolCall, feeds Message.toolResponse back, yields the final text',
    () async {
      final chat = _ScriptChat([
        const [
          FunctionCallResponse(name: 'get_time', args: {'tz': 'CST'}),
        ],
        const [TextResponse("It's "), TextResponse('9pm.')],
      ]);
      final calls = <FunctionCallResponse>[];
      final out = await chat
          .generateChatResponseWithTools(
            onToolCall: (c) {
              calls.add(c);
              return {'result': '9pm', 'status': 'ok'};
            },
          )
          .toList();

      expect(calls.single.name, 'get_time');
      expect(
        out.whereType<TextResponse>().map((t) => t.token).join(),
        "It's 9pm.",
      );
      expect(chat.fedBack.where((m) => m.toolName == 'get_time'), hasLength(1));
    },
  );

  test('parallel calls each get a tool response, in order', () async {
    final chat = _ScriptChat([
      const [
        ParallelFunctionCallResponse(
          calls: [
            FunctionCallResponse(name: 'a', args: {}),
            FunctionCallResponse(name: 'b', args: {}),
          ],
        ),
      ],
      const [TextResponse('ok')],
    ]);
    final names = <String>[];
    await chat
        .generateChatResponseWithTools(
          onToolCall: (c) {
            names.add(c.name);
            return {'result': 'x'};
          },
        )
        .toList();
    expect(names, ['a', 'b']);
  });

  test('isCancelled ends the loop before the next generation', () async {
    final chat = _ScriptChat([
      const [FunctionCallResponse(name: 'a', args: {})],
      const [TextResponse('unreachable')],
    ]);
    var cancel = false;
    final out = await chat
        .generateChatResponseWithTools(
          onToolCall: (c) {
            cancel = true;
            return {'result': 'x'};
          },
          isCancelled: () => cancel,
        )
        .toList();
    expect(out.whereType<TextResponse>(), isEmpty);
  });

  test('maxToolTurns caps a runaway loop', () async {
    final chat = _ScriptChat(
      List.filled(50, const [FunctionCallResponse(name: 'a', args: {})]),
    );
    var n = 0;
    await chat
        .generateChatResponseWithTools(
          onToolCall: (c) {
            n++;
            return {'result': 'x'};
          },
          maxToolTurns: 3,
        )
        .toList();
    expect(n, 3);
  });
}
