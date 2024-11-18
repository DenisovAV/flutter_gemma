import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_input_field.dart';
import 'package:flutter_gemma_example/chat_message.dart';
import 'package:flutter_gemma_example/gemma_input_field.dart';

class ChatListWidget extends StatelessWidget {
  const ChatListWidget({
    required this.messages,
    required this.gemmaHandler,
    required this.humanHandler,
    required this.errorHandler,
    super.key,
  });

  final List<Message> messages;
  final ValueChanged<Message> gemmaHandler;
  final ValueChanged<String> humanHandler;
  final ValueChanged<String> errorHandler;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      reverse: true,
      itemCount: messages.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          if (messages.isNotEmpty && messages.last.isUser) {
            return GemmaInputField(
              messages: messages,
              streamHandler: gemmaHandler,
              errorHandler: errorHandler,
            );
          }
          if (messages.isEmpty || !messages.last.isUser) {
            return ChatInputField(handleSubmitted: humanHandler);
          }
        } else if (index == 1) {
          return const Divider(height: 1.0);
        } else {
          final message = messages.reversed.toList()[index - 2];
          return ChatMessageWidget(
            message: message,
          );
        }
        return null;
      },
    );
  }
}
