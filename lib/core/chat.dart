import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/function_call.dart';
import 'package:flutter_gemma/core/message.dart';
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

  Future<dynamic> generateChatResponse() async {
    debugPrint('InferenceChat: Getting response from native model...');
    final response = await session.getResponse();
    final cleanedResponse = _cleanResponse(response);

    if (cleanedResponse.isEmpty) {
      debugPrint('InferenceChat: Raw response from native model is EMPTY after cleaning.');
      return '';
    }

    debugPrint('InferenceChat: Raw response from native model:\n--- START ---\n$cleanedResponse\n--- END ---');

    final functionCall = _parseFunctionCall(cleanedResponse);
    if (functionCall != null) {
      final toolCallMessage = Message.toolCall(text: cleanedResponse);
      _fullHistory.add(toolCallMessage);
      _modelHistory.add(toolCallMessage);
      debugPrint('InferenceChat: Added tool call to history: ${toolCallMessage.text}');
      return functionCall;
    }

    final chatMessage = Message(text: cleanedResponse, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);

    return cleanedResponse;
  }

  Stream<dynamic> generateChatResponseAsync() async* {
    final buffer = StringBuffer();

    await for (final token in session.getResponseAsync()) {
      buffer.write(token);
      yield token;
    }

    final response = buffer.toString();
    final responseTokens = await session.sizeInTokens(response);
    _currentTokens += responseTokens;

    if (_currentTokens >= (maxTokens - tokenBuffer)) {
      await _recreateSessionWithReducedChunks();
    }

    final functionCall = _parseFunctionCall(response);
    if (functionCall != null) {
      yield functionCall;
      return;
    }

    final chatMessage = Message(text: response, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);
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
    toolsPrompt.writeln('You have access to functions. If you decide to invoke any of the function(s), you MUST put it in the format of {"name": function name, "parameters": dictionary of argument name and its value} You SHOULD NOT include any other text in the response if you call a function');
    toolsPrompt.writeln('<tool_code>');
    for (final tool in tools) {
      toolsPrompt.writeln(
          '${tool.name}: ${tool.description} Parameters: ${jsonEncode(tool.parameters)}');
    }
    toolsPrompt.writeln('</tool_code>');
    return toolsPrompt.toString();
  }

  FunctionCall? _parseFunctionCall(String response) {
    debugPrint('InferenceChat: Parsing response for function call...');
    final turnRegex = RegExp(r'<start_of_turn>model\s*([\s\S]*?)<end_of_turn>');
    var content = response;
    if (turnRegex.hasMatch(response)) {
      content = turnRegex.firstMatch(response)!.group(1)!.trim();
    }

    // Function to process a potential JSON string
    FunctionCall? tryParseJson(String jsonString) {
      try {
        final decoded = jsonDecode(jsonString.trim());
        if (decoded is Map<String, dynamic>) {
          final toolName = decoded['name'] as String?;
          final parameters = decoded['parameters'] as Map<String, dynamic>?;

          if (toolName != null && parameters != null) {
            final functionCall = FunctionCall(name: toolName, args: parameters);
            debugPrint('InferenceChat: Parsed function call from JSON: ${functionCall.name}(${functionCall.args})');
            return functionCall;
          }
        }
      } catch (e) {
        // It's okay if it fails, it might not be JSON.
        debugPrint('InferenceChat: Failed to decode string as JSON. Error: $e');
      }
      return null;
    }

    // 1. Check for <tool_code> tags
    final toolCodeRegex = RegExp(r'<tool_code>([\s\S]*?)<\/tool_code>', multiLine: true);
    var toolCodeMatch = toolCodeRegex.firstMatch(content);
    if (toolCodeMatch != null) {
      final toolCode = toolCodeMatch.group(1)!.trim();
      debugPrint('InferenceChat: Found <tool_code> content: $toolCode');
      final result = tryParseJson(toolCode);
      if (result != null) return result;
    }

    // 2. Check for markdown code block
    final markdownRegex = RegExp(r'```(?:json|tool_code)\s*([\s\S]*?)\s*```', multiLine: true);
    final markdownMatch = markdownRegex.firstMatch(content);
    if (markdownMatch != null) {
      final toolCode = markdownMatch.group(1)!.trim();
      debugPrint('InferenceChat: Found markdown tool_code content: $toolCode');
      final result = tryParseJson(toolCode);
      if (result != null) return result;
    }

    // 3. If no tags are found, try to parse the whole content as JSON
    debugPrint('InferenceChat: No <tool_code> or markdown tags found. Attempting to parse the entire response as JSON.');
    final result = tryParseJson(content);
    if (result != null) return result;

    debugPrint('InferenceChat: No valid function call found in response.');
    return null;
  }
}