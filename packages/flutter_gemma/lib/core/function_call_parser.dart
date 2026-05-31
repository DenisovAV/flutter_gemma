import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/parsing/function_call_format.dart';
import 'package:flutter_gemma/core/parsing/function_call_format_factory.dart';

/// Facade for backward compatibility.
/// Delegates to model-specific [FunctionCallFormat] implementations.
class FunctionCallParser {
  /// Check if buffer starts with function call indicators
  static bool isFunctionCallStart(String buffer, {ModelType? modelType}) {
    return FunctionCallFormatFactory.create(modelType)
        .isFunctionCallStart(buffer);
  }

  /// DEPRECATED: Use isFunctionCallStart instead
  @Deprecated('Use isFunctionCallStart with modelType parameter')
  static bool isJsonStart(String buffer) {
    return isFunctionCallStart(buffer);
  }

  /// Checks if buffer looks definitely like text (not a function call)
  static bool isDefinitelyText(String buffer, {ModelType? modelType}) {
    return FunctionCallFormatFactory.create(modelType).isDefinitelyText(buffer);
  }

  /// Check if function call structure is complete
  static bool isFunctionCallComplete(String buffer, {ModelType? modelType}) {
    return FunctionCallFormatFactory.create(modelType)
        .isFunctionCallComplete(buffer);
  }

  /// DEPRECATED: Use isFunctionCallComplete instead
  @Deprecated('Use isFunctionCallComplete with modelType parameter')
  static bool isJsonComplete(String buffer) {
    return isFunctionCallComplete(buffer);
  }

  /// Parse a single function call based on model type
  static FunctionCallResponse? parse(String text, {ModelType? modelType}) {
    if (text.trim().isEmpty) return null;

    try {
      return FunctionCallFormatFactory.create(modelType).parse(text);
    } catch (e) {
      debugPrint('FunctionCallParser: Error parsing function call: $e');
      return null;
    }
  }

  /// Parse all function calls from text (for parallel tool calls)
  static List<FunctionCallResponse> parseAll(String text,
      {ModelType? modelType}) {
    if (text.trim().isEmpty) return [];

    try {
      return FunctionCallFormatFactory.create(modelType).parseAll(text);
    } catch (e) {
      debugPrint('FunctionCallParser: Error parsing function calls: $e');
      return [];
    }
  }
}
