import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/core/message.dart';
import 'package:flutter_gemma_example/core/message_utils.dart';

class GemmaLocalService {
  Future<String?> processMessage(List<Message> messages) {
    final prompt = messages.last.text.prepareQuestion();
    return FlutterGemmaPlugin.instance.getResponse(prompt: prompt);
  }

  Stream<String?> processMessageAsync(List<Message> messages) {
    final prompt = messages.last.text.prepareQuestion();
    return FlutterGemmaPlugin.instance.getResponseAsync(prompt: prompt);
  }
}
