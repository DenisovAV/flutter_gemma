import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/preferred_backend.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/loading_widget.dart';
import 'package:path/path.dart' as path;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? chat;
  final _messages = <Message>[];
  bool _isModelInitialized = false;
  int? _loadingProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    // Gemma 3 support Android / Web
    // const modelAssetPath = 'gemma3-1b-it-int4.task';

    // Gemma 1.1 / 2 for iOS
    const modelAssetPath = 'model.bin';

    // Gemma 3 require correct file extension .task for Android
    var modelAppPath = path.basename(modelAssetPath);

    _gemma.modelManager.setModelPath(modelAppPath);
    bool isLoaded = await _gemma.modelManager.isModelInstalled;
    if (!isLoaded) {
      await for (int progress in _gemma.modelManager
          .installModelFromAssetWithProgress(modelAssetPath)) {
        setState(() {
          _loadingProgress = progress;
        });
      }
    }
    final model = await _gemma.createModel(
      isInstructionTuned: true,
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
    );
    chat = await model.createChat(
      temperature: 1.0,
      randomSeed: 1,
      topK: 1,
      tokenBuffer: 128,
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
            : LoadingWidget(
                message: _loadingProgress == null
                    ? 'Model is checking'
                    : 'Model loading progress:',
                progress: _loadingProgress,
              ),
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
