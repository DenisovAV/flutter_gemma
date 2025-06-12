import 'dart:typed_data';
import 'package:flutter_gemma/core/model.dart';

class Message {
  const Message({
    required this.text,
    this.isUser = false,
    this.imageBytes,
  });

  final String text;
  final bool isUser;
  final Uint8List? imageBytes;

  bool get hasImage => imageBytes != null;

  Message copyWith({
    String? text,
    bool? isUser,
    Uint8List? imageBytes,
  }) {
    return Message(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }

  factory Message.text({
    required String text,
    bool isUser = false,
  }) {
    return Message(
      text: text,
      isUser: isUser,
    );
  }

  factory Message.withImage({
    required String text,
    required Uint8List imageBytes,
    bool isUser = false,
  }) {
    return Message(
      text: text,
      imageBytes: imageBytes,
      isUser: isUser,
    );
  }

  factory Message.imageOnly({
    required Uint8List imageBytes,
    bool isUser = false,
    String text = '',
  }) {
    return Message(
      text: text,
      imageBytes: imageBytes,
      isUser: isUser,
    );
  }

  String transformToChatPrompt({required ModelType type}) {
    return text;
  }

  @override
  String toString() {
    return 'Message(text: $text, isUser: $isUser, hasImage: $hasImage)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message &&
        other.text == text &&
        other.isUser == isUser &&
        _listEquals(other.imageBytes, imageBytes);
  }

  @override
  int get hashCode => text.hashCode ^ isUser.hashCode ^ imageBytes.hashCode;

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}