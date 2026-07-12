import 'package:flutter_gemma/genai.dart';
import 'package:flutter_gemma/core/genai/genai_output_converter.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TextResponse chunk → model ChatMessage with one TextPart', () {
    final m = chatMessageFromChunk(const TextResponse('hi'));
    expect(m.role, ChatMessageRole.model);
    expect(m.parts.whereType<TextPart>().single.text, 'hi');
  });

  test('ThinkingResponse chunk → ThinkingPart', () {
    final m = chatMessageFromChunk(const ThinkingResponse('reason'));
    expect(m.parts.whereType<ThinkingPart>().single.text, 'reason');
  });

  test('FunctionCallResponse chunk → ToolPart.call', () {
    final m = chatMessageFromChunk(
      const FunctionCallResponse(name: 'calc', args: {'a': 1}),
    );
    final tp = m.parts.whereType<ToolPart>().single;
    expect(tp.kind, ToolPartKind.call);
    expect(tp.toolName, 'calc');
  });

  test('coalesced: thinking + text order', () {
    final m = chatMessageFromParts(text: 'answer', thinking: 'think');
    expect(m.parts.first, isA<ThinkingPart>());
    expect(m.parts.whereType<TextPart>().single.text, 'answer');
  });

  test('coalesced: preamble text is kept alongside tool calls', () {
    // The batch fold must not silently drop a "Let me check…" preamble when a
    // tool call is present — the streaming path keeps it, so both must agree.
    final m = chatMessageFromParts(
      text: 'let me check',
      calls: const [FunctionCallResponse(name: 'f', args: {})],
    );
    expect(m.parts.whereType<TextPart>().single.text, 'let me check');
    expect(m.parts.whereType<ToolPart>(), hasLength(1));
    // Order follows generation: text precedes the tool call.
    final textAt = m.parts.indexWhere((p) => p is TextPart);
    final callAt = m.parts.indexWhere((p) => p is ToolPart);
    expect(textAt, lessThan(callAt));
  });
}
