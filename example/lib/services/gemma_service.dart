import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  final InferenceChat _chat;

  GemmaLocalService(this._chat);

  Future<void> addQueryChunk(Message message) => _chat.addQueryChunk(message);

  Stream<String> processMessageAsync(Message message) async* {
    await _chat.addQueryChunk(message);
    yield* _chat.generateChatResponseAsync();
  }
}
