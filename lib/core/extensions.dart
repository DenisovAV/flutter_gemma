import 'dart:convert';
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
    // System messages should not be sent to the model
    if (this.type == MessageType.systemInfo) {
      return '';
    }

    switch (type) {
      case ModelType.general:
        return _transformGeneral();

      case ModelType.gemmaIt:
        return _transformGemmaIt();

      case ModelType.deepSeek:
        return _transformDeepSeek();
    }
  }

  String _transformGeneral() {
    if (isUser) {
      var content = text;
      if (type == MessageType.toolResponse) {
        content = '<tool_response>\n'
            'Tool Name: $toolName\n'
            'Tool Response:\n$text\n'
            '</tool_response>';
      }
      return '$startTurn$userPrefix\n$content$endTurn';
    }

    // Handle model responses
    var content = text;
    if (type == MessageType.toolCall) {
      // The text already contains the full <tool_code> block
      content = text;
    }
    return '$startTurn$modelPrefix\n$content$endTurn';
  }

  String _transformGemmaIt() {
    if (isUser) {
      var content = text;
      if (type == MessageType.toolResponse) {
        content = '<tool_response>\n'
            'Tool Name: $toolName\n'
            'Tool Response:\n$text\n'
            '</tool_response>';
      }
      return '$startTurn$userPrefix\n$content$endTurn\n$startTurn$modelPrefix\n';
    }

    // Handle model responses - for GemmaIt format
    var content = text;
    if (type == MessageType.toolCall) {
      content = text;
    }
    return '$content$endTurn\n';
  }

  String _transformDeepSeek() {
    if (isUser) {
      var content = text;
      if (type == MessageType.toolResponse) {
        content = '<tool_response>\n'
            'Tool Name: $toolName\n'
            'Tool Response:\n$text\n'
            '</tool_response>';
      }
      return '$deepseekStart$deepseekUser$content$deepseekAssistant';
    } else {
      return text;
    }
  }
}
