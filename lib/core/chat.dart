import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/function_call_parser.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';

import 'model.dart';

class InferenceChat {
  final Future<InferenceModelSession> Function()? sessionCreator;
  final int maxTokens;
  final int tokenBuffer;
  final bool supportImage;
  final bool supportsFunctionCalls;
  final ModelType modelType; // Add modelType parameter
  final bool isThinking; // Add isThinking flag for thinking models
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
    this.supportsFunctionCalls = false,
    this.tools = const [],
    this.modelType = ModelType.gemmaIt, // Default to gemmaIt for backward compatibility
    this.isThinking = false, // Default to false for backward compatibility
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
    // and only if the model supports function calls
    if (message.isUser && 
        message.type == MessageType.text && 
        !_toolsInstructionSent && 
        tools.isNotEmpty && 
        !noTool &&
        supportsFunctionCalls) {
      _toolsInstructionSent = true;
      final toolsPrompt = _createToolsPrompt();
      final newText = '$toolsPrompt\n${message.text}';
      messageToSend = message.copyWith(text: newText);
    } else if (!supportsFunctionCalls && tools.isNotEmpty && !noTool) {
      // Log warning if model doesn't support function calls but tools are provided
      debugPrint('WARNING: Model does not support function calls, but tools were provided. Tools will be ignored.');
    }

    // --- DETAILED LOGGING ---
    final historyForLogging = _modelHistory.map((m) => m.transformToChatPrompt(type: modelType)).join('\n');
    debugPrint('--- Sending to Native ---');
    debugPrint('History:\n$historyForLogging');
    debugPrint('Current Message:\n${messageToSend.transformToChatPrompt(type: modelType)}');
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
    final cleanedResponse = ModelThinkingFilter.cleanResponse(
      response,
      isThinking: isThinking,
      modelType: modelType
    );

    if (cleanedResponse.isEmpty) {
      debugPrint('InferenceChat: Raw response from native model is EMPTY after cleaning.');
      return TextResponse(''); // Return TextResponse instead of String
    }

    debugPrint('InferenceChat: Raw response from native model:\n--- START ---\n$cleanedResponse\n--- END ---');

    // Try to parse as function call if tools are available and model supports function calls
    if (tools.isNotEmpty && supportsFunctionCalls) {
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

    return TextResponse(cleanedResponse); // Return TextResponse instead of String
  }

  Stream<ModelResponse> generateChatResponseAsync() async* {
    debugPrint('InferenceChat: Starting async stream generation');
    final buffer = StringBuffer();
    
    // Smart function handling mode - continuous scanning for JSON patterns
    String funcBuffer = '';
    bool functionProcessed = false;

    debugPrint('InferenceChat: Starting to iterate over native tokens...');
    
    final originalStream = session.getResponseAsync().map((token) => TextResponse(token));
    
    // Apply thinking filter if needed using ModelThinkingFilter
    final Stream<ModelResponse> filteredStream = isThinking 
        ? ModelThinkingFilter.filterThinkingStream(
            originalStream, 
            modelType: modelType
          )
        : originalStream;
        
    await for (final response in filteredStream) {
      if (response is TextResponse) {
        final token = response.token;
        debugPrint('InferenceChat: Received filtered token: "$token"');
        
        // Track if this token should be added to buffer (default true)
        bool shouldAddToBuffer = true;
        
        // Continuous scanning for function calls in text - for models like DeepSeek
        if (tools.isNotEmpty && supportsFunctionCalls) {
          // Check if we're currently buffering potential JSON
          if (funcBuffer.isNotEmpty) {
            // We're already buffering - add token and check for completion
            funcBuffer += token;
            debugPrint('InferenceChat: Buffering token: "$token", total: ${funcBuffer.length} chars');
            
            // Check if we now have a complete JSON
            if (FunctionCallParser.isJsonComplete(funcBuffer)) {
              // First try to extract message from any JSON with message field
              try {
                final jsonData = jsonDecode(funcBuffer);
                if (jsonData is Map<String, dynamic> && jsonData.containsKey('message')) {
                  // Found JSON with message field - extract and display the message
                  final message = jsonData['message'] as String;
                  debugPrint('InferenceChat: Extracted message from JSON: "$message"');
                  yield TextResponse(message);
                  funcBuffer = '';
                  shouldAddToBuffer = false; // Don't add JSON tokens to buffer
                  continue;
                }
              } catch (e) {
                debugPrint('InferenceChat: Failed to parse JSON for message extraction: $e');
              }
              
              // If no message field found, try parsing as function call
              final functionCall = FunctionCallParser.parse(funcBuffer);
              if (functionCall != null) {
                debugPrint('InferenceChat: Found function call in complete buffer!');
                yield functionCall;
                funcBuffer = '';
                shouldAddToBuffer = false; // Don't add function call tokens to buffer
                continue;
              } else {
                // Not a valid JSON - emit as text and clear buffer
                debugPrint('InferenceChat: Invalid JSON, emitting as text');
                yield TextResponse(funcBuffer);
                funcBuffer = '';
                shouldAddToBuffer = false;
                continue;
              }
            }
            
            // If buffer gets too long without completing, flush as text
            if (funcBuffer.length > 150) {
              debugPrint('InferenceChat: Buffer too long without completion, flushing as text');
              yield TextResponse(funcBuffer);
              funcBuffer = '';
              shouldAddToBuffer = false;
              continue;
            }
            
            // Still buffering, don't emit yet
            shouldAddToBuffer = false;
          } else {
            // Not currently buffering - check if this token starts JSON
            if (token.contains('{') || token.contains('```')) {
              debugPrint('InferenceChat: Found potential JSON start in token: "$token"');
              funcBuffer = token;
              shouldAddToBuffer = false; // Don't add to main buffer while we determine if it's JSON
            } else {
              // Normal text token - emit immediately
              debugPrint('InferenceChat: Emitting text token: "$token"');
              yield response;
              shouldAddToBuffer = true; // Add to main buffer for history
            }
          }
        } else {
          // No function processing happening - emit token directly
          debugPrint('InferenceChat: No function processing, emitting token as text: "$token"');
          yield response;
          shouldAddToBuffer = true; // Add to main buffer for history
        }
        
        // Add token to buffer only if it should be included in final message
        if (shouldAddToBuffer) {
          buffer.write(token);
        }
      } else {
        // For non-TextResponse (like ThinkingResponse), pass through
        yield response;
      }
    }
    
    debugPrint('InferenceChat: Native token stream ended');
    final response = buffer.toString();
    debugPrint('InferenceChat: Complete response accumulated: "$response"');
    
    // Handle end of stream - process any remaining buffer
    if (funcBuffer.isNotEmpty) {
      debugPrint('InferenceChat: Processing remaining buffer at end of stream: ${funcBuffer.length} chars');
      
      // First try to extract message from JSON if it has message field
      if (FunctionCallParser.isJsonComplete(funcBuffer)) {
        try {
          final jsonData = jsonDecode(funcBuffer);
          if (jsonData is Map<String, dynamic> && jsonData.containsKey('message')) {
            final message = jsonData['message'] as String;
            debugPrint('InferenceChat: Extracted message from end-of-stream JSON: "$message"');
            yield TextResponse(message);
          } else {
            // Try to parse as function call
            final functionCall = FunctionCallParser.parse(funcBuffer);
            if (functionCall != null) {
              debugPrint('InferenceChat: Function call found at end of stream');
              yield functionCall;
            } else {
              yield TextResponse(funcBuffer);
            }
          }
        } catch (e) {
          debugPrint('InferenceChat: Failed to parse end-of-stream JSON: $e');
          yield TextResponse(funcBuffer);
        }
      } else {
        debugPrint('InferenceChat: No complete JSON at end of stream, emitting remaining as text');
        yield TextResponse(funcBuffer);
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
    switch (modelType) {
      case ModelType.general:
      case ModelType.gemmaIt:
        // Remove trailing <end_of_turn> tags and trim whitespace
        return response
            .replaceAll(RegExp(r'<end_of_turn>\s*$'), '')
            .trim();
      
      case ModelType.deepSeek:
        String cleaned = response;
        // Remove <think> blocks (DeepSeek internal reasoning)
        cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
        // DeepSeek doesn't use <end_of_turn>, just trim whitespace
        return cleaned.trim();
    }
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
