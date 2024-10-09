import 'package:flutter/material.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/loading_widge.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _messages = <Message>[];
  late Stream<int> loadingProgress;

  @override
  void initState() {
    super.initState();
    loadingProgress = FlutterGemmaPlugin.instance.loadAssetModelWithProgress(fullPath: 'model.bin')
      ..listen(
        (_) => {},
        onDone: () => FlutterGemmaPlugin.instance.init(
          maxTokens: 512,
          temperature: 1.0,
          topK: 1,
          randomSeed: 1,
        ),
      );
  }

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
          StreamBuilder<int>(
            stream: loadingProgress,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return FutureBuilder(
                  future: FlutterGemmaPlugin.instance.isInitialized,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.waiting &&
                        snapshot.data == true) {
                      return ChatListWidget(
                        gemmaHandler: (message) {
                          setState(() {
                            _messages.add(message);
                          });
                        },
                        humanHandler: (text) {
                          setState(() {
                            _messages.add(Message(text: text, isUser: true));
                          });
                        },
                        messages: _messages,
                      );
                    } else {
                      return const LoadingWidget(message: 'Model is initializing');
                    }
                  },
                );
              } else {
                return LoadingWidget(
                  message: 'Model is loading',
                  progress: snapshot.data ?? 0,
                );
              }
            },
          ),
        ]));
  }
}
