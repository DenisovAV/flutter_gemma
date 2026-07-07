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

  test('coalesced: tool calls suppress text', () {
    final m = chatMessageFromParts(
      text: 'ignored',
      calls: const [FunctionCallResponse(name: 'f', args: {})],
    );
    expect(m.parts.whereType<ToolPart>(), hasLength(1));
    expect(m.parts.whereType<TextPart>(), isEmpty);
  });
}
