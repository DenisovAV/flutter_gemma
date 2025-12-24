import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';

/// Unified parser for function calls in all formats:
/// - Direct JSON: {"name": "function_name", "parameters": {...}}
/// - Markdown blocks: ```json\n{"name": ...}\n```
/// - Tool code blocks: <tool_code>{"name": ...}</tool_code>
class FunctionCallParser {
  /// Check if buffer starts with function call indicators
  /// Uses ModelType for explicit format detection
  static bool isFunctionCallStart(String buffer, {ModelType? modelType}) {
    final clean = buffer.trim();
    if (clean.isEmpty) return false;

    return switch (modelType) {
      ModelType.functionGemma => clean.startsWith(functionGemmaStartCall),
      _ => clean.startsWith('{') ||
           clean.startsWith('```json') ||
           clean.startsWith('```') ||
           clean.startsWith('<tool_code>'),
    };
  }

  /// DEPRECATED: Use isFunctionCallStart instead
  @Deprecated('Use isFunctionCallStart with modelType parameter')
  static bool isJsonStart(String buffer) {
    return isFunctionCallStart(buffer);
  }

  /// Checks if buffer looks definitely like text (not JSON)
  static bool isDefinitelyText(String buffer) {
    final clean = buffer.trim();

    // Need at least 5 characters to be confident
    if (clean.length < 5) return false;

    // If it starts with JSON indicators, it's not text
    if (isFunctionCallStart(buffer)) return false;

    // If no JSON patterns in first 30 chars, it's text
    final early = clean.length > 30 ? clean.substring(0, 30) : clean;
    return !early.contains('{') &&
        !early.toLowerCase().contains('json') &&
        !early.contains('<tool');
  }

  /// Check if function call structure is complete
  static bool isFunctionCallComplete(String buffer, {ModelType? modelType}) {
    final clean = buffer.trim();
    if (clean.isEmpty) return false;

    return switch (modelType) {
      ModelType.functionGemma =>
          // Complete if has end tag OR if has start tag and ends with }
          // (stop_token may cut off <end_function_call>)
          (clean.contains(functionGemmaStartCall) &&
              clean.contains(functionGemmaEndCall)) ||
          (clean.contains(functionGemmaStartCall) &&
              clean.endsWith('}')),
      _ => _isJsonComplete(clean),
    };
  }

  static bool _isJsonComplete(String clean) {
    // Direct JSON: starts with { and ends with }
    if (clean.startsWith('{') && clean.endsWith('}')) {
      return _isBalancedJson(clean);
    }
    // Markdown/tool_code blocks
    if (clean.contains('```json') && clean.endsWith('```')) return true;
    if (clean.contains('<tool_code>') && clean.contains('</tool_code>')) return true;
    return false;
  }

  /// DEPRECATED: Use isFunctionCallComplete instead
  @Deprecated('Use isFunctionCallComplete with modelType parameter')
  static bool isJsonComplete(String buffer) {
    return isFunctionCallComplete(buffer);
  }

  /// Parse function call based on model type
  /// Uses explicit ModelType routing - no fallback chains
  static FunctionCallResponse? parse(String text, {ModelType? modelType}) {
    if (text.trim().isEmpty) return null;

    try {
      final content = _cleanModelResponse(text);

      // Explicit routing by model type using Dart 3 switch expression
      return switch (modelType) {
        ModelType.functionGemma => _parseFunctionGemmaCall(content),
        // All other models use JSON-based formats
        _ => _parseToolCodeBlock(content) ??
             _parseMarkdownBlock(content) ??
             _parseDirectJson(content),
      };
    } catch (e) {
      debugPrint('FunctionCallParser: Error parsing function call: $e');
      return null;
    }
  }

  /// Remove model response wrappers
  static String _cleanModelResponse(String response) {
    // Remove <start_of_turn>model...content...<end_of_turn> wrappers
    final turnRegex = RegExp(r'<start_of_turn>model\s*([\s\S]*?)<end_of_turn>');
    if (turnRegex.hasMatch(response)) {
      return turnRegex.firstMatch(response)!.group(1)!.trim();
    }

    // Remove trailing <end_of_turn> tags
    return response.replaceAll(RegExp(r'<end_of_turn>\s*$'), '').trim();
  }

  /// Parse <tool_code>JSON</tool_code> format
  static FunctionCallResponse? _parseToolCodeBlock(String content) {
    final regex = RegExp(r'<tool_code>\s*([\s\S]*?)\s*</tool_code>', multiLine: true);
    final match = regex.firstMatch(content);

    if (match != null) {
      final jsonStr = match.group(1)!.trim();
      debugPrint('FunctionCallParser: Found tool_code block: $jsonStr');
      return _parseJsonString(jsonStr);
    }

    return null;
  }

  /// Parse ```json\nJSON\n``` or ```\nJSON\n``` format
  static FunctionCallResponse? _parseMarkdownBlock(String content) {
    // Try specific ```json first
    var regex = RegExp(r'```json\s*([\s\S]*?)\s*```', multiLine: true);
    var match = regex.firstMatch(content);

    if (match != null) {
      final jsonStr = match.group(1)!.trim();
      debugPrint('FunctionCallParser: Found markdown json block: $jsonStr');
      return _parseJsonString(jsonStr);
    }

    // Try generic ``` blocks
    regex = RegExp(r'```\s*([\s\S]*?)\s*```', multiLine: true);
    match = regex.firstMatch(content);

    if (match != null) {
      final jsonStr = match.group(1)!.trim();
      // Only parse if it looks like JSON
      if (jsonStr.startsWith('{') && jsonStr.contains('"name"')) {
        debugPrint('FunctionCallParser: Found markdown code block: $jsonStr');
        return _parseJsonString(jsonStr);
      }
    }

    return null;
  }

  /// Parse direct JSON format
  static FunctionCallResponse? _parseDirectJson(String content) {
    final trimmed = content.trim();

    // Must start with { and contain "name" to be considered
    if (trimmed.startsWith('{') && trimmed.contains('"name"')) {
      debugPrint('FunctionCallParser: Found direct JSON: $trimmed');
      return _parseJsonString(trimmed);
    }

    return null;
  }

  /// Parse JSON string into FunctionCall
  static FunctionCallResponse? _parseJsonString(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);

      if (decoded is Map<String, dynamic>) {
        final name = decoded['name'] as String?;
        final parameters = decoded['parameters'] as Map<String, dynamic>?;

        if (name != null && parameters != null) {
          final functionCall = FunctionCallResponse(name: name, args: parameters);
          debugPrint(
              'FunctionCallParser: Successfully parsed function: ${functionCall.name}(${functionCall.args})');
          return functionCall;
        }

        // Fallback: try 'args' instead of 'parameters'
        final args = decoded['args'] as Map<String, dynamic>?;
        if (name != null && args != null) {
          final functionCall = FunctionCallResponse(name: name, args: args);
          debugPrint(
              'FunctionCallParser: Successfully parsed function with args: ${functionCall.name}(${functionCall.args})');
          return functionCall;
        }
      }

      debugPrint('FunctionCallParser: JSON missing required fields (name/parameters)');
      return null;
    } catch (e) {
      debugPrint('FunctionCallParser: Failed to decode JSON: $e');
      return null;
    }
  }

  /// Parse FunctionGemma format:
  /// <start_function_call>call:name{param:<escape>value<escape>}<end_function_call>
  /// Also handles case where <end_function_call> is missing (stop token cuts it off)
  static FunctionCallResponse? _parseFunctionGemmaCall(String content) {
    // First try with end tag
    var regex = RegExp(
      r'<start_function_call>call:(\w+)\{(.*?)\}<end_function_call>',
      multiLine: true,
      dotAll: true,
    );

    var match = regex.firstMatch(content);

    // If not found, try without end tag (stop_token may cut it off)
    if (match == null) {
      regex = RegExp(
        r'<start_function_call>call:(\w+)\{(.*?)\}',
        multiLine: true,
        dotAll: true,
      );
      match = regex.firstMatch(content);
    }

    if (match == null) return null;

    final functionName = match.group(1)!;
    final paramsStr = match.group(2)!;

    // Parse parameters: param:<escape>value<escape>,param2:<escape>value2<escape>
    final params = <String, dynamic>{};
    final paramRegex = RegExp(r'(\w+):<escape>(.*?)<escape>');

    for (final paramMatch in paramRegex.allMatches(paramsStr)) {
      final key = paramMatch.group(1)!;
      final value = paramMatch.group(2)!;
      params[key] = value;
    }

    return FunctionCallResponse(name: functionName, args: params);
  }

  /// Fast check for balanced braces without full JSON parsing
  static bool _isBalancedJson(String str) {
    int braceCount = 0;
    bool inString = false;
    bool escaped = false;
    bool hasSeenOpenBrace = false;

    for (int i = 0; i < str.length; i++) {
      final char = str[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char == '\\') {
        escaped = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (!inString) {
        if (char == '{') {
          braceCount++;
          hasSeenOpenBrace = true;
        } else if (char == '}') {
          braceCount--;
          if (braceCount < 0) return false; // More closing than opening
        }
      }
    }

    // JSON is complete if braces are balanced and we've seen at least one opening brace
    return braceCount == 0 && hasSeenOpenBrace;
  }
}
