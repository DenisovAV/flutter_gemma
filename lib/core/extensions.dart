import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';

const userPrefix = "user";
const modelPrefix = "model";
const developerPrefix =
    "developer"; // FunctionGemma uses developer role for tools
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
      {ModelType type = ModelType.general,
      ModelFileType fileType = ModelFileType.binary}) {
    // DEBUG LOG
    debugPrint(
        '[transformToChatPrompt] modelType=$type, fileType=$fileType, messageType=${this.type}, isUser=$isUser');

    // System messages should not be sent to the model
    if (this.type == MessageType.systemInfo) {
      return '';
    }

    // .task files - MediaPipe handles templates, return raw content
    // EXCEPT FunctionGemma which needs manual formatting (no prefix/suffix in .task)
    if (fileType == ModelFileType.task && type != ModelType.functionGemma) {
      final result = _formatToolResponseContent();
      debugPrint(
          '[transformToChatPrompt] Using _formatToolResponseContent, result length=${result.length}');
      return result;
    }

    // .litertlm files - platform-dependent behavior
    if (fileType == ModelFileType.litertlm) {
      // iOS: MediaPipe doesn't handle turn markers for .litertlm → format manually (like binary)
      // Android/Desktop/Web: LiteRT-LM SDK handles templates → return raw text (like task)
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        // Fall through to manual formatting below
      } else {
        final result = _formatToolResponseContent();
        debugPrint(
            '[transformToChatPrompt] litertlm non-iOS, using raw text, result length=${result.length}');
        return result;
      }
    }

    // .bin/.tflite files (and .litertlm on iOS) - apply manual formatting based on model type
    final result = switch (type) {
      ModelType.general => _transformGeneral(),
      ModelType.gemmaIt => _transformGemmaIt(),
      ModelType.deepSeek => _transformDeepSeek(),
      ModelType.qwen => _transformQwen(),
      ModelType.llama => _transformLlama(),
      ModelType.hammer => _transformHammer(),
      ModelType.functionGemma => _transformFunctionGemma(),
      ModelType.phi => _transformGeneral(),
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
  /// Filters ModelResponse stream for models with thinking support.
  /// Supports DeepSeek (`<think>...</think>`) and Gemma 4 (`<|channel>thought\n...<channel|>`) models.
  static Stream<ModelResponse> filterThinkingStream(
      Stream<ModelResponse> originalStream,
      {required ModelType modelType}) async* {
    switch (modelType) {
      case ModelType.deepSeek:
        // DeepSeek starts with raw thinking (no opening <think> tag), ends with </think>
        bool insideThinking = true;
        StringBuffer thinkingBuffer = StringBuffer();

        await for (final response in originalStream) {
          if (response is TextResponse) {
            String token = response.token;

            if (insideThinking) {
              if (token.contains('</think>')) {
                final beforeEnd = token.split('</think>')[0];
                if (beforeEnd.isNotEmpty) {
                  thinkingBuffer.write(beforeEnd);
                }
                if (thinkingBuffer.isNotEmpty) {
                  yield ThinkingResponse(thinkingBuffer.toString());
                }
                insideThinking = false;
                final afterEnd =
                    token.split('</think>').skip(1).join('</think>');
                if (afterEnd.isNotEmpty) {
                  yield TextResponse(afterEnd);
                }
              } else {
                thinkingBuffer.write(token);
                yield ThinkingResponse(token);
              }
            } else {
              yield response;
            }
          } else {
            yield response;
          }
        }
        break;

      case ModelType.qwen:
        // Qwen3 emits <think>...</think>, Qwen2.5 emits nothing.
        // Start insideThinking=false — only enter thinking when <think> is found.
        bool qwenInsideThinking = false;
        StringBuffer qwenThinkingBuffer = StringBuffer();

        await for (final response in originalStream) {
          if (response is TextResponse) {
            String token = response.token;

            if (qwenInsideThinking) {
              if (token.contains('</think>')) {
                final beforeEnd = token.split('</think>')[0];
                if (beforeEnd.isNotEmpty) {
                  qwenThinkingBuffer.write(beforeEnd);
                  yield ThinkingResponse(beforeEnd);
                }
                qwenInsideThinking = false;
                qwenThinkingBuffer.clear();
                final afterEnd =
                    token.split('</think>').skip(1).join('</think>');
                if (afterEnd.isNotEmpty) {
                  yield TextResponse(afterEnd);
                }
              } else {
                qwenThinkingBuffer.write(token);
                yield ThinkingResponse(token);
              }
            } else {
              if (token.contains('<think>')) {
                final beforeStart = token.split('<think>')[0];
                if (beforeStart.isNotEmpty) {
                  yield TextResponse(beforeStart);
                }
                qwenInsideThinking = true;
                qwenThinkingBuffer.clear();
                final afterStart =
                    token.split('<think>').skip(1).join('<think>');
                if (afterStart.isNotEmpty) {
                  if (afterStart.contains('</think>')) {
                    final thinking = afterStart.split('</think>')[0];
                    if (thinking.isNotEmpty) {
                      yield ThinkingResponse(thinking);
                    }
                    qwenInsideThinking = false;
                    final afterEnd =
                        afterStart.split('</think>').skip(1).join('</think>');
                    if (afterEnd.isNotEmpty) {
                      yield TextResponse(afterEnd);
                    }
                  } else {
                    qwenThinkingBuffer.write(afterStart);
                    yield ThinkingResponse(afterStart);
                  }
                }
              } else {
                // No thinking tags — pass through as text (Qwen2.5 path)
                yield response;
              }
            }
          } else {
            yield response;
          }
        }
        break;

      case ModelType.gemmaIt:
        // Gemma 4 E2B/E4B: <|channel>thought\n...<channel|>
        const startMarker = '<|channel>thought\n';
        const endMarker = '<channel|>';
        bool gemmaInsideThinking = false;
        String gemmaBuffer = '';

        await for (final response in originalStream) {
          if (response is TextResponse) {
            gemmaBuffer += response.token;

            while (gemmaBuffer.isNotEmpty) {
              if (gemmaInsideThinking) {
                final endIdx = gemmaBuffer.indexOf(endMarker);
                if (endIdx >= 0) {
                  final thinkingContent = gemmaBuffer.substring(0, endIdx);
                  if (thinkingContent.isNotEmpty) {
                    yield ThinkingResponse(thinkingContent);
                  }
                  gemmaBuffer =
                      gemmaBuffer.substring(endIdx + endMarker.length);
                  gemmaInsideThinking = false;
                } else {
                  // Check for partial end marker at tail
                  final partial = _findPartialSuffix(gemmaBuffer, endMarker);
                  final safe =
                      gemmaBuffer.substring(0, gemmaBuffer.length - partial);
                  if (safe.isNotEmpty) {
                    yield ThinkingResponse(safe);
                  }
                  gemmaBuffer =
                      gemmaBuffer.substring(gemmaBuffer.length - partial);
                  break;
                }
              } else {
                final startIdx = gemmaBuffer.indexOf(startMarker);
                if (startIdx >= 0) {
                  final textBefore = gemmaBuffer.substring(0, startIdx);
                  if (textBefore.isNotEmpty) {
                    yield TextResponse(textBefore);
                  }
                  gemmaBuffer =
                      gemmaBuffer.substring(startIdx + startMarker.length);
                  gemmaInsideThinking = true;
                } else {
                  // Check for partial start marker at tail
                  final partial = _findPartialSuffix(gemmaBuffer, startMarker);
                  final safe =
                      gemmaBuffer.substring(0, gemmaBuffer.length - partial);
                  if (safe.isNotEmpty) {
                    yield TextResponse(safe);
                  }
                  gemmaBuffer =
                      gemmaBuffer.substring(gemmaBuffer.length - partial);
                  break;
                }
              }
            }
          } else {
            yield response;
          }
        }
        // Flush remaining buffer
        if (gemmaBuffer.isNotEmpty) {
          yield gemmaInsideThinking
              ? ThinkingResponse(gemmaBuffer)
              : TextResponse(gemmaBuffer);
        }
        break;

      case ModelType.general:
      case ModelType.llama:
      case ModelType.hammer:
      case ModelType.functionGemma:
      case ModelType.phi:
        // For all other models just pass original stream
        // Thinking not supported
        yield* originalStream;
        break;
    }
  }

  /// Removes thinking blocks from final text.
  /// Supports DeepSeek (`<think>...</think>`) and Gemma 4 (`<|channel>thought\n...<channel|>`) models.
  /// Note: For streaming thinking output, use [filterThinkingStream] with generateChatResponseAsync() instead.
  static String removeThinkingFromText(String text,
      {required ModelType modelType}) {
    switch (modelType) {
      case ModelType.deepSeek:
      case ModelType.qwen:
        // Remove all <think>...</think> blocks (DeepSeek/Qwen3 format)
        RegExp thinkingRegex = RegExp(r'<think>.*?</think>', dotAll: true);
        return text.replaceAll(thinkingRegex, '').trim();

      case ModelType.gemmaIt:
        // Remove all <|channel>thought\n...<channel|> blocks (Gemma 4 E2B/E4B)
        return text
            .replaceAll(
                RegExp(r'<\|channel>thought\n.*?<channel\|>', dotAll: true), '')
            .trim();

      case ModelType.general:
      case ModelType.llama:
      case ModelType.hammer:
      case ModelType.functionGemma:
      case ModelType.phi:
        // For all other models return text without changes
        // Thinking not supported
        return text;
    }
  }

  /// Cleans model response from service tags and thinking blocks
  static String cleanResponse(String response,
      {required bool isThinking,
      required ModelType modelType,
      required ModelFileType fileType}) {
    String cleaned = response;

    // Always strip thinking tags for models that may generate them (Qwen3, DeepSeek, Gemma 4)
    final bool modelCanThink = modelType == ModelType.deepSeek ||
        modelType == ModelType.qwen ||
        modelType == ModelType.gemmaIt;
    if (isThinking || modelCanThink) {
      cleaned = removeThinkingFromText(cleaned, modelType: modelType);
    }

    // For .task files, minimal cleaning - MediaPipe handles formatting
    if (fileType == ModelFileType.task) {
      return cleaned.trim();
    }

    // For .litertlm files - platform-dependent cleaning
    if (fileType == ModelFileType.litertlm) {
      // iOS: MediaPipe doesn't strip turn markers → clean like binary
      // Android/Desktop/Web: LiteRT-LM SDK handles cleanup → just trim
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        // Fall through to model-specific cleaning below
      } else {
        return cleaned.trim();
      }
    }

    // For .bin/.tflite files (and .litertlm on iOS), apply model-specific cleaning
    switch (modelType) {
      case ModelType.general:
        // General models - no special cleaning needed
        return cleaned.trim();
      case ModelType.gemmaIt:
        // Remove trailing <end_of_turn> tags and trim whitespace
        return cleaned.replaceAll(RegExp(r'<end_of_turn>\s*$'), '').trim();
      case ModelType.qwen:
        // Remove trailing <|im_end|> tags and trim whitespace
        return cleaned.replaceAll(RegExp(r'<\|im_end\|>\s*$'), '').trim();
      case ModelType.llama:
      case ModelType.hammer:
      case ModelType.deepSeek:
      case ModelType.functionGemma:
      case ModelType.phi:
        // These models don't use special end tags, just trim whitespace
        return cleaned.trim();
    }
  }

  /// Returns length of the longest suffix of [text] that is a prefix of [marker].
  static int _findPartialSuffix(String text, String marker) {
    for (int i = marker.length.clamp(0, text.length); i >= 1; i--) {
      if (text.endsWith(marker.substring(0, i))) {
        return i;
      }
    }
    return 0;
  }
}
