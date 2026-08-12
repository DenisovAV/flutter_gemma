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

  test('maxToolTurns < 1 throws (no silent empty-stream no-op)', () {
    final chat = _ScriptChat(const []);
    expect(
      () => chat
          .generateChatResponseWithTools(
            onToolCall: (c) => {'result': 'x'},
            maxToolTurns: 0,
          )
          .toList(),
      throwsA(isA<RangeError>()),
    );
  });

  test('onToolCall throwing balances the committed call then rethrows', () async {
    final chat = _ScriptChat([
      const [FunctionCallResponse(name: 'boom', args: {})],
    ]);
    await expectLater(
      chat
          .generateChatResponseWithTools(
            onToolCall: (c) => throw StateError('tool failed'),
          )
          .toList(),
      throwsA(isA<StateError>()),
    );
    // The committed tool-call must get a matching (error) tool-response so the
    // persistent chat is not left with a dangling call that poisons next turn.
    expect(
      chat.fedBack.where((m) => m.toolName == 'boom'),
      hasLength(1),
      reason: 'failed call must be answered to balance history',
    );
  });

  test(
    'cancel after generation balances the pending call before stopping',
    () async {
      final chat = _ScriptChat([
        const [FunctionCallResponse(name: 'a', args: {})],
        const [TextResponse('unreachable')],
      ]);
      var polls = 0;
      final out = await chat
          .generateChatResponseWithTools(
            onToolCall: (c) => {'result': 'x'},
            // false at the top-of-loop check, true right after generation — so the
            // cancel lands with a call already committed but not yet executed.
            isCancelled: () => ++polls > 1,
          )
          .toList();
      expect(out.whereType<TextResponse>(), isEmpty); // stopped, no 2nd turn
      expect(
        chat.fedBack.where((m) => m.toolName == 'a'),
        hasLength(1),
        reason: 'cancelled call must be answered to balance history',
      );
    },
  );
}
