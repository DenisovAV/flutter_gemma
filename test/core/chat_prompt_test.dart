import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';

void main() {
  group('FunctionGemma Tools Prompt - Enum Support', () {
    test('generates prompt with enum values', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'change_color',
            description: 'Changes the color',
            parameters: {
              'type': 'object',
              'properties': {
                'color': {
                  'type': 'string',
                  'enum': ['red', 'blue', 'green'],
                  'description': 'The color name',
                },
              },
              'required': ['color'],
            },
          ),
        ],
      );

      final prompt = chat.createToolsPrompt();

      // Check enum format: enum:[<escape>red<escape>,<escape>blue<escape>,<escape>green<escape>]
      expect(prompt, contains('enum:[<escape>red<escape>,<escape>blue<escape>,<escape>green<escape>]'));
      expect(prompt, contains('description:<escape>The color name<escape>'));
      expect(prompt, contains('type:<escape>STRING<escape>'));
    });

    test('generates prompt without enum when not provided', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'set_title',
            description: 'Sets the title',
            parameters: {
              'type': 'object',
              'properties': {
                'title': {
                  'type': 'string',
                  'description': 'The title text',
                },
              },
              'required': ['title'],
            },
          ),
        ],
      );

      final prompt = chat.createToolsPrompt();

      expect(prompt, isNot(contains('enum:')));
      expect(prompt, contains('type:<escape>STRING<escape>'));
    });

    test('skips enum field when enum array is empty', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'test_func',
            description: 'Test function',
            parameters: {
              'type': 'object',
              'properties': {
                'value': {
                  'type': 'string',
                  'enum': <String>[], // Empty array
                  'description': 'Some value',
                },
              },
            },
          ),
        ],
      );

      final prompt = chat.createToolsPrompt();

      expect(prompt, isNot(contains('enum:')));
    });

    test('throws ArgumentError for enum values with special tokens', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'bad_func',
            description: 'Bad function',
            parameters: {
              'type': 'object',
              'properties': {
                'value': {
                  'type': 'string',
                  'enum': ['normal', '<escape>malicious'],
                  'description': 'Value with injection attempt',
                },
              },
            },
          ),
        ],
      );

      expect(
        () => chat.createToolsPrompt(),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('contains FunctionGemma special tokens'),
        )),
      );
    });

    test('throws ArgumentError for enum values with start token', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'bad_func',
            description: 'Bad function',
            parameters: {
              'type': 'object',
              'properties': {
                'value': {
                  'type': 'string',
                  'enum': ['<start_function_call>'],
                  'description': 'Injection attempt',
                },
              },
            },
          ),
        ],
      );

      expect(
        () => chat.createToolsPrompt(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles multiple parameters with enums', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'set_style',
            description: 'Sets the style',
            parameters: {
              'type': 'object',
              'properties': {
                'color': {
                  'type': 'string',
                  'enum': ['red', 'blue'],
                  'description': 'Color',
                },
                'size': {
                  'type': 'string',
                  'enum': ['small', 'large'],
                  'description': 'Size',
                },
              },
            },
          ),
        ],
      );

      final prompt = chat.createToolsPrompt();

      expect(prompt, contains('enum:[<escape>red<escape>,<escape>blue<escape>]'));
      expect(prompt, contains('enum:[<escape>small<escape>,<escape>large<escape>]'));
    });

    test('preserves field order: description, enum, type', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'test',
            description: 'Test',
            parameters: {
              'type': 'object',
              'properties': {
                'color': {
                  'type': 'string',
                  'enum': ['red'],
                  'description': 'Color',
                },
              },
            },
          ),
        ],
      );

      final prompt = chat.createToolsPrompt();

      // Find the color parameter block
      final colorStart = prompt.indexOf('color:{');
      final colorEnd = prompt.indexOf('}', colorStart);
      final colorBlock = prompt.substring(colorStart, colorEnd + 1);

      // Verify order: description comes before enum, enum comes before type
      final descIndex = colorBlock.indexOf('description:');
      final enumIndex = colorBlock.indexOf('enum:');
      final typeIndex = colorBlock.indexOf('type:');

      expect(descIndex, lessThan(enumIndex), reason: 'description should come before enum');
      expect(enumIndex, lessThan(typeIndex), reason: 'enum should come before type');
    });
  });

  group('JSON Tools Prompt (other models)', () {
    test('includes enum in JSON format for non-FunctionGemma models', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.gemmaIt,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'change_color',
            description: 'Changes the color',
            parameters: {
              'type': 'object',
              'properties': {
                'color': {
                  'type': 'string',
                  'enum': ['red', 'blue', 'green'],
                  'description': 'The color name',
                },
              },
            },
          ),
        ],
      );

      final prompt = chat.createToolsPrompt();

      // JSON format preserves enum as JSON array
      expect(prompt, contains('"enum":["red","blue","green"]'));
    });
  });
}
