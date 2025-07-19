import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/chat_response_handler.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  final InferenceChat _chat;
  late final ChatResponseHandler _responseHandler;

  GemmaLocalService(this._chat) {
    _responseHandler = ChatResponseHandler(_chat);
  }

  Future<void> addQuery(Message message) => _chat.addQuery(message);

  /// Process message and return stream (maintaining original signature)
  Future<Stream<dynamic>> processMessage(Message message) async {
    debugPrint('GemmaLocalService: Adding query to chat: "${message.text}"');
    await _chat.addQuery(message);
    debugPrint('GemmaLocalService: Using ChatResponseHandler for ASYNC processing (function handling: ON)');
    
    // Use async mode with function handling enabled for testing
    return _responseHandler.processResponse(async: true, handleFunctions: true).map((event) {
      if (event is FunctionCallEvent) {
        return event.call;
      } else if (event is TextTokenEvent) {
        return event.token;
      } else if (event is TextCompleteEvent) {
        return event.fullText;
      } else if (event is ErrorEvent) {
        throw Exception(event.error);
      }
      return event.toString();
    });
  }

  /// Legacy method for backward compatibility
  Stream<dynamic> processMessageAsync(Message message) async* {
    await _chat.addQuery(message);
    yield* _chat.generateChatResponseAsync();
  }
}
