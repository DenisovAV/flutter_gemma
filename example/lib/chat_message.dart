import 'package:flutter/material.dart';
import 'package:flutter_gemma_example/core/message.dart';

class ChatMessageWidget extends StatelessWidget {
  const ChatMessageWidget({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment:
            message.isHuman ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          message.isHuman ? const SizedBox() : _buildAvatar(),
          const SizedBox(
            width: 10,
          ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: const Color(0x80757575),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: message.text.isNotEmpty
                ? Text(
                    message.text,
                    style: const TextStyle(fontSize: 16.0),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(
            width: 10,
          ),
          message.isHuman ? _buildAvatar() : const SizedBox(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return message.isHuman
        ? const Icon(Icons.person)
        : _circled('assets/gemma.png');
  }

  Widget _circled(String image) => CircleAvatar(
      backgroundColor: Colors.transparent, foregroundImage: AssetImage(image));
}
