import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  final InferenceChat _chat;

  GemmaLocalService(this._chat);

  Future<void> addQuery(Message message) => _chat.addQuery(message);

  Future<dynamic> processMessage(Message message) async {
    debugPrint('GemmaLocalService: Adding query to chat: "${message.text}"');
    await _chat.addQuery(message);
    debugPrint('GemmaLocalService: Generating chat response async...');
    // Return the stream instead of awaiting full response
    return _chat.generateChatResponseAsync();
  }

  Stream<dynamic> processMessageAsync(Message message) async* {
    await _chat.addQuery(message);
    yield* _chat.generateChatResponseAsync();
  }
}
