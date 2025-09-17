import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/loading_widget.dart';
import 'package:flutter_gemma_example/models/model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma_example/model_selection_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.model = Model.gemma3_1B, this.selectedBackend});

  final Model model;
  final PreferredBackend? selectedBackend;

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? chat;
  final _messages = <Message>[];
  bool _isModelInitialized = false;
  bool _isStreaming = false; // Track streaming state
  String? _error;
  Color _backgroundColor = const Color(0xFF0b2351);
  String _appTitle = 'Flutter Gemma Example'; // Track the current app title

  // Define the tools
  final List<Tool> _tools = [
    const Tool(
      name: 'change_app_title',
      description: 'Changes the title of the app in the AppBar. Provide a new title text.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'The new title text to display in the AppBar',
          },
        },
        'required': ['title'],
      },
    ),
    const Tool(
      name: 'change_background_color',
      description:
          "Changes the background color of the app. The color should be a standard web color name like 'red', 'blue', 'green', 'yellow', 'purple', or 'orange'.",
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
    /* const Tool(
      name: 'show_alert',
      description: 'Shows an alert dialog with a custom message and title.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {
            'type': 'string',
            'description': 'The title of the alert dialog',
          },
          'message': {
            'type': 'string',
            'description': 'The message content of the alert dialog',
          },
          'button_text': {
            'type': 'string',
            'description': 'The text for the OK button (optional, defaults to "OK")',
          },
        },
        'required': ['title', 'message'],
      },
    ), */
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
      final path = kIsWeb ? widget.model.url : '${(await getApplicationDocumentsDirectory()).path}/${widget.model.filename}';
      await _gemma.modelManager.setModelPath(path);
    }

    final model = await _gemma.createModel(
      modelType: super.widget.model.modelType,
      fileType: super.widget.model.fileType, // Pass fileType from model
      preferredBackend: super.widget.selectedBackend ?? super.widget.model.preferredBackend,
      maxTokens: 1024,
      supportImage: widget.model.supportImage, // Pass image support
      maxNumImages: widget.model.maxNumImages, // Maximum 4 images for multimodal models
    );

    debugPrint('ChatScreen: Creating chat with:');
    debugPrint('  supportImage: ${widget.model.supportImage}');
    debugPrint('  supportsFunctionCalls: ${widget.model.supportsFunctionCalls}');
    debugPrint('  modelType: ${widget.model.modelType}');
    debugPrint('  fileType: ${widget.model.fileType}');

    chat = await model.createChat(
      temperature: super.widget.model.temperature,
      randomSeed: 1,
      topK: super.widget.model.topK,
      topP: super.widget.model.topP,
      tokenBuffer: 256,
      supportImage: widget.model.supportImage, // Image support in chat
      supportsFunctionCalls: widget.model.supportsFunctionCalls, // Function calls support from model
      tools: _tools, // Pass the tools to the chat
      isThinking: widget.model.isThinking, // Pass isThinking from model
      modelType: widget.model.modelType, // Pass modelType from model
    );

    debugPrint('ChatScreen: Chat created, supportsImages: ${chat?.supportsImages}');

    setState(() {
      _isModelInitialized = true;
    });
  }

  // Helper method to handle function calls with system messages (async version)
  Future<void> _handleFunctionCall(FunctionCallResponse functionCall) async {
    debugPrint('Function call received: ${functionCall.name}(${functionCall.args})');

    // Set streaming state and show "Calling function..." in one setState
    setState(() {
      _isStreaming = true;
      _messages.add(Message.systemInfo(
        text: "🔧 Calling: ${functionCall.name}(${functionCall.args.entries.map((e) => '${e.key}: \"${e.value}\"').join(', ')})",
      ));
    });

    // Small delay to show the calling message
    await Future.delayed(const Duration(milliseconds: 300));

    // 2. Show "Executing function"
    setState(() {
      _messages.add(Message.systemInfo(
        text: "⚡ Executing function",
      ));
    });

    final toolResponse = await _executeTool(functionCall);
    debugPrint('Tool response: $toolResponse');

    // 3. Show "Function completed"
    setState(() {
      _messages.add(Message.systemInfo(
        text: "✅ Function completed: ${toolResponse['message'] ?? 'Success'}",
      ));
    });

    // Small delay to show completion
    await Future.delayed(const Duration(milliseconds: 300));

    // Send tool response back to the model
    final toolMessage = Message.toolResponse(
      toolName: functionCall.name,
      response: toolResponse,
    );
    await chat?.addQuery(toolMessage);

    // TEMPORARILY use sync response for debugging
    debugPrint('⚡ ChatScreen: Starting function response generation (SYNC MODE)');

    final response = await chat!.generateChatResponse();
    debugPrint('⚡ ChatScreen: SYNC response received: ${response.runtimeType}');

    if (response is TextResponse) {
      final accumulatedResponse = response.token;
      debugPrint('🏁 ChatScreen: SYNC Function response completed: "$accumulatedResponse" (length: ${accumulatedResponse.length})');

      setState(() {
        _messages.add(Message.text(text: accumulatedResponse));
      });
    } else if (response is FunctionCallResponse) {
      debugPrint('❌ ChatScreen: Unexpected FunctionCall after tool response: ${response.name}');
    }

    // Reset streaming state when done
    setState(() {
      _isStreaming = false;
    });
  }

  // Main gemma response handler - processes responses from GemmaInputField
  Future<void> _handleGemmaResponse(ModelResponse response) async {
    if (response is FunctionCallResponse) {
      debugPrint('🔧 ChatScreen: Function call received: ${response.name}');
      await _handleFunctionCall(response);
    } else if (response is TextResponse) {
      // DEBUG: Track what text we're receiving from GemmaInputField
      debugPrint('📥 ChatScreen: Received final text from GemmaInputField: "${response.token}" (length: ${response.token.length})');
      setState(() {
        _messages.add(Message.text(text: response.token));
        _isStreaming = false;
      });
    } else {
      debugPrint('❌ ChatScreen: Unexpected response type: ${response.runtimeType}');
    }
  }

  // Function to execute tools
  Future<Map<String, dynamic>> _executeTool(FunctionCallResponse functionCall) async {
    if (functionCall.name == 'change_app_title') {
      final newTitle = functionCall.args['title'] as String?;
      if (newTitle != null && newTitle.isNotEmpty) {
        setState(() {
          _appTitle = newTitle;
        });
        return {'status': 'success', 'message': 'App title changed to "$newTitle"'};
      } else {
        return {'error': 'Title cannot be empty'};
      }
    }
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
        return {'status': 'success', 'message': 'Background color changed to $colorName'};
      } else {
        return {'error': 'Color not supported', 'available_colors': colorMap.keys.toList()};
      }
    }
    if (functionCall.name == 'show_alert') {
      final title = functionCall.args['title'] as String? ?? 'Alert';
      final message = functionCall.args['message'] as String? ?? 'No message provided';
      final buttonText = functionCall.args['button_text'] as String? ?? 'OK';

      // Show the alert dialog
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(buttonText),
              ),
            ],
          );
        },
      );

      return {'status': 'success', 'message': 'Alert dialog shown with title "$title"'};
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
            Text(
              _appTitle,
              style: const TextStyle(fontSize: 18),
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
                if (chat?.supportsImages == true && _messages.isEmpty) _buildImageSupportInfo(),
                Expanded(
                  child: ChatListWidget(
                    chat: chat,
                    gemmaHandler: _handleGemmaResponse,
                    messageHandler: (message) {
                      // Handles all message additions to history
                      setState(() {
                        _error = null;
                        _messages.add(message);
                        // Set streaming to true when user sends message
                        _isStreaming = true;
                      });
                    },
                    errorHandler: (err) {
                      setState(() {
                        _error = err;
                        _isStreaming = false; // Reset streaming on error
                      });
                    },
                    messages: _messages,
                    isProcessing: _isStreaming,
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
