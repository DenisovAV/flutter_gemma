import 'dart:convert';

import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';

/// Parser for LiteRT-LM SDK Chat Completions JSON responses.
///
/// Used by [InferenceChat] when the active session backend exposes
/// `lastRawResponse` (FFI/LiteRT-LM path with structured `tool_calls`).
/// The SDK already converts native `<|tool_call>...<tool_call|>` Gemma 4
/// tokens into OpenAI-style JSON via `chat_template.jinja` + minja, so this
/// helper just walks the JSON and surfaces [FunctionCallResponse]s.
///
/// Parsing rules mirror upstream Python `Conversation._handle_tool_calls`
/// (`python/litert_lm/conversation.py`).
class SdkResponseParser {
  /// Extract all function calls from an SDK response JSON string.
  ///
  /// Accepts the structural variants observed in the wild:
  /// 1. Top-level `tool_calls` list (Gemma 4 standard path).
  /// 2. `content` array entries with `type: "tool_call"` (multimodal).
  /// 3. Concatenated multi-document JSON — when the model emits two or more
  ///    `<|tool_call>...<tool_call|>` blocks, the SDK serializes them as
  ///    separate `{role:assistant,tool_calls:[...]}{role:assistant,tool_calls:[...]}`
  ///    documents back-to-back rather than wrapping them in an array. We split
  ///    on top-level `}{` boundaries and parse each fragment.
  ///
  /// Each call element may be either OpenAI-style
  /// (`{type: "function", function: {name, arguments}}`) or flat
  /// (`{name, arguments}`) — both accepted.
  ///
  /// String values inside `arguments` (and nested maps/lists) are stripped of
  /// the `<|"|>` Gemma 4 escape token, which leaks through SDK parsing.
  static List<FunctionCallResponse> extractToolCalls(String jsonStr) {
    final result = <FunctionCallResponse>[];
    for (final fragment in _splitConcatenatedJson(jsonStr)) {
      final Map<String, dynamic> json;
      try {
        final parsed = jsonDecode(fragment);
        if (parsed is! Map<String, dynamic>) continue;
        json = parsed;
      } on FormatException {
        continue;
      }
      _harvestCalls(json, result);
    }
    return result;
  }

  /// Split a string that may be one JSON object or a concatenation of multiple
  /// top-level objects (e.g. `{...}{...}`). Tracks brace depth while ignoring
  /// braces inside string literals so it doesn't false-cut on `"a{b}"`.
  static Iterable<String> _splitConcatenatedJson(String input) sync* {
    int depth = 0;
    int start = -1;
    bool inString = false;
    bool escape = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == r'\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          yield input.substring(start, i + 1);
          start = -1;
        }
      }
    }
  }

  static void _harvestCalls(
      Map<String, dynamic> json, List<FunctionCallResponse> out) {
    void addFromCallObject(Object? raw) {
      if (raw is! Map<String, dynamic>) return;
      Map<String, dynamic>? fn;
      if (raw['type'] == 'function' && raw['function'] is Map<String, dynamic>) {
        fn = raw['function'] as Map<String, dynamic>;
      } else if (raw['name'] is String) {
        fn = raw;
      }
      if (fn == null) return;
      final name = fn['name'] as String?;
      if (name == null) return;
      final rawArgs = fn['arguments'];
      final args = rawArgs is Map<String, dynamic>
          ? _stripEscapeTokens(rawArgs) as Map<String, dynamic>
          : <String, dynamic>{};
      out.add(FunctionCallResponse(name: name, args: args));
    }

    final topLevel = json['tool_calls'] as List<dynamic>?;
    if (topLevel != null) {
      for (final call in topLevel) {
        addFromCallObject(call);
      }
    }

    final content = json['content'] as List<dynamic>?;
    if (content != null) {
      for (final item in content) {
        if (item is Map<String, dynamic> && item['type'] == 'tool_call') {
          addFromCallObject(item['tool_call']);
        }
      }
    }
  }

  /// Recursively strip Gemma 4 `<|"|>` escape tokens from string values.
  ///
  /// Workaround for an SDK quirk observed on macOS GPU 2026-04-29 where
  /// minja-rendered escape tokens leak into the parsed `arguments` map (e.g.
  /// `"<|\"|>red<|\"|>"` instead of `"red"`). Walks Maps and Lists so nested
  /// argument values are also cleaned.
  static dynamic _stripEscapeTokens(dynamic value) {
    if (value is String) return value.replaceAll('<|"|>', '');
    if (value is Map) {
      return value
          .map((k, v) => MapEntry(k as String, _stripEscapeTokens(v)));
    }
    if (value is List) return value.map(_stripEscapeTokens).toList();
    return value;
  }

  /// Clean a raw SDK response JSON string by recursively stripping
  /// `<|"|>` escape tokens. Used by `chat.dart` before writing the
  /// assistant turn into chat history — without this the next request
  /// echoes the escape tokens back to the model and Gemma 4 starts
  /// reproducing them in subsequent `tool_calls` arguments (#248).
  ///
  /// Returns the cleaned JSON string, or the input unchanged if it isn't
  /// valid JSON (the caller falls back to writing the raw string in that
  /// case).
  static String cleanRawForHistory(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      return jsonEncode(_stripEscapeTokens(decoded));
    } on FormatException {
      return rawJson;
    }
  }

  /// Serialize [tools] into the OpenAI Chat Completions JSON format that
  /// LiteRT-LM SDK expects in `litert_lm_conversation_config_set_tools`.
  /// SDK then applies `chat_template.jinja` (via minja) to render native
  /// Gemma 4 `<|tool>declaration:...<tool|>` tokens.
  ///
  /// Reference: upstream `c/engine_test.cc::CreateConversationConfigWithTools`.
  static String serializeToolsForSdk(List<Tool> tools) => jsonEncode([
        for (final tool in tools)
          {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parameters,
            },
          },
      ]);

  /// Build the JSON message that delivers a tool execution result back to
  /// the model on the next turn. Format mirrors upstream Python
  /// `serve.py::gemini_to_litertlm_message` and Gemma 4 data processor's
  /// `FormatToolResponse`.
  ///
  /// SDK then renders this as native
  /// `<|tool_response>response:NAME{...}<tool_response|>` tokens.
  static String buildToolResponseJson({
    required String toolName,
    required Object? response,
    String? toolCallId,
  }) =>
      jsonEncode({
        'role': 'tool',
        'content': [
          {
            'name': toolName,
            'response': response,
          },
        ],
        if (toolCallId != null) 'tool_call_id': toolCallId,
      });
}
