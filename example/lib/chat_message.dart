import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatMessageWidget extends StatelessWidget {
  const ChatMessageWidget({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          message.isUser ? const SizedBox() : _buildAvatar(),
          const SizedBox(
            width: 10,
          ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: const Color(0x80757575),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: message.text.isNotEmpty
                ? MarkdownBody(
                    data: message.text,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(
            width: 10,
          ),
          message.isUser ? _buildAvatar() : const SizedBox(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return message.isUser ? const Icon(Icons.person) : _circled('assets/gemma.png');
  }

  Widget _circled(String image) =>
      CircleAvatar(backgroundColor: Colors.transparent, foregroundImage: AssetImage(image));
}
