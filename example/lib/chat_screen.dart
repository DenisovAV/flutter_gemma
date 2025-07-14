import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/function_call.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/loading_widget.dart';
import 'package:flutter_gemma_example/models/model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma_example/model_selection_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.model = Model.gemma3Gpu_1B});

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
  Color _backgroundColor = const Color(0xFF0b2351);

  // Define the tools
  final List<Tool> _tools = [
    const Tool(
      name: 'change_background_color',
      description: "Changes the background color of the app. The color should be a standard web color name like 'red', 'blue', 'green', 'yellow', 'purple', or 'orange'.",
      parameters: {
        'type': 'object',
        'properties': {
          'color': {
            'type': 'string',
            'description': 'The color name',
          },
        },
        'required': ['color'],
      },
    ),
  ];

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
      supportImage: widget.model.supportImage, // Pass image support
      maxNumImages: widget.model.maxNumImages, // Maximum 4 images for multimodal models
    );

    chat = await model.createChat(
      temperature: super.widget.model.temperature,
      randomSeed: 1,
      topK: super.widget.model.topK,
      topP: super.widget.model.topP,
      tokenBuffer: 256,
      supportImage: widget.model.supportImage, // Image support in chat
      tools: _tools, // Pass the tools to the chat
    );

    setState(() {
      _isModelInitialized = true;
    });
  }

  // Function to execute tools
  Future<Map<String, dynamic>> _executeTool(FunctionCall functionCall) async {
    if (functionCall.name == 'change_background_color') {
      final colorName = functionCall.args['color']?.toLowerCase();
      final colorMap = {
        'red': Colors.red,
        'blue': Colors.blue,
        'green': Colors.green,
        'yellow': Colors.yellow,
        'purple': Colors.purple,
        'orange': Colors.orange,
      };
      if (colorMap.containsKey(colorName)) {
        setState(() {
          _backgroundColor = colorMap[colorName]!;
        });
        return {'status': 'success'};
      } else {
        return {'error': 'Color not supported'};
      }
    }
    return {'error': 'Tool not found'};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const ModelSelectionScreen(),
              ),
                  (route) => false,
            );
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Flutter Gemma Example',
              style: TextStyle(fontSize: 18),
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (chat?.supportsImages == true)
              const Text(
                'Image support enabled',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          // Image support indicator
          if (chat?.supportsImages == true)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(
                Icons.image,
                color: Colors.green,
                size: 20,
              ),
            ),
        ],
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
          if (chat?.supportsImages == true && _messages.isEmpty)
            _buildImageSupportInfo(),
          Expanded(
            child: ChatListWidget(
              chat: chat,
              gemmaHandler: (response) async {
                if (response is FunctionCall) {
                  debugPrint('Function call received: ${response.name}(${response.args})');
                  final toolResponse = await _executeTool(response);
                  debugPrint('Tool response: $toolResponse');
                  final message = Message.toolResponse(
                    toolName: response.name,
                    response: toolResponse,
                  );
                  await chat?.addQuery(message);
                  debugPrint('Sending tool response back to model...');
                  final finalResponse = await chat?.generateChatResponse();
                  debugPrint('Final response from model: $finalResponse');

                  if (finalResponse is String && finalResponse.isNotEmpty) {
                    setState(() {
                      _messages.add(Message.text(text: finalResponse));
                    });
                  } else {
                    debugPrint('Received empty or non-string response after tool call: $finalResponse');
                  }
                } else if (response is String && response.isNotEmpty) {
                  setState(() {
                    _messages.add(Message.text(text: response));
                  });
                }
              },
              humanHandler: (message) { // Now accepts Message instead of String
                setState(() {
                  _error = null;
                  _messages.add(message);
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
            : const LoadingWidget(message: 'Initializing model'),
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

  Widget _buildImageSupportInfo() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1a3a5c),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.green,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Model supports images',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Use the 📷 button to add images to your messages',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
