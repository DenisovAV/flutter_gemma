import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma_builtin_ai/pigeon.g.dart';
import 'package:flutter_gemma_builtin_ai/src/builtin_ai_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _prefix = 'dev.flutter.pigeon.flutter_gemma_builtin_ai.BuiltInAiService';
const _streamChannel = 'flutter_gemma_builtin_ai_stream';

void _mockHost(String method, List<Object?> Function(Object? args) reply) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('$_prefix.$method', (ByteData? message) async {
        final args = BuiltInAiService.pigeonChannelCodec.decodeMessage(message);
        return BuiltInAiService.pigeonChannelCodec.encodeMessage(reply(args));
      });
}

void _clearHost(String method) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('$_prefix.$method', null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methods = [
    'addQueryChunk',
    'addImage',
    'generateResponse',
    'generateResponseAsync',
    'countTokens',
    'closeSession',
    'stopGeneration',
  ];

  tearDown(() {
    for (final m in methods) {
      _clearHost(m);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel(_streamChannel), null);
  });

  BuiltInAiSession newSession({int sessionId = 1, bool supportImage = false}) {
    return BuiltInAiSession(
      sessionId: sessionId,
      service: BuiltInAiService(),
      modelType: ModelType.general,
      fileType: ModelFileType.builtIn,
      supportImage: supportImage,
      onClose: () {},
    );
  }

  test('getResponse returns the host string', () async {
    _mockHost('generateResponse', (_) => ['Hello from Nano']);
    final session = newSession();
    expect(await session.getResponse(), 'Hello from Nano');
  });

  test('getResponseAsync yields partials, filters foreign sessionId, closes on '
      'done', () async {
    _mockHost('generateResponseAsync', (_) => [null]);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel(_streamChannel),
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              // Foreign session — must be ignored.
              events.success({
                'partialResult': 'X',
                'done': false,
                'sessionId': 99,
              });
              events.success({
                'partialResult': 'Hel',
                'done': false,
                'sessionId': 1,
              });
              events.success({
                'partialResult': 'lo',
                'done': false,
                'sessionId': 1,
              });
              // Completion tagged for our session.
              events.success({
                'partialResult': '',
                'done': true,
                'sessionId': 1,
              });
            },
          ),
        );

    final session = newSession();
    final chunks = await session.getResponseAsync().toList();
    expect(chunks, ['Hel', 'lo']);
  });

  test('ERROR data event surfaces as a stream error', () async {
    _mockHost('generateResponseAsync', (_) => [null]);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel(_streamChannel),
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events.success({
                'code': 'ERROR',
                'message': 'boom',
                'sessionId': 1,
              });
            },
          ),
        );

    final session = newSession();
    await expectLater(session.getResponseAsync(), emitsError(isA<Exception>()));
  });

  test('sizeInTokens returns the host value', () async {
    _mockHost('countTokens', (_) => [42]);
    final session = newSession();
    expect(await session.sizeInTokens('some text'), 42);
  });

  test('sizeInTokens falls back to (len/4).ceil() when host throws', () async {
    _mockHost('countTokens', (_) => ['UNAVAILABLE', 'not supported', null]);
    final session = newSession();
    // 'abcdefg' -> 7 chars -> ceil(7/4) = 2
    expect(await session.sizeInTokens('abcdefg'), 2);
  });

  test(
    'addQueryChunk with an image Message calls addImage then addQueryChunk',
    () async {
      final calls = <String>[];
      _mockHost('addImage', (_) {
        calls.add('addImage');
        return [null];
      });
      _mockHost('addQueryChunk', (_) {
        calls.add('addQueryChunk');
        return [null];
      });

      final session = newSession(supportImage: true);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await session.addQueryChunk(
        Message.withImage(text: 'describe', imageBytes: bytes, isUser: true),
      );

      expect(calls, ['addImage', 'addQueryChunk']);
    },
  );
}
