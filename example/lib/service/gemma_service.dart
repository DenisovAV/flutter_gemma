import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  Future<String> processChatMessage(List<Message> messages) {
    return FlutterGemmaPlugin.instance.initializedModel!.getChatResponse(messages: messages);
  }

  Stream<String> processChatMessageAsync(List<Message> messages) {
    return FlutterGemmaPlugin.instance.initializedModel!.getChatResponseAsync(messages: messages);
  }

  Future<String> processMessage(Message message) {
    return FlutterGemmaPlugin.instance.initializedModel!.getResponse(prompt: message.text);
  }

  Stream<String> processMessageAsync(Message message) {
    return FlutterGemmaPlugin.instance.initializedModel!.getResponseAsync(prompt: message.text);
  }
}
