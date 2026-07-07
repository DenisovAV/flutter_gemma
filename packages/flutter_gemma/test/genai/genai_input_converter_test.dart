import 'dart:typed_data';
import 'package:flutter_gemma/genai.dart';
import 'package:flutter_gemma/core/genai/genai_input_converter.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user text → one user Message', () async {
    final out = await messagesFromChatMessage(ChatMessage.user('hi'));
    expect(out, hasLength(1));
    expect(out.first.text, 'hi');
    expect(out.first.isUser, isTrue);
  });

  test(
    'user text + two image DataParts → one Message with both images',
    () async {
      final a = Uint8List.fromList([1]);
      final b = Uint8List.fromList([2]);
      final msg = ChatMessage.user(
        'look',
        parts: [
          TextPart('look'),
          DataPart(a, mimeType: 'image/png'),
          DataPart(b, mimeType: 'image/png'),
        ],
      );
      final out = await messagesFromChatMessage(msg);
      expect(out, hasLength(1));
      expect(out.first.images, [a, b]);
    },
  );

  test('model role → non-user Message', () async {
    final out = await messagesFromChatMessage(ChatMessage.model('ok'));
    expect(out.single.isUser, isFalse);
  });

  test('system role throws', () async {
    expect(
      () => messagesFromChatMessage(ChatMessage.system('sys')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('ThinkingPart throws', () async {
    final msg = ChatMessage(
      role: ChatMessageRole.model,
      parts: [const ThinkingPart('t')],
    );
    expect(
      () => messagesFromChatMessage(msg),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('tool result → Message.toolResponse', () async {
    final msg = ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        ToolPart.result(callId: '1', toolName: 'calc', result: {'v': 7}),
      ],
    );
    final out = await messagesFromChatMessage(msg);
    expect(out.single.type, MessageType.toolResponse);
    expect(out.single.toolName, 'calc');
  });

  test('second audio DataPart throws', () async {
    final msg = ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        DataPart(Uint8List.fromList([1]), mimeType: 'audio/wav'),
        DataPart(Uint8List.fromList([2]), mimeType: 'audio/wav'),
      ],
    );
    expect(
      () => messagesFromChatMessage(msg),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('empty parts throws', () async {
    final msg = ChatMessage(role: ChatMessageRole.user, parts: const []);
    expect(() => messagesFromChatMessage(msg), throwsA(isA<ArgumentError>()));
  });

  test('tool call in a user-role message throws', () async {
    final msg = ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        ToolPart.call(callId: '1', toolName: 'calc', arguments: {'a': 1}),
      ],
    );
    expect(
      () => messagesFromChatMessage(msg),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('non-media DataPart mime throws', () async {
    final msg = ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        DataPart(Uint8List.fromList([1, 2]), mimeType: 'application/pdf'),
      ],
    );
    expect(
      () => messagesFromChatMessage(msg),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
