import 'dart:typed_data';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Uint8List? imageBytes; // set on a user message that attached an image

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageBytes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
