import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';

const userPrefix = "user";
const modelPrefix = "model";
const startTurn = "<start_of_turn>";
const endTurn = "<end_of_turn>";

const deepseekStart = "<｜begin▁of▁sentence｜>";
const deepseekUser = "<｜User｜>";
const deepseekAssistant = "<｜Assistant｜>";

extension MessageExtension on Message {
  String transformToChatPrompt({ModelType type = ModelType.general}) {
    switch (type) {
      case ModelType.general:
        return text;

      case ModelType.gemmaIt:
        return isUser
            ? '$startTurn$userPrefix\n$text$endTurn\n$startTurn$modelPrefix\n'
            : '$text$endTurn\n';

      case ModelType.deepSeek:
        if (isUser) {
          return '$deepseekStart$deepseekUser$text$deepseekAssistant';
        } else {
          return text;
        }
    }
  }
}
