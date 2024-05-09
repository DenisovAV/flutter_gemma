import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  Future<String?> processMessage(List<Message> messages) {
    return FlutterGemmaPlugin.instance.getChatResponse(messages: messages);
  }

  Stream<String?> processMessageAsync(List<Message> messages) {
    return FlutterGemmaPlugin.instance.getChatResponseAsync(messages: messages);
  }
}
