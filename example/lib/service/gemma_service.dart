import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaLocalService {
  InferenceModelSession get _session => FlutterGemmaPlugin.instance.initializedModel!.session!;
  
  Future<String> processMessage(Message message) {
    return _session.getResponse(message.text);
  }

  Stream<String> processMessageAsync(Message message) {
    return _session.getResponseAsync(message.text);
  }
}
