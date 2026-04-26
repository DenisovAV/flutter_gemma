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
      ModelType.qwen3 => _transformQwen(),
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
  /// Supports DeepSeek/Qwen3 (`<think>...</think>`) and Gemma 4 (`<|channel>thought\n...<channel|>`).
  static Stream<ModelResponse> filterThinkingStream(
      Stream<ModelResponse> originalStream,
      {required ModelType modelType}) async* {
    switch (modelType) {
      case ModelType.deepSeek:
        // DeepSeek starts in thinking mode (no opening <think> tag).
        // Uses buffer to handle partial </think> across token boundaries.
        const endTag = '</think>';
        bool dsInside = true;
        String dsBuffer = '';

        await for (final response in originalStream) {
          if (response is TextResponse) {
            dsBuffer += response.token;

            while (dsBuffer.isNotEmpty) {
              if (dsInside) {
                final endIdx = dsBuffer.indexOf(endTag);
                if (endIdx >= 0) {
                  final thinking = dsBuffer.substring(0, endIdx);
                  if (thinking.isNotEmpty) {
                    yield ThinkingResponse(thinking);
                  }
                  dsBuffer = dsBuffer.substring(endIdx + endTag.length);
                  dsInside = false;
                } else {
                  final partial = _findPartialSuffix(dsBuffer, endTag);
                  final safe = dsBuffer.substring(0, dsBuffer.length - partial);
                  if (safe.isNotEmpty) {
                    yield ThinkingResponse(safe);
                  }
                  dsBuffer = dsBuffer.substring(dsBuffer.length - partial);
                  break;
                }
              } else {
                yield TextResponse(dsBuffer);
                dsBuffer = '';
                break;
              }
            }
          } else {
            yield response;
          }
        }
        if (dsBuffer.isNotEmpty) {
          yield dsInside ? ThinkingResponse(dsBuffer) : TextResponse(dsBuffer);
        }
        break;

      case ModelType.qwen:
      case ModelType.qwen3:
        // Qwen3 emits <think>...</think>, Qwen2.5 emits nothing.
        // Starts insideThinking=false — safe for non-thinking models.
        // Uses buffer to handle partial tags across token boundaries.
        const startTag = '<think>';
        const endTag = '</think>';
        bool qwenInside = false;
        String qwenBuffer = '';

        await for (final response in originalStream) {
          if (response is TextResponse) {
            qwenBuffer += response.token;

            while (qwenBuffer.isNotEmpty) {
              if (qwenInside) {
                final endIdx = qwenBuffer.indexOf(endTag);
                if (endIdx >= 0) {
                  final thinking = qwenBuffer.substring(0, endIdx);
                  if (thinking.isNotEmpty) {
                    yield ThinkingResponse(thinking);
                  }
                  qwenBuffer = qwenBuffer.substring(endIdx + endTag.length);
                  qwenInside = false;
                } else {
                  final partial = _findPartialSuffix(qwenBuffer, endTag);
                  final safe =
                      qwenBuffer.substring(0, qwenBuffer.length - partial);
                  if (safe.isNotEmpty) {
                    yield ThinkingResponse(safe);
                  }
                  qwenBuffer =
                      qwenBuffer.substring(qwenBuffer.length - partial);
                  break;
                }
              } else {
                final startIdx = qwenBuffer.indexOf(startTag);
                if (startIdx >= 0) {
                  final textBefore = qwenBuffer.substring(0, startIdx);
                  if (textBefore.isNotEmpty) {
                    yield TextResponse(textBefore);
                  }
                  qwenBuffer = qwenBuffer.substring(startIdx + startTag.length);
                  qwenInside = true;
                } else {
                  final partial = _findPartialSuffix(qwenBuffer, startTag);
                  final safe =
                      qwenBuffer.substring(0, qwenBuffer.length - partial);
                  if (safe.isNotEmpty) {
                    yield TextResponse(safe);
                  }
                  qwenBuffer =
                      qwenBuffer.substring(qwenBuffer.length - partial);
                  break;
                }
              }
            }
          } else {
            yield response;
          }
        }
        if (qwenBuffer.isNotEmpty) {
          yield qwenInside
              ? ThinkingResponse(qwenBuffer)
              : TextResponse(qwenBuffer);
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
  /// Supports DeepSeek/Qwen3 (`<think>...</think>`) and Gemma 4 (`<|channel>thought\n...<channel|>`).
  /// Note: For streaming thinking output, use [filterThinkingStream] with generateChatResponseAsync() instead.
  static String removeThinkingFromText(String text,
      {required ModelType modelType}) {
    switch (modelType) {
      case ModelType.deepSeek:
      case ModelType.qwen:
      case ModelType.qwen3:
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

    // Strip thinking tags for models that may generate them
    final bool modelCanThink = modelType == ModelType.deepSeek ||
        modelType == ModelType.qwen ||
        modelType == ModelType.qwen3 ||
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
      case ModelType.qwen3:
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
