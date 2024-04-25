import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma_example/chat_input_field.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/core/message.dart';
import 'package:flutter_gemma_example/gemma_input_field.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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
          FutureBuilder(
            future: FlutterGemmaPlugin.instance.isInitialized,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.waiting && snapshot.data == true) {
                return ChatListWidget(
                  gemmaHandler: (message) {
                    setState(() {
                      _messages.add(message);
                    });
                  },
                  humanHandler: (text) {
                    setState(() {
                      _messages.add(Message(text: text, isHuman: true));
                    });
                  },
                  messages: _messages,
                );
              } else {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
            },
          ),
        ]));
  }
}
