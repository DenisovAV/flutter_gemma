import 'dart:typed_data';
import 'package:flutter_gemma/core/genai/genai_input_converter.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image on a non-vision chat throws', () {
    final msgs = [
      Message.withImage(
        text: 'x',
        imageBytes: Uint8List.fromList([1]),
        isUser: true,
      ),
    ];
    expect(
      () => assertMessagesFitChat(
        msgs,
        supportImage: false,
        supportAudio: true,
        supportsFunctionCalls: true,
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('audio on a non-audio chat throws', () {
    final msgs = [
      Message.withAudio(
        text: 'x',
        audioBytes: Uint8List.fromList([1]),
        isUser: true,
      ),
    ];
    expect(
      () => assertMessagesFitChat(
        msgs,
        supportImage: true,
        supportAudio: false,
        supportsFunctionCalls: true,
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('capable chat passes', () {
    final msgs = [Message(text: 'x', isUser: true)];
    assertMessagesFitChat(
      msgs,
      supportImage: true,
      supportAudio: true,
      supportsFunctionCalls: true,
    );
  });
}
