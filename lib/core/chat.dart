import 'package:flutter/foundation.dart';
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

  // State management
  bool _isGenerating = false;

  // Cleanup callbacks
  final List<VoidCallback> _cleanupListeners = [];

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
    _isGenerating = true;

    try {
      await for (final token in session.getResponseAsync()) {
        buffer.write(token);
        yield token;
      }
    } catch (e) {
      // If cancelled or error, still preserve the partial response
    } finally {
      _isGenerating = false;
    }

    final response = buffer.toString();
    if (response.isNotEmpty) {
      try {
        // Only try to get token count if we're not in the middle of generation
        final responseTokens = await session.sizeInTokens(response);
        _currentTokens += responseTokens;

        if (_currentTokens >= (maxTokens - tokenBuffer)) {
          await _recreateSessionWithReducedChunks();
        }
      } catch (e) {
        // If we can't get token count (e.g., session busy), estimate it
        // Rough estimation: ~4 characters per token
        final estimatedTokens = (response.length / 4).ceil();
        _currentTokens += estimatedTokens;
      }

      final chatMessage = Message(text: response, isUser: false);
      _fullHistory.add(chatMessage);
      _modelHistory.add(chatMessage);
    }
  }

  Future<void> cancelGenerateResponseAsync() async {
    if (_isGenerating) {
      try {
        await session.cancelGenerateResponseAsync();
      } catch (e) {
        // Ignore cancellation errors - the session might already be done
      } finally {
        _isGenerating = false;
        // Trigger cleanup listeners
        for (final listener in _cleanupListeners) {
          listener();
        }
      }
    }
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
    // Stop any ongoing generation first
    if (_isGenerating) {
      await cancelGenerateResponseAsync();
    }

    _modelHistory.clear();
    _currentTokens = 0;
    await session.close();
    session = await sessionCreator!();

    // Trigger cleanup listeners
    for (final listener in _cleanupListeners) {
      listener();
    }
  }

  void addCleanupListener(VoidCallback listener) {
    _cleanupListeners.add(listener);
  }

  void removeCleanupListener(VoidCallback listener) {
    _cleanupListeners.remove(listener);
  }
}
