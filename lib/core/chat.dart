import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  Future<String> generateChatResponse() async {
    debugPrint('InferenceChat: Getting response from native model...');
    final response = await session.getResponse();
    final cleanedResponse = _cleanResponse(response);

    if (cleanedResponse.isEmpty) {
      debugPrint('InferenceChat: Raw response from native model is EMPTY after cleaning.');
      return '';
    }

    debugPrint('InferenceChat: Raw response from native model:\n--- START ---\n$cleanedResponse\n--- END ---');

    // Simply add to history and return - no function parsing here
    final chatMessage = Message(text: cleanedResponse, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);

    return cleanedResponse;
  }

  Stream<String> generateChatResponseAsync() async* {
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

    // Simply add to history - no function parsing here
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