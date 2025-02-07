const userPrefix = "user";
const modelPrefix = "model";
const startTurn = "<start_of_turn>";
const endTurn = "<end_of_turn>";

extension MessageExtension on String {
  String transformToChatPrompt() => '$startTurn$userPrefix\n$this$endTurn$startTurn$modelPrefix';
}
