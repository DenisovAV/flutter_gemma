import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  Future<String> processMessage(Message message) {
    return FlutterGemmaPlugin.instance.initializedModel!.getResponse(prompt: message.text);
  }

  Stream<String> processMessageAsync(Message message) {
    return FlutterGemmaPlugin.instance.initializedModel!.getResponseAsync(prompt: message.text);
  }
}
