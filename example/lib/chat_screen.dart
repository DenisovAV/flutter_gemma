import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/loading_widget.dart';
import 'package:flutter_gemma_example/models/model.dart';
import 'package:path_provider/path_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.model = Model.gemma3Gpu});

  final Model model;

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? chat;
  final _messages = <Message>[];
  bool _isModelInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    if (!await _gemma.modelManager.isModelInstalled) {
      final path = kIsWeb
          ? widget.model.url
          : '${(await getApplicationDocumentsDirectory()).path}/${widget.model.filename}';
      await _gemma.modelManager.setModelPath(path);
    }
    final model = await _gemma.createModel(
      modelType: super.widget.model.modelType,
      preferredBackend: super.widget.model.preferredBackend,
      maxTokens: 1024,
    );
    chat = await model.createChat(
      temperature: super.widget.model.temperature,
      randomSeed: 1,
      topK: super.widget.model.topK,
      topP: super.widget.model.topP,
      tokenBuffer: 256,
    );
    setState(() {
      _isModelInitialized = true;
    });
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
        _isModelInitialized
            ? Column(children: [
                if (_error != null) _buildErrorBanner(_error!),
                Expanded(
                  child: ChatListWidget(
                    chat: chat,
                    gemmaHandler: (message) {
                      setState(() {
                        _messages.add(message);
                      });
                    },
                    humanHandler: (text) {
                      setState(() {
                        _error = null;
                        _messages.add(Message(text: text, isUser: true));
                      });
                    },
                    errorHandler: (err) {
                      setState(() {
                        _error = err;
                      });
                    },
                    messages: _messages,
                  ),
                )
              ])
            : const LoadingWidget(message: 'Initializing the model'),
      ]),
    );
  }

  Widget _buildErrorBanner(String errorMessage) {
    return Container(
      width: double.infinity,
      color: Colors.red,
      padding: const EdgeInsets.all(8.0),
      child: Text(
        errorMessage,
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }
}
