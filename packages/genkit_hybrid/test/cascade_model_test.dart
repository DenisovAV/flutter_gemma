import 'dart:async';

import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/src/cascade_model.dart';
import 'package:test/test.dart';

// A real Model that returns [text], optionally throwing (transient) first.
Model _model(String name, {String text = 'ok', bool throwFirst = false}) =>
    Model(
      name: name,
      fn: (request, context) async {
        if (throwFirst) throw Exception('$name unavailable');
        return ModelResponse(
          finishReason: FinishReason.stop,
          message: Message(
            role: Role.model,
            content: [TextPart(text: text)],
          ),
        );
      },
    );

// A minimal non-streaming Genkit context record (matches Model.fn's context).
final _blockingCtx = (
  streamingRequested: false,
  sendChunk: (ModelResponseChunk _) {},
  context: <String, dynamic>{},
  inputStream: null,
  init: null,
);

ModelRequest _req() => ModelRequest(messages: []);

void main() {
  test('accept on first -> no escalation', () async {
    final m = cascadeModel(
      branches: {
        'a': _model('a', text: 'A'),
        'b': _model('b', text: 'B'),
      },
      order: ['a', 'b'],
      accept: (r) => true,
    );
    final resp = await m.fn(_req(), _blockingCtx);
    expect(resp.text, 'A');
  });

  test('reject first -> escalate and return second', () async {
    final m = cascadeModel(
      branches: {
        'a': _model('a', text: 'A'),
        'b': _model('b', text: 'B'),
      },
      order: ['a', 'b'],
      accept: (r) => r.text == 'B',
    );
    final resp = await m.fn(_req(), _blockingCtx);
    expect(resp.text, 'B');
  });

  test('reject all -> last response returned anyway', () async {
    final m = cascadeModel(
      branches: {
        'a': _model('a', text: 'A'),
        'b': _model('b', text: 'B'),
      },
      order: ['a', 'b'],
      accept: (r) => false,
    );
    final resp = await m.fn(_req(), _blockingCtx);
    expect(resp.text, 'B');
  });

  test('transient error mid-cascade -> next branch', () async {
    final m = cascadeModel(
      branches: {
        'a': _model('a', throwFirst: true),
        'b': _model('b', text: 'B'),
      },
      order: ['a', 'b'],
      accept: (r) => true,
    );
    final resp = await m.fn(_req(), _blockingCtx);
    expect(resp.text, 'B');
  });

  test('async accept is awaited', () async {
    final m = cascadeModel(
      branches: {
        'a': _model('a', text: 'A'),
        'b': _model('b', text: 'B'),
      },
      order: ['a', 'b'],
      accept: (r) async {
        await Future<void>.delayed(Duration.zero);
        return r.text == 'B';
      },
    );
    final resp = await m.fn(_req(), _blockingCtx);
    expect(resp.text, 'B');
  });

  test('construction validation throws ArgumentError', () {
    expect(
      () => cascadeModel(branches: {}, order: ['a'], accept: (_) => true),
      throwsArgumentError,
    );
    expect(
      () => cascadeModel(
        branches: {'a': _model('a')},
        order: [],
        accept: (_) => true,
      ),
      throwsArgumentError,
    );
    expect(
      () => cascadeModel(
        branches: {'a': _model('a')},
        order: ['x'],
        accept: (_) => true,
      ),
      throwsArgumentError,
    );
  });

  test('streaming caller gets one final chunk (non-streaming v1)', () async {
    final received = <String>[];
    final streamingCtx = (
      streamingRequested: true,
      sendChunk: (ModelResponseChunk c) =>
          received.add(c.content.first.text ?? ''),
      context: <String, dynamic>{},
      inputStream: null,
      init: null,
    );
    final m = cascadeModel(
      branches: {'a': _model('a', text: 'A')},
      order: ['a'],
      accept: (r) => true,
    );
    final resp = await m.fn(_req(), streamingCtx);
    expect(resp.text, 'A');
    expect(received, ['A']); // exactly one chunk = the final response
  });
}
