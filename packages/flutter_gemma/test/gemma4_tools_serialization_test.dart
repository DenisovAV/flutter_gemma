import 'dart:convert';

import 'package:flutter_gemma/core/parsing/sdk_response_parser.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SdkResponseParser.serializeToolsForSdk', () {
    test('single tool produces OpenAI Chat Completions JSON', () {
      const tools = [
        Tool(
          name: 'change_color',
          description: 'Change UI background color',
          parameters: {
            'type': 'object',
            'properties': {
              'color': {'type': 'string'},
            },
            'required': ['color'],
          },
        ),
      ];
      final raw = SdkResponseParser.serializeToolsForSdk(tools);
      final decoded = jsonDecode(raw) as List<dynamic>;
      expect(decoded, hasLength(1));
      expect(decoded.first, isA<Map<String, dynamic>>());
      final entry = decoded.first as Map<String, dynamic>;
      expect(entry['type'], equals('function'));
      expect(entry['function'], isA<Map<String, dynamic>>());
      final fn = entry['function'] as Map<String, dynamic>;
      expect(fn['name'], equals('change_color'));
      expect(fn['description'], equals('Change UI background color'));
      expect(fn['parameters'], equals(tools.first.parameters));
    });

    test('multiple tools — order preserved, each wrapped', () {
      const tools = [
        Tool(name: 'first', description: 'First tool', parameters: {}),
        Tool(name: 'second', description: 'Second tool', parameters: {}),
      ];
      final decoded =
          jsonDecode(SdkResponseParser.serializeToolsForSdk(tools)) as List;
      expect(decoded, hasLength(2));
      expect((decoded[0] as Map)['function']['name'], equals('first'));
      expect((decoded[1] as Map)['function']['name'], equals('second'));
      for (final entry in decoded) {
        expect((entry as Map)['type'], equals('function'));
      }
    });
  });

  group('SdkResponseParser.buildToolResponseJson', () {
    test('Map response wraps in role:tool content array', () {
      final raw = SdkResponseParser.buildToolResponseJson(
        toolName: 'get_weather',
        response: {'temp': 72, 'unit': 'F'},
        toolCallId: 'call_42',
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['role'], equals('tool'));
      expect(decoded['tool_call_id'], equals('call_42'));
      final content = decoded['content'] as List;
      expect(content, hasLength(1));
      final entry = content.first as Map<String, dynamic>;
      expect(entry['name'], equals('get_weather'));
      expect(entry['response'], equals({'temp': 72, 'unit': 'F'}));
    });

    test('String response — toolCallId omitted when null', () {
      final raw = SdkResponseParser.buildToolResponseJson(
        toolName: 'echo',
        response: 'OK',
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.containsKey('tool_call_id'), isFalse);
      expect((decoded['content'] as List).first['response'], equals('OK'));
    });
  });
}
