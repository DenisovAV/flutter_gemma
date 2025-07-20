import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/function_call_parser.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';

class InferenceChat {
  final Future<InferenceModelSession> Function()? sessionCreator;
  final int maxTokens;
  final int tokenBuffer;
  final bool supportImage;
  late InferenceModelSession session;
  final List<Tool> tools;

  final List<Message> _fullHistory = [];
  final List<Message> _modelHistory = [];
  int _currentTokens = 0;
  bool _toolsInstructionSent = false; // Flag to track if tools instruction was sent

  InferenceChat({
    required this.sessionCreator,
    required this.maxTokens,
    this.tokenBuffer = 2000,
    this.supportImage = false,
    this.tools = const [],
  });

  List<Message> get fullHistory => List.unmodifiable(_fullHistory);

  Future<void> initSession() async {
    session = await sessionCreator!();
  }

  Future<void> addQuery(Message message) async {
    await addQueryChunk(message);
  }

  Future<void> addQueryChunk(Message message, [bool noTool=false]) async {
    var messageToSend = message;
    // Only add tools prompt for the first user text message (not a tool response)
    if (message.isUser && 
        message.type == MessageType.text && 
        !_toolsInstructionSent && 
        tools.isNotEmpty && 
        !noTool) {
      _toolsInstructionSent = true;
      final toolsPrompt = _createToolsPrompt();
      final newText = '$toolsPrompt\n${message.text}';
      messageToSend = message.copyWith(text: newText);
    }

    // --- DETAILED LOGGING ---
    final historyForLogging = _modelHistory.map((m) => m.transformToChatPrompt()).join('\n');
    debugPrint('--- Sending to Native ---');
    debugPrint('History:\n$historyForLogging');
    debugPrint('Current Message:\n${messageToSend.transformToChatPrompt()}');
    debugPrint('-------------------------');
    // --- END LOGGING ---

    await session.addQueryChunk(messageToSend);

    // THE FIX: Add the message that was *actually* sent to the model to the history.
    _fullHistory.add(messageToSend);
    _modelHistory.add(messageToSend);
  }

  Future<ModelResponse> generateChatResponse() async {
    debugPrint('InferenceChat: Getting response from native model...');
    final response = await session.getResponse();
    final cleanedResponse = _cleanResponse(response);

    if (cleanedResponse.isEmpty) {
      debugPrint('InferenceChat: Raw response from native model is EMPTY after cleaning.');
      return TextResponse(''); // Возвращаем TextToken вместо String
    }

    debugPrint('InferenceChat: Raw response from native model:\n--- START ---\n$cleanedResponse\n--- END ---');

    // Try to parse as function call if tools are available
    if (tools.isNotEmpty) {
      final functionCall = FunctionCallParser.parse(cleanedResponse);
      if (functionCall != null) {
        debugPrint('InferenceChat: Detected function call in sync response');
        final toolCallMessage = Message.toolCall(text: cleanedResponse);
        _fullHistory.add(toolCallMessage);
        _modelHistory.add(toolCallMessage);
        debugPrint('InferenceChat: Added tool call to history: ${toolCallMessage.text}');
        return functionCall;
      }
    }

    // Regular text response
    final chatMessage = Message(text: cleanedResponse, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);

    return TextResponse(cleanedResponse); // Возвращаем TextToken вместо String
  }

  Stream<ModelResponse> generateChatResponseAsync() async* {
    debugPrint('InferenceChat: Starting async stream generation');
    final buffer = StringBuffer();
    
    // Smart function handling mode
    String funcBuffer = '';
    bool isJsonMode = false;
    bool decisionMade = false;
    bool functionProcessed = false;

    debugPrint('InferenceChat: Starting to iterate over native tokens...');
    await for (final token in session.getResponseAsync()) {
      debugPrint('InferenceChat: Received token from native: "$token"');
      buffer.write(token);
      
      // Step 1: Determine JSON or text mode (only once!)
      if (!decisionMade && tools.isNotEmpty) {
        funcBuffer += token;
        debugPrint('InferenceChat: Function buffer now: "$funcBuffer"');
        
        if (FunctionCallParser.isJsonStart(funcBuffer)) {
          isJsonMode = true;
          decisionMade = true;
          debugPrint('InferenceChat: Detected JSON mode');
        } else if (FunctionCallParser.isDefinitelyText(funcBuffer)) {
          isJsonMode = false;
          decisionMade = true;
          debugPrint('InferenceChat: Detected text mode - streaming immediately');
          debugPrint('InferenceChat: Emitting buffered content: "$funcBuffer"');
          // Emit accumulated buffer as single token
          yield TextResponse(funcBuffer); // Оборачиваем в TextToken
          funcBuffer = ''; // Clear buffer to avoid duplication
          debugPrint('InferenceChat: Mode decided - TEXT, will stream rest directly');
        } else {
          debugPrint('InferenceChat: Mode not yet determined, continuing to buffer');
        }
      } else {
        // Step 2: Process based on determined mode (don't buffer anymore!)
        if (tools.isNotEmpty && isJsonMode && !functionProcessed) {
          // JSON mode - buffer until complete
          funcBuffer += token;
          debugPrint('InferenceChat: JSON mode - buffering token, buffer: "$funcBuffer"');
          if (FunctionCallParser.isJsonComplete(funcBuffer)) {
            final functionCall = FunctionCallParser.parse(funcBuffer);
            if (functionCall != null) {
              debugPrint('InferenceChat: Function call parsed successfully');
              yield functionCall;
              functionProcessed = true;
              funcBuffer = ''; // Clear buffer, rest will be text response
            }
          }
        } else if (tools.isEmpty || !isJsonMode) {
          // Text mode - stream tokens directly (no buffering needed)
          debugPrint('InferenceChat: TEXT mode - emitting token directly: "$token"');
          yield TextResponse(token); // Оборачиваем в TextToken
        } else {
          debugPrint('InferenceChat: Post-function mode - emitting token: "$token"');
          // After function processed, emit remaining tokens  
          yield TextResponse(token); // Оборачиваем в TextToken
        }
      }
    }
    
    debugPrint('InferenceChat: Native token stream ended');
    final response = buffer.toString();
    debugPrint('InferenceChat: Complete response accumulated: "$response"');
    
    // Handle end of stream - process any remaining buffer
    if (funcBuffer.isNotEmpty && !functionProcessed && tools.isNotEmpty) {
      debugPrint('InferenceChat: Processing remaining buffer at end of stream');
      if (isJsonMode) {
        final functionCall = FunctionCallParser.parse(funcBuffer);
        if (functionCall != null) {
          debugPrint('InferenceChat: Function call found at end of stream');
          yield functionCall;
          functionProcessed = true;
        } else {
          debugPrint('InferenceChat: Incomplete JSON at end of stream, emitting as text');
          yield TextResponse(funcBuffer); // Оборачиваем в TextToken
        }
      } else if (funcBuffer.isNotEmpty) {
        debugPrint('InferenceChat: Emitting remaining buffer as text');
        yield TextResponse(funcBuffer); // Оборачиваем в TextToken
      }
    }
    
    try {
      debugPrint('InferenceChat: Calculating response tokens...');
      final responseTokens = await session.sizeInTokens(response);
      debugPrint('InferenceChat: Response tokens: $responseTokens');
      _currentTokens += responseTokens;
      debugPrint('InferenceChat: Current total tokens: $_currentTokens');

      if (_currentTokens >= (maxTokens - tokenBuffer)) {
        debugPrint('InferenceChat: Token limit reached, recreating session...');
        await _recreateSessionWithReducedChunks();
        debugPrint('InferenceChat: Session recreated successfully');
      }
    } catch (e) {
      debugPrint('InferenceChat: Error during token calculation: $e');
    }

    try {
      debugPrint('InferenceChat: Adding message to history...');
      final chatMessage = Message(text: response, isUser: false);
      debugPrint('InferenceChat: Created message object: ${chatMessage.text}');
      _fullHistory.add(chatMessage);
      debugPrint('InferenceChat: Added to full history');
      _modelHistory.add(chatMessage);
      debugPrint('InferenceChat: Added to model history');
      debugPrint('InferenceChat: Message added to history successfully');
    } catch (e) {
      debugPrint('InferenceChat: Error adding message to history: $e');
      rethrow;
    }
    
    debugPrint('InferenceChat: generateChatResponseAsync completed successfully');
  }

  Future<void> _recreateSessionWithReducedChunks() async {
    while (_currentTokens >= (maxTokens - tokenBuffer) &&
        _modelHistory.isNotEmpty) {
      final removedMessage = _modelHistory.removeAt(0);
      final size = await session.sizeInTokens(removedMessage.text);
      _currentTokens -= size;

      if (removedMessage.hasImage) {
        _currentTokens -= 257;
      }
    }

    await session.close();
    session = await sessionCreator!();

    for (final message in _modelHistory) {
      await session.addQueryChunk(message);
    }
  }

  Future<void> clearHistory({List<Message>? replayHistory}) async {
    _fullHistory.clear();
    _modelHistory.clear();
    _currentTokens = 0;
    _toolsInstructionSent = false; // Reset the flag when clearing history
    await session.close();
    session = await sessionCreator!();

    if (replayHistory != null) {
      for (final message in replayHistory) {
        await addQueryChunk(message, true);
      }
    }
  }

  bool get supportsImages => supportImage;

  int get imageMessageCount => _fullHistory.where((msg) => msg.hasImage).length;

  String _cleanResponse(String response) {
    // Remove trailing <end_of_turn> tags and trim whitespace
    return response
        .replaceAll(RegExp(r'<end_of_turn>\s*$'), '')
        .trim();
  }

  String _createToolsPrompt() {
    if (tools.isEmpty) {
      return '';
    }

    final toolsPrompt = StringBuffer();
    toolsPrompt.writeln('You have access to functions. ONLY call a function when the user explicitly requests an action or command (like "change color", "show alert", "set title"). For regular conversation, greetings, and questions, respond normally without calling any functions.');
    toolsPrompt.writeln('When you do need to call a function, respond with ONLY the JSON in this format: {"name": function_name, "parameters": {argument: value}}');
    toolsPrompt.writeln('After the function is executed, you will get a response. Then provide a helpful message to the user about what was accomplished.');
    toolsPrompt.writeln('<tool_code>');
    for (final tool in tools) {
      toolsPrompt.writeln(
          '${tool.name}: ${tool.description} Parameters: ${jsonEncode(tool.parameters)}');
    }
    toolsPrompt.writeln('</tool_code>');
    return toolsPrompt.toString();
  }
}