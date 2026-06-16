import 'package:flutter_gemma/core/model_response.dart';

/// Strategy interface for model-specific function call parsing.
///
/// Each model family uses a different format for tool/function calls.
/// Implementations handle detection, completion checking, and parsing
/// for their specific format.
abstract class FunctionCallFormat {
  /// Check if buffer starts with a function call indicator.
  bool isFunctionCallStart(String buffer);

  /// Check if buffer content is definitely plain text (not a function call).
  bool isDefinitelyText(String buffer);

  /// Check if the function call structure is complete and ready to parse.
  bool isFunctionCallComplete(String buffer);

  /// Parse a single function call from text.
  /// Returns null if not a valid function call.
  FunctionCallResponse? parse(String text);

  /// Parse all function calls from text (for parallel tool calls).
  /// Default implementation delegates to [parse] for single call.
  List<FunctionCallResponse> parseAll(String text) {
    final result = parse(text);
    return result != null ? [result] : [];
  }
}
