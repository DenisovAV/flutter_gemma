import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  final InferenceChat _chat;

  GemmaLocalService(this._chat);

  Future<void> addQuery(Message message) => _chat.addQuery(message);

  /// Process message and return stream - TEMPORARILY USING SYNC for debugging!
  Future<Stream<ModelResponse>> processMessage(Message message) async {
    debugPrint('GemmaLocalService: processMessage() called with: "${message.text}"');
    debugPrint('GemmaLocalService: Adding query to chat: "${message.text}"');
    await _chat.addQuery(message);
    debugPrint('GemmaLocalService: TEMP DEBUG: Using SYNC method instead of async');

    // TEMPORARILY use sync method to debug image issue
    final response = await _chat.generateChatResponse();
    debugPrint('GemmaLocalService: SYNC response received: ${response.runtimeType}');

    // Convert single response to stream for compatibility
    return Stream.fromIterable([response]);
  }

  /// Legacy method for backward compatibility - ALSO USING SYNC for debugging
  Stream<ModelResponse> processMessageAsync(Message message) async* {
    await _chat.addQuery(message);
    debugPrint('GemmaLocalService: Legacy method also using SYNC for debugging');
    final response = await _chat.generateChatResponse();
    yield response;
  }
}
