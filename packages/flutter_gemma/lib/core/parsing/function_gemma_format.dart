import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/model_response.dart';

import 'function_call_format.dart';

/// FunctionGemma proprietary format.
///
/// Format: `<start_function_call>call:name{param:<escape>value<escape>}<end_function_call>`
///
/// Used by: ModelType.functionGemma
class FunctionGemmaCallFormat extends FunctionCallFormat {
  @override
  bool isFunctionCallStart(String buffer) {
    return buffer.trim().startsWith(functionGemmaStartCall);
  }

  @override
  bool isDefinitelyText(String buffer) {
    final clean = buffer.trim();
    if (clean.length < 5) return false;
    if (isFunctionCallStart(buffer)) return false;

    final early = clean.length > 30 ? clean.substring(0, 30) : clean;
    return !early.contains(functionGemmaStartCall);
  }

  @override
  bool isFunctionCallComplete(String buffer) {
    final clean = buffer.trim();
    if (clean.isEmpty) return false;

    // Complete if has end tag OR if has start tag and ends with }
    // (stop_token may cut off <end_function_call>)
    return (clean.contains(functionGemmaStartCall) &&
            clean.contains(functionGemmaEndCall)) ||
        (clean.contains(functionGemmaStartCall) && clean.endsWith('}'));
  }

  @override
  FunctionCallResponse? parse(String text) {
    if (text.trim().isEmpty) return null;

    // First try with end tag
    var regex = RegExp(
      r'<start_function_call>call:(\w+)\{(.*?)\}<end_function_call>',
      multiLine: true,
      dotAll: true,
    );
    var match = regex.firstMatch(text);

    // If not found, try without end tag (stop_token may cut it off)
    if (match == null) {
      regex = RegExp(
        r'<start_function_call>call:(\w+)\{(.*?)\}',
        multiLine: true,
        dotAll: true,
      );
      match = regex.firstMatch(text);
    }

    if (match == null) return null;

    final functionName = match.group(1)!;
    final paramsStr = match.group(2)!;

    final params = <String, dynamic>{};
    final paramRegex = RegExp(r'(\w+):<escape>(.*?)<escape>');
    for (final paramMatch in paramRegex.allMatches(paramsStr)) {
      params[paramMatch.group(1)!] = paramMatch.group(2)!;
    }

    return FunctionCallResponse(name: functionName, args: params);
  }
}
