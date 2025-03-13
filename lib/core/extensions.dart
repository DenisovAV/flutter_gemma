import 'package:flutter_gemma/core/message.dart';

const userPrefix = "user";
const modelPrefix = "model";
const startTurn = "<start_of_turn>";
const endTurn = "<end_of_turn>";

extension MessageExtension on Message {
  String transformToChatPrompt() => isUser ? '$startTurn$userPrefix\n$text$endTurn\n$startTurn$modelPrefix\n' : '$text$endTurn\n';
}
