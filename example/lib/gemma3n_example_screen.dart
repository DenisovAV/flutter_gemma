import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/loading_widget.dart';
import 'package:flutter_gemma_example/models/model.dart';
import 'package:path_provider/path_provider.dart';

/// Example screen specifically demonstrating Gemma 3 Nano model usage
class Gemma3nExampleScreen extends StatefulWidget {
  const Gemma3nExampleScreen({super.key});

  @override
  Gemma3nExampleScreenState createState() => Gemma3nExampleScreenState();
}

class Gemma3nExampleScreenState extends State<Gemma3nExampleScreen> {
  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? chat;
  final _messages = <Message>[];
  bool _isModelInitialized = false;
  String? _error;
  // Use one of the new Gemma 3 Nano models as the default
  Model _selectedModel = Model.gemma3nE2BGpu;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  @override
  void dispose() {
    super.dispose();
    _gemma.modelManager.deleteModel();
  }

  Future<void> _initializeModel() async {
    try {
      setState(() {
        _isModelInitialized = false;
        _error = null;
      });

      // Check if model is already installed, if not set the path
      if (!await _gemma.modelManager.isModelInstalled) {
        final path = kIsWeb
            ? _selectedModel.url
            : '${(await getApplicationDocumentsDirectory()).path}/${_selectedModel.filename}';
        await _gemma.modelManager.setModelPath(path);
      }

      // Create the model with optimized settings for Gemma 3 Nano
      final model = await _gemma.createModel(
        modelType: _selectedModel.modelType,
        preferredBackend: _selectedModel.preferredBackend,
        maxTokens: 2048, // Larger context for better conversations
      );

      // Create chat with optimized parameters for Gemma 3 Nano
      chat = await model.createChat(
        temperature: _selectedModel.temperature,
        randomSeed: 1,
        topK: _selectedModel.topK,
        topP: _selectedModel.topP,
        tokenBuffer: 512, // Larger buffer for longer conversations
      );

      setState(() {
        _isModelInitialized = true;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isModelInitialized = false;
      });
    }
  }

  void _addMessage(Message message) {
    setState(() {
      _messages.add(message);
    });
  }

  void _addUserMessage(String text) {
    _addMessage(Message(text: text, isUser: true));
  }

  void _handleError(String error) {
    setState(() {
      _error = error;
    });
  }

  void _switchModel(Model newModel) {
    if (_selectedModel != newModel) {
      setState(() {
        _selectedModel = newModel;
        _messages.clear();
        _error = null;
      });
      _gemma.modelManager.deleteModel().then((_) {
        _initializeModel();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b2351),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b2351),
        title: const Text(
          'Gemma 3 Nano Example',
          style: TextStyle(fontSize: 20),
        ),
        actions: [
          PopupMenuButton<Model>(
            icon: const Icon(Icons.model_training),
            onSelected: _switchModel,
            itemBuilder: (context) => [
              // List the new Gemma 3 Nano models
              const PopupMenuItem(
                value: Model.gemma3nE4BGpu,
                child: Text('Gemma 3n E4B IT (GPU)'),
              ),
              const PopupMenuItem(
                value: Model.gemma3nE4BCpu,
                child: Text('Gemma 3n E4B IT (CPU)'),
              ),
              const PopupMenuItem(
                value: Model.gemma3nE2BGpu,
                child: Text('Gemma 3n E2B IT (GPU)'),
              ),
              const PopupMenuItem(
                value: Model.gemma3nE2BCpu,
                child: Text('Gemma 3n E2B IT (CPU)'),
              ),
              if (!kIsWeb)
                const PopupMenuItem(
                  value: Model.gemma3nLocalAsset,
                  child: Text('Gemma 3n E2B IT (Local Asset)'),
                ),
            ],
          ),
        ],
      ),
      body: _isModelInitialized
          ? Column(
              children: [
                // Model info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Using: ${_selectedModel.displayName}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Gemma 3 Nano is a compact 1.5B parameter model optimized for on-device inference with excellent performance.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Backend: ${_selectedModel.preferredBackend.name.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.yellow,
                        ),
                      ),
                    ],
                  ),
                ),
                // Chat interface
                Expanded(
                  child: ChatListWidget(
                    chat: chat,
                    messages: _messages,
                    gemmaHandler: _addMessage,
                    humanHandler: _addUserMessage,
                    errorHandler: _handleError,
                  ),
                ),
              ],
            )
          : LoadingWidget(
              message: 'Gemma 3 Nano',
            ),
    );
  }
}
