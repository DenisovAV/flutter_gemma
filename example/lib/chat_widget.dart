import 'package:flutter/material.dart';
import 'package:flutter_gemma_example/chat_message.dart';
import 'package:flutter_gemma_example/core/message.dart';

class ChatListWidget extends StatelessWidget {
  const ChatListWidget({super.key, required this.messages});

  final List<Message> messages;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages.reversed.toList()[index];
        return ChatMessageWidget(
          message: message,
        );
      },
    );
  }
}
