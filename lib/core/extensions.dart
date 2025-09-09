import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';

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

  // Helper method to format tool response content
  String _formatToolResponseContent() {
    if (type == MessageType.toolResponse) {
      return '<tool_response>\n'
          'Tool Name: $toolName\n'
          'Tool Response:\n$text\n'
          '</tool_response>';
    }
    return text;
  }

  String _transformGeneral() {
    if (isUser) {
      final content = _formatToolResponseContent();
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
      final content = _formatToolResponseContent();
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
      final content = _formatToolResponseContent();
      return '$deepseekStart$deepseekUser$content$deepseekAssistant';
    } else {
      return text;
    }
  }
}

// Filter class for thinking models
class ModelThinkingFilter {
  /// Filters ModelResponse stream for models with thinking support
  /// Only supports DeepSeek models with <think>...</think> blocks
  static Stream<ModelResponse> filterThinkingStream(Stream<ModelResponse> originalStream, {required ModelType modelType}) async* {
    switch (modelType) {
      case ModelType.deepSeek:
        // Apply DeepSeek thinking filtration
        // ⚠️ IMPORTANT: DeepSeek STARTS with thinking, ENDS with </think>!
        bool insideThinking = true;
        StringBuffer thinkingBuffer = StringBuffer();

        await for (final response in originalStream) {
          if (response is TextResponse) {
            String token = response.token;

            if (insideThinking) {
              // Check for thinking block end
              if (token.contains('</think>')) {
                // Add text before </think> to thinking
                final beforeEnd = token.split('</think>')[0];
                if (beforeEnd.isNotEmpty) {
                  thinkingBuffer.write(beforeEnd);
                }

                // Send completed thinking block
                if (thinkingBuffer.isNotEmpty) {
                  yield ThinkingResponse(thinkingBuffer.toString());
                }

                // Switch to normal mode
                insideThinking = false;

                // Process text after </think> - pass as regular text for function call parsing
                final afterEnd = token.split('</think>').skip(1).join('</think>');
                if (afterEnd.isNotEmpty) {
                  yield TextResponse(afterEnd);
                }
              } else {
                // Accumulate thinking content
                thinkingBuffer.write(token);
                // Send intermediate thinking
                yield ThinkingResponse(token);
              }
            } else {
              // Normal mode - pass tokens as is for function call parsing
              yield response;
            }
          } else {
            // For FunctionCallResponse and other types just pass without changes
            yield response;
          }
        }
        break;

      case ModelType.general:
      case ModelType.gemmaIt:
        // For all other models just pass original stream
        // Thinking not supported
        yield* originalStream;
        break;
    }
  }

  /// Removes thinking blocks from final text
  /// Only supports DeepSeek (<think>...</think>) models
  static String removeThinkingFromText(String text, {required ModelType modelType}) {
    switch (modelType) {
      case ModelType.deepSeek:
        // Remove all <think>...</think> blocks (DeepSeek specific)
        RegExp thinkingRegex = RegExp(r'<think>.*?</think>', dotAll: true);
        return text.replaceAll(thinkingRegex, '').trim();

      case ModelType.general:
      case ModelType.gemmaIt:
        // For all other models return text without changes
        // Thinking not supported
        return text;
    }
  }

  /// Cleans model response from service tags and thinking blocks
  static String cleanResponse(String response, {required bool isThinking, required ModelType modelType}) {
    String cleaned = response;

    // Remove <think> blocks if model supports thinking
    if (isThinking) {
      cleaned = removeThinkingFromText(cleaned, modelType: modelType);
    }

    switch (modelType) {
      case ModelType.general:
      case ModelType.gemmaIt:
        // Remove trailing <end_of_turn> tags and trim whitespace
        return cleaned.replaceAll(RegExp(r'<end_of_turn>\s*$'), '').trim();

      case ModelType.deepSeek:
        // DeepSeek doesn't use <end_of_turn>, just trim whitespace
        return cleaned.trim();
    }
  }
}
