import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  final InferenceChat _chat;
  bool _isProcessing = false;

  GemmaLocalService(this._chat);

  bool get isProcessing => _isProcessing;

  Future<void> addQueryChunk(Message message) => _chat.addQueryChunk(message);

  Stream<String> processMessageAsync(Message message) async* {
    if (_isProcessing) {
      throw StateError(
          'Already processing a message. Cancel current generation first.');
    }

    _isProcessing = true;
    try {
      await _chat.addQueryChunk(message);
      yield* _chat.generateChatResponseAsync();
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> cancelGenerateResponseAsync() async {
    if (_isProcessing) {
      await _chat.cancelGenerateResponseAsync();
      _isProcessing = false;
    }
  }
}
