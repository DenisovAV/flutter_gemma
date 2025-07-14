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

  Future<void> addQueryChunk(Message message) async {
    var messageToSend = message;
    // If the message is from the user, it's the first message, and tools are available, prepend the tools to the message.
    if (message.isUser && _modelHistory.isEmpty && tools.isNotEmpty) {
      final toolsPrompt = _createToolsPrompt();
      final newText = '$toolsPrompt\n${message.text}';
      messageToSend = message.copyWith(text: newText);
    }

    await session.addQueryChunk(messageToSend);

    // THE FIX: Add the message that was *actually* sent to the model to the history.
    _fullHistory.add(messageToSend);
    _modelHistory.add(messageToSend);
  }

  Future<dynamic> generateChatResponse() async {
    if (_modelHistory.isNotEmpty && _modelHistory.last.type == MessageType.toolResponse) {
      await session.addQueryChunk(const Message(text: '', isUser: false));
    }

    final response = await session.getResponse();
    final trimmedResponse = response.trim();

    if (trimmedResponse.isEmpty) {
      return '';
    }

    final functionCall = _parseFunctionCall(trimmedResponse);
    if (functionCall != null) {
      final toolCallMessage = Message.toolCall(text: trimmedResponse);
      _fullHistory.add(toolCallMessage);
      _modelHistory.add(toolCallMessage);
      return functionCall;
    }

    final chatMessage = Message(text: trimmedResponse, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);

    return trimmedResponse;
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
    await session.close();
    session = await sessionCreator!();

    if (replayHistory != null) {
      for (final message in replayHistory) {
        await addQueryChunk(message);
      }
    }
  }

  bool get supportsImages => supportImage;

  int get imageMessageCount => _fullHistory.where((msg) => msg.hasImage).length;

  String _createToolsPrompt() {
    if (tools.isEmpty) {
      return '';
    }

    final toolsPrompt = StringBuffer();
    toolsPrompt.writeln('<tool_code>');
    toolsPrompt.writeln('Here are the tools available:');
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

    final toolCodeRegex =
        RegExp(r'<tool_code>([\s\S]*?)<\/tool_code>', multiLine: true);
    final markdownRegex = RegExp(r'```tool_code\s*([\s\S]*?)\s*```', multiLine: true);

    var toolCodeMatch = toolCodeRegex.firstMatch(content);
    if (toolCodeMatch == null) {
      toolCodeMatch = markdownRegex.firstMatch(content);
    }

    if (toolCodeMatch != null) {
      var toolCode = toolCodeMatch.group(1)!.trim();
      debugPrint('InferenceChat: Found tool_code content: $toolCode');

      // NEW: Extract the JSON part from the string
      final jsonRegex = RegExp(r'\{[\s\S]*\}');
      final jsonMatch = jsonRegex.firstMatch(toolCode);
      
      if (jsonMatch != null) {
        final jsonString = jsonMatch.group(0)!;
        debugPrint('InferenceChat: Extracted JSON string: $jsonString');
        try {
          final decoded = jsonDecode(jsonString);
          if (decoded is Map<String, dynamic>) {
            // Try to find the function name in the text before the JSON
            var toolName = decoded['tool_name'] ?? decoded['name'];
            if (toolName == null) {
              final nameRegex = RegExp(r'(\w+)\s*:');
              final nameMatch = nameRegex.firstMatch(toolCode);
              if (nameMatch != null) {
                toolName = nameMatch.group(1)!;
              }
            }

            final parameters = decoded['parameters'] ?? decoded['args'] ?? decoded;
            if (toolName != null && parameters is Map<String, dynamic>) {
              final functionCall = FunctionCall(name: toolName, args: parameters);
              debugPrint('InferenceChat: Parsed function call from JSON: ${functionCall.name}(${functionCall.args})');
              return functionCall;
            }
          }
        } catch (e) {
          debugPrint('InferenceChat: Failed to decode extracted JSON. Error: $e');
        }
      }
    }
    debugPrint('InferenceChat: No valid function call found in response.');
    return null;
  }
}