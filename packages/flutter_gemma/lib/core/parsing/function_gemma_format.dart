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
    if (!clean.contains(functionGemmaStartCall)) return false;

    // The end tag means the model stopped, even if the body never balanced —
    // chat.dart then emits the buffer as text. Otherwise the call is finished
    // only once its own brace closes; a stop token may have cut the tag off.
    return clean.contains(functionGemmaEndCall) || _findCallBody(clean) != null;
  }

  @override
  FunctionCallResponse? parse(String text) {
    if (text.trim().isEmpty) return null;

    final call = _findCallBody(text);
    if (call == null) return null;

    return FunctionCallResponse(name: call.$1, args: _parseParams(call.$2));
  }
}

/// Locates `call:NAME{...}` and returns the name plus its balanced body, or
/// `null` while the call is still arriving.
///
/// A regex cannot delimit the body. `}` is not a terminator: it closes a nested
/// object, or sits inside an escaped string value. So `<escape>…<escape>` spans
/// are opaque here and brace depth — not the first `}` — ends the call. The
/// `<end_function_call>` tag is optional; a stop token often eats it.
(String, String)? _findCallBody(String text) {
  const callPrefix = 'call:';

  final startIndex = text.indexOf(functionGemmaStartCall);
  if (startIndex == -1) return null;

  var i = startIndex + functionGemmaStartCall.length;
  if (!text.startsWith(callPrefix, i)) return null;
  i += callPrefix.length;

  final name = _readKey(text, i);
  if (name == null) return null;
  i = name.$2;

  if (i >= text.length || text[i] != '{') return null;
  final open = i;
  var depth = 0;

  while (i < text.length) {
    if (text.startsWith(functionGemmaEscape, i)) {
      final close = text.indexOf(
        functionGemmaEscape,
        i + functionGemmaEscape.length,
      );
      if (close == -1) return null; // string value still streaming
      i = close + functionGemmaEscape.length;
      continue;
    }

    final char = text[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return (name.$1, text.substring(open + 1, i));
    }
    i++;
  }

  return null;
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

/// The only numeric shapes Python's `str()` — and so the template — can render.
/// Dart's `int.tryParse`/`double.tryParse` also accept `0x1f`, `+5`, `007`,
/// `Infinity` and `NaN`; reading those as numbers invents a type the model
/// never meant.
final _bareNumber = RegExp(r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][-+]?\d+)?$');

/// Classifies a bare (unescaped) token exactly as the template's `else` branch
/// would have rendered it. Unrecognised tokens survive as Strings.
dynamic _classifyBareToken(String token) {
  if (token == 'true') return true;
  if (token == 'false') return false;
  if (!_bareNumber.hasMatch(token)) return token;
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
