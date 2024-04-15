import 'package:flutter/material.dart';
import 'package:flutter_gemma_example/chat_input_field.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/core/message.dart';
import 'package:flutter_gemma_example/gemma_input_field.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _messages = <Message>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFF0b2351),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0b2351),
          title: const Text(
            'Flutter Gemma Example',
            style: TextStyle(fontSize: 20),
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        body: Stack(children: [
          Center(
            child: Image.asset(
              'assets/background.png',
              width: 200,
              height: 200,
            ),
          ),
          Column(
            children: <Widget>[
              Flexible(
                  child: ChatListWidget(
                messages: _messages,
              )),
              const Divider(height: 1.0),
              if (_messages.isEmpty || !_messages.last.isHuman)
                ChatInputField(
                  handleSubmitted: (text) {
                    setState(() {
                      _messages.add(Message(text: text, isHuman: true));
                    });
                  },
                ),
              if (_messages.isNotEmpty && _messages.last.isHuman)
                GemmaInputField(
                    messages: _messages,
                    streamHandled: (message) {
                      setState(() {
                        _messages.add(message);
                      });
                    })
            ],
          )
        ]));
  }
}
