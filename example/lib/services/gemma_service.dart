import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  final InferenceChat _chat;

  GemmaLocalService(this._chat);

  Future<void> addQuery(Message message) => _chat.addQuery(message);

  /// Process message and return stream - back to direct streaming!
  Future<Stream<ModelResponse>> processMessage(Message message) async {
    debugPrint('GemmaLocalService: processMessage() called with: "${message.text}"');
    debugPrint('GemmaLocalService: Adding query to chat: "${message.text}"');
    await _chat.addQuery(message);
    debugPrint('GemmaLocalService: Using direct InferenceChat stream (function handling: integrated)');

    // Return direct stream from InferenceChat - no more intermediate processing!
    return _chat.generateChatResponseAsync();
  }

  /// Legacy method for backward compatibility
  Stream<ModelResponse> processMessageAsync(Message message) async* {
    await _chat.addQuery(message);
    yield* _chat.generateChatResponseAsync();
  }
}
