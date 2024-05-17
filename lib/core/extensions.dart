import 'package:flutter_gemma/core/message.dart';

const userPrefix = "user";
const modelPrefix = "model";
const startTurn = "<start_of_turn>";
const endTurn = "<end_of_turn>";

extension MessageExtension on Iterable<Message> {
  String transformToChatPrompt({
    int contextLength = 4,
  }) =>
      skip(length <= contextLength ? 0 : length - contextLength)
          .map((e) => '$startTurn${e.isUser ? userPrefix : modelPrefix}\n${e.text}$endTurn')
          .join('\n');
}
