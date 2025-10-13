import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/chat_widget.dart';
import 'package:flutter_gemma_example/loading_widget.dart';
import 'package:flutter_gemma_example/models/model.dart';
import 'package:flutter_gemma_example/model_selection_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.model = Model.gemma3_1B, this.selectedBackend});

  final Model model;
  final PreferredBackend? selectedBackend;

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  InferenceChat? chat;
  final _messages = <Message>[];
  bool _isModelInitialized = false;
  bool _isInitializing = false; // Protection against concurrent initialization
  bool _isStreaming = false; // Track streaming state
  String? _error;
  Color _backgroundColor = const Color(0xFF0b2351);
  String _appTitle = 'Flutter Gemma Example'; // Track the current app title

  // Toggle for sync/async mode
  bool _useSyncMode = false;

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
    _isInitializing = false; // Reset initialization flag
    _isModelInitialized = false; // Reset model flag
    super.dispose();
    // No need to call deleteModel - model cleanup handled by model.close() callback
  }

  Future<void> _initializeModel() async {
    if (_isModelInitialized || _isInitializing) {
      debugPrint('[ChatScreen] Already initialized or initializing, skipping');
      return;
    }

    _isInitializing = true;
    debugPrint('[ChatScreen] Starting model initialization...');

    try {
      // Step 1: Install model (Modern API handles already-installed check)
      debugPrint('[ChatScreen] Step 1: Installing model...');
      await FlutterGemma.installModel(
        modelType: widget.model.modelType,
        fileType: widget.model.fileType,
      )
        .fromNetwork(widget.model.url)
        .install();
      debugPrint('[ChatScreen] Step 1: Model installed ✅');

      // Step 2: Create model with runtime config
      debugPrint('[ChatScreen] Step 2: Creating InferenceModel...');
      final model = await FlutterGemma.getActiveModel(
        maxTokens: widget.model.maxTokens,
        preferredBackend: widget.selectedBackend ?? widget.model.preferredBackend,
        supportImage: widget.model.supportImage,
        maxNumImages: widget.model.maxNumImages,
      );
      debugPrint('[ChatScreen] Step 2: InferenceModel created ✅');

      // Step 3: Create chat
      debugPrint('[ChatScreen] Step 3: Creating chat...');
      chat = await model.createChat(
        temperature: widget.model.temperature,
        randomSeed: 1,
        topK: widget.model.topK,
        topP: widget.model.topP,
        tokenBuffer: 256,
        supportImage: widget.model.supportImage,
        supportsFunctionCalls: widget.model.supportsFunctionCalls,
        tools: _tools,
        isThinking: widget.model.isThinking,
        modelType: widget.model.modelType,
      );
      debugPrint('[ChatScreen] Step 3: Chat created ✅');

      setState(() {
        _isModelInitialized = true;
        _error = null;
      });
      debugPrint('[ChatScreen] Initialization complete ✅');
    } catch (e) {
      debugPrint('[ChatScreen] ❌ Initialization failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize model: ${e.toString()}';
          _isModelInitialized = false;
        });
      }
      rethrow;
    }
    finally {
     _isInitializing = false; // Always reset the flag
    }
  }

  // Helper method to handle function calls with system messages (async version)
  Future<void> _handleFunctionCall(FunctionCallResponse functionCall) async {

    // Set streaming state and show "Calling function..." in one setState
    setState(() {
      _isStreaming = true;
      _messages.add(Message.systemInfo(
        text: "🔧 Calling: ${functionCall.name}(${functionCall.args.entries.map((e) => '${e.key}: "${e.value}"').join(', ')})",
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

    final response = await chat!.generateChatResponse();

    if (response is TextResponse) {
      final accumulatedResponse = response.token;

      setState(() {
        _messages.add(Message.text(text: accumulatedResponse));
      });
    } else if (response is FunctionCallResponse) {
    }

    // Reset streaming state when done
    setState(() {
      _isStreaming = false;
    });
  }

  // Main gemma response handler - processes responses from GemmaInputField
  Future<void> _handleGemmaResponse(ModelResponse response) async {
    if (response is FunctionCallResponse) {
      await _handleFunctionCall(response);
    } else if (response is TextResponse) {
      // DEBUG: Track what text we're receiving from GemmaInputField
      setState(() {
        _messages.add(Message.text(text: response.token));
        _isStreaming = false;
      });
    } else {
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
          // Sync/Async toggle
          Row(
            children: [
              const Text('Sync', style: TextStyle(fontSize: 12)),
              Switch(
                value: _useSyncMode,
                onChanged: (value) {
                  setState(() {
                    _useSyncMode = value;
                  });
                },
                activeColor: Colors.green,
              ),
            ],
          ),
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
                    useSyncMode: _useSyncMode,
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
