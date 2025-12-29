import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';

const userPrefix = "user";
const modelPrefix = "model";
const developerPrefix = "developer"; // FunctionGemma uses developer role for tools
const startTurn = "<start_of_turn>";
const endTurn = "<end_of_turn>";

const deepseekStart = "<｜begin▁of▁sentence｜>";
const deepseekUser = "<｜User｜>";
const deepseekAssistant = "<｜Assistant｜>";

// Qwen tokens
const qwenStart = "<|im_start|>";
const qwenEnd = "<|im_end|>";

// Llama tokens
const llamaInstStart = "[INST]";
const llamaInstEnd = "[/INST]";

// Hammer tokens (using general format for now - need more research)
const hammerUser = "User:";
const hammerAssistant = "Assistant:";

// FunctionGemma special tokens
const functionGemmaStartCall = '<start_function_call>';
const functionGemmaEndCall = '<end_function_call>';
const functionGemmaStartDecl = '<start_function_declaration>';
const functionGemmaEndDecl = '<end_function_declaration>';
const functionGemmaStartResp = '<start_function_response>';
const functionGemmaEndResp = '<end_function_response>';
const functionGemmaEscape = '<escape>';

extension MessageExtension on Message {
  String transformToChatPrompt(
      {ModelType type = ModelType.general, ModelFileType fileType = ModelFileType.binary}) {
    // DEBUG LOG
    debugPrint('[transformToChatPrompt] modelType=$type, fileType=$fileType, messageType=${this.type}, isUser=$isUser');

    // System messages should not be sent to the model
    if (this.type == MessageType.systemInfo) {
      return '';
    }

    // .task files - MediaPipe handles templates, return raw content
    // EXCEPT FunctionGemma which needs manual formatting (no prefix/suffix in .task)
    if (fileType == ModelFileType.task && type != ModelType.functionGemma) {
      final result = _formatToolResponseContent();
      debugPrint('[transformToChatPrompt] Using _formatToolResponseContent, result length=${result.length}');
      return result;
    }

    // .bin/.tflite files - apply manual formatting based on model type
    final result = switch (type) {
      ModelType.general => _transformGeneral(),
      ModelType.gemmaIt => _transformGemmaIt(),
      ModelType.deepSeek => _transformDeepSeek(),
      ModelType.qwen => _transformQwen(),
      ModelType.llama => _transformLlama(),
      ModelType.hammer => _transformHammer(),
      ModelType.functionGemma => _transformFunctionGemma(),
    };
    return result;
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

  String _transformQwen() {
    if (isUser) {
      final content = _formatToolResponseContent();
      return '$qwenStart$userPrefix\n$content$qwenEnd\n$qwenStart$modelPrefix\n';
    }
    var content = text;
    if (type == MessageType.toolCall) {
      content = text;
    }
    return '$content$qwenEnd\n';
  }

  String _transformLlama() {
    if (isUser) {
      final content = _formatToolResponseContent();
      return '$llamaInstStart $content $llamaInstEnd';
    }
    return text;
  }

  String _transformHammer() {
    if (isUser) {
      final content = _formatToolResponseContent();
      return '$hammerUser $content\n$hammerAssistant ';
    }
    return text;
  }

  String _transformFunctionGemma() {
    // If text already has turn markers (from chat.dart with tools), return as is
    if (text.startsWith(startTurn)) {
      return text;
    }

    // Handle tool response - NO user turn, goes directly after function call
    // Per FunctionGemma docs: <end_function_call><start_function_response>...
    if (type == MessageType.toolResponse) {
      final content = _formatFunctionGemmaContent();
      return '$content\n$startTurn$modelPrefix\n';
    }

    if (isUser) {
      final content = _formatFunctionGemmaContent();
      return '$startTurn$userPrefix\n$content$endTurn\n$startTurn$modelPrefix\n';
    }
    return '$text$endTurn\n';
  }

  String _formatFunctionGemmaContent() {
    // Format tool response in FunctionGemma format
    if (type == MessageType.toolResponse && toolName != null) {
      return '$functionGemmaStartResp'
             'response:$toolName{result:$functionGemmaEscape$text$functionGemmaEscape}'
             '$functionGemmaEndResp';
    }
    return text;
  }
}

// Filter class for thinking models
class ModelThinkingFilter {
  /// Filters ModelResponse stream for models with thinking support
  /// Only supports DeepSeek models with <think>...</think> blocks
  static Stream<ModelResponse> filterThinkingStream(Stream<ModelResponse> originalStream,
      {required ModelType modelType}) async* {
    switch (modelType) {
      case ModelType.deepSeek:
        // Apply DeepSeek thinking filtration
        // DeepSeek starts with thinking content, ends with </think>
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
      case ModelType.qwen:
      case ModelType.llama:
      case ModelType.hammer:
      case ModelType.functionGemma:
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
      case ModelType.qwen:
      case ModelType.llama:
      case ModelType.hammer:
      case ModelType.functionGemma:
        // For all other models return text without changes
        // Thinking not supported
        return text;
    }
  }

  /// Cleans model response from service tags and thinking blocks
  static String cleanResponse(String response,
      {required bool isThinking, required ModelType modelType, required ModelFileType fileType}) {
    String cleaned = response;

    // Remove <think> blocks if model supports thinking
    if (isThinking) {
      cleaned = removeThinkingFromText(cleaned, modelType: modelType);
    }

    // For .task files, minimal cleaning - MediaPipe handles formatting
    if (fileType == ModelFileType.task) {
      return cleaned.trim();
    }

    // For .bin/.tflite files, apply model-specific cleaning
    switch (modelType) {
      case ModelType.general:
        // General models - no special cleaning needed
        return cleaned.trim();
      case ModelType.gemmaIt:
        // Remove trailing <end_of_turn> tags and trim whitespace
        return cleaned.replaceAll(RegExp(r'<end_of_turn>\\s*\$'), '').trim();
      case ModelType.qwen:
        // Remove trailing <|im_end|> tags and trim whitespace
        return cleaned.replaceAll(RegExp(r'<\\|im_end\\|>\\s*\$'), '').trim();
      case ModelType.llama:
      case ModelType.hammer:
      case ModelType.deepSeek:
      case ModelType.functionGemma:
        // These models don't use special end tags, just trim whitespace
        return cleaned.trim();
    }
  }
}
