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

    return FunctionCallResponse(
      name: functionName,
      args: _parseParams(paramsStr),
    );
  }
}

// ---------------------------------------------------------------------------
// Argument parsing
//
// Mirrors the `format_argument` macro of FunctionGemma's own
// `chat_template.jinja` (invoked with `escape_keys=False` for call arguments):
//
//   string  -> <escape>text<escape>
//   boolean -> bare `true` / `false`
//   number  -> bare `42`, `-3`, `1.5`, `-0.25`
//   list    -> `[item,item]`   (items recurse)
//   object  -> `{key:value}`   (bare keys, items recurse)
//
// A regex cannot do this: an escaped string may itself contain `,`, `[` or `]`,
// and objects nest. So we walk the argument list once with a cursor. Anything
// we cannot classify is kept verbatim as a String rather than silently dropped.
// ---------------------------------------------------------------------------

bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F; // _

bool _isValueEnd(String c) => c == ',' || c == ']' || c == '}';

int _skipWhitespace(String src, int i) {
  while (i < src.length && src[i].trim().isEmpty) {
    i++;
  }
  return i;
}

/// Reads a `\w+` identifier starting at [i]. Returns `null` when there is none.
(String, int)? _readKey(String src, int i) {
  final start = i;
  while (i < src.length && _isWordChar(src.codeUnitAt(i))) {
    i++;
  }
  if (i == start) return null;
  return (src.substring(start, i), i);
}

/// Classifies a bare (unescaped) token exactly as the template's `else` branch
/// would have rendered it. Unrecognised tokens survive as Strings.
dynamic _classifyBareToken(String token) {
  if (token == 'true') return true;
  if (token == 'false') return false;
  return int.tryParse(token) ?? double.tryParse(token) ?? token;
}

/// Parses one value starting at [i]; returns the value and the next index.
(dynamic, int) _parseValue(String src, int i) {
  i = _skipWhitespace(src, i);
  if (i >= src.length) return ('', i);

  // Escaped string: consumes up to its own closing marker, so embedded
  // commas/brackets are preserved.
  if (src.startsWith(functionGemmaEscape, i)) {
    final start = i + functionGemmaEscape.length;
    final end = src.indexOf(functionGemmaEscape, start);
    if (end == -1) return (src.substring(start), src.length);
    return (src.substring(start, end), end + functionGemmaEscape.length);
  }

  if (src[i] == '[') {
    final list = <dynamic>[];
    i = _skipWhitespace(src, i + 1);
    if (i < src.length && src[i] == ']') return (list, i + 1);
    while (i < src.length) {
      final (value, next) = _parseValue(src, i);
      list.add(value);
      i = _skipWhitespace(src, next);
      if (i < src.length && src[i] == ',') {
        i++;
        continue;
      }
      if (i < src.length && src[i] == ']') return (list, i + 1);
      break;
    }
    return (list, i);
  }

  if (src[i] == '{') {
    final map = <String, dynamic>{};
    i = _skipWhitespace(src, i + 1);
    if (i < src.length && src[i] == '}') return (map, i + 1);
    while (i < src.length) {
      i = _skipWhitespace(src, i);
      final key = _readKey(src, i);
      if (key == null) break;
      i = _skipWhitespace(src, key.$2);
      if (i >= src.length || src[i] != ':') break;
      final (value, next) = _parseValue(src, i + 1);
      map[key.$1] = value;
      i = _skipWhitespace(src, next);
      if (i < src.length && src[i] == ',') {
        i++;
        continue;
      }
      if (i < src.length && src[i] == '}') return (map, i + 1);
      break;
    }
    return (map, i);
  }

  final start = i;
  while (i < src.length && !_isValueEnd(src[i])) {
    i++;
  }
  return (_classifyBareToken(src.substring(start, i).trim()), i);
}

/// Parses the `{...}` body of a function call into typed arguments.
Map<String, dynamic> _parseParams(String src) {
  final params = <String, dynamic>{};
  var i = 0;
  while (i < src.length) {
    i = _skipWhitespace(src, i);
    final key = _readKey(src, i);
    if (key == null) break;
    i = _skipWhitespace(src, key.$2);
    if (i >= src.length || src[i] != ':') break;
    final (value, next) = _parseValue(src, i + 1);
    params[key.$1] = value;
    i = _skipWhitespace(src, next);
    if (i < src.length && src[i] == ',') i++;
  }
  return params;
}
