import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';

class InferenceChat {
  final Future<InferenceModelSession> Function()? sessionCreator;
  final int maxTokens;
  final int tokenBuffer;
  late InferenceModelSession session;

  final List<Message> _fullHistory = [];
  final List<Message> _modelHistory = [];
  int _currentTokens = 0;

  InferenceChat({
    required this.sessionCreator,
    required this.maxTokens,
    this.tokenBuffer = 2000,
  });

  List<Message> get fullHistory => List.unmodifiable(_fullHistory);

  Future<void> initSession() async {
    session = await sessionCreator!();
  }

  Future<void> addQueryChunk(Message message) async {
    final messageTokens = await session.sizeInTokens(message.text);
    _currentTokens += messageTokens;
    if (_currentTokens >= (maxTokens - tokenBuffer)) {
      await _recreateSessionWithReducedChunks();
    }

    await session.addQueryChunk(message);
    _fullHistory.add(message);
    _modelHistory.add(message);
  }

  Future<String> generateChatResponse() async {
    final response = await session.getResponse();
    final responseTokens = await session.sizeInTokens(response);
    _currentTokens += responseTokens;

    if (_currentTokens >= (maxTokens - tokenBuffer)) {
      await _recreateSessionWithReducedChunks();
    }

    final chatMessage = Message(text: response, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);

    return response;
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

    final chatMessage = Message(text: response, isUser: false);
    _fullHistory.add(chatMessage);
    _modelHistory.add(chatMessage);
  }

  Future<void> _recreateSessionWithReducedChunks() async {
    while (_currentTokens >= (maxTokens - tokenBuffer) && _modelHistory.isNotEmpty) {
      final removedMessage = _modelHistory.removeAt(0);
      final size = await session.sizeInTokens(removedMessage.text);
      _currentTokens -= size;
    }

    await session.close();
    session = await sessionCreator!();

    for (final message in _modelHistory) {
      await session.addQueryChunk(message);
    }
  }

  Future<void> clearHistory() async {
    _modelHistory.clear();
    _currentTokens = 0;
    await session.close();
    session = await sessionCreator!();
  }
}
