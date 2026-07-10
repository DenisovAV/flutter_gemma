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
      expect(
        prompt,
        contains(
          'enum:[<escape>red<escape>,<escape>blue<escape>,<escape>green<escape>]',
        ),
      );
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
                'title': {'type': 'string', 'description': 'The title text'},
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
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('contains FunctionGemma special tokens'),
          ),
        ),
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

      expect(() => chat.createToolsPrompt(), throwsA(isA<ArgumentError>()));
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

      expect(
        prompt,
        contains('enum:[<escape>red<escape>,<escape>blue<escape>]'),
      );
      expect(
        prompt,
        contains('enum:[<escape>small<escape>,<escape>large<escape>]'),
      );
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

      expect(
        descIndex,
        lessThan(enumIndex),
        reason: 'description should come before enum',
      );
      expect(
        enumIndex,
        lessThan(typeIndex),
        reason: 'enum should come before type',
      );
    });
  });

  // Every expectation below is a golden string rendered by FunctionGemma's own
  // `chat_template.jinja` (`format_function_declaration`). The template is the
  // spec: it sorts properties with `dictsort` (case-insensitive), emits
  // `items:{...}` for arrays, recurses into objects, and only emits `enum` for
  // STRING-typed properties.
  //
  // The template ships with the model; an ungated copy lives at
  // huggingface.co/onnx-community/functiongemma-270m-it-ONNX. To re-derive these
  // strings after a template change, render `format_function_declaration` with
  // jinja2.
  group('FunctionGemma Tools Prompt - canonical chat_template (#367)', () {
    String promptFor(
      Map<String, dynamic> properties, {
      List<String>? required,
    }) {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          Tool(
            name: 't',
            description: 'd',
            parameters: {
              'type': 'object',
              'properties': properties,
              'required': ?required,
            },
          ),
        ],
      );
      return chat.createToolsPrompt();
    }

    test('sorts properties alphabetically, not in schema order', () {
      final prompt = promptFor({
        'zebra': {'type': 'string', 'description': 'z'},
        'apple': {'type': 'string', 'description': 'a'},
      });

      expect(
        prompt,
        contains(
          'declaration:t{description:<escape>d<escape>,parameters:{properties:{'
          'apple:{description:<escape>a<escape>,type:<escape>STRING<escape>},'
          'zebra:{description:<escape>z<escape>,type:<escape>STRING<escape>}},'
          'type:<escape>OBJECT<escape>}}',
        ),
      );
    });

    test('sorts case-insensitively, matching Jinja dictsort', () {
      final prompt = promptFor({
        'Beta': {'type': 'string', 'description': 'b'},
        'alpha': {'type': 'string', 'description': 'a'},
      });

      expect(prompt.indexOf('alpha:'), lessThan(prompt.indexOf('Beta:')));
    });

    test('renders items for an array property', () {
      final prompt = promptFor({
        'exts': {
          'type': 'array',
          'description': 'e',
          'items': {'type': 'string'},
        },
      });

      expect(
        prompt,
        contains(
          'exts:{description:<escape>e<escape>,items:{type:<escape>STRING<escape>},'
          'type:<escape>ARRAY<escape>}',
        ),
      );
    });

    test('renders a number property as NUMBER', () {
      final prompt = promptFor({
        'n': {'type': 'number', 'description': 'num'},
      });

      expect(
        prompt,
        contains(
          'n:{description:<escape>num<escape>,type:<escape>NUMBER<escape>}',
        ),
      );
    });

    test('recurses into an object property with sorted nested properties', () {
      final prompt = promptFor({
        'o': {
          'type': 'object',
          'description': 'obj',
          'properties': {
            'b': {'type': 'string', 'description': 'B'},
            'a': {'type': 'string', 'description': 'A'},
          },
          'required': ['a'],
        },
      });

      expect(
        prompt,
        contains(
          'o:{description:<escape>obj<escape>,properties:{'
          'a:{description:<escape>A<escape>,type:<escape>STRING<escape>},'
          'b:{description:<escape>B<escape>,type:<escape>STRING<escape>}},'
          'required:[<escape>a<escape>],type:<escape>OBJECT<escape>}',
        ),
      );
    });

    test('renders numeric enum values bare, not escaped', () {
      final prompt = promptFor({
        's': {
          'type': 'string',
          'description': 's',
          'enum': [1, 2],
        },
      });

      expect(prompt, contains('enum:[1,2]'));
    });

    test('omits enum for a non-string property', () {
      final prompt = promptFor({
        'n': {
          'type': 'number',
          'description': 'n',
          'enum': [1, 2],
        },
      });

      expect(prompt, isNot(contains('enum:')));
    });

    test('skips properties whose name collides with a structural key', () {
      final prompt = promptFor({
        'type': {'type': 'string', 'description': 'x'},
        'ok': {'type': 'string', 'description': 'y'},
      });

      expect(
        prompt,
        contains(
          'properties:{ok:{description:<escape>y<escape>,type:<escape>STRING<escape>}}',
        ),
      );
    });

    test('emits an empty description when the property has none', () {
      final prompt = promptFor({
        'x': {'type': 'string'},
      });

      expect(
        prompt,
        contains(
          'x:{description:<escape><escape>,type:<escape>STRING<escape>}',
        ),
      );
    });

    test('single string property with enum matches the canonical output', () {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [
          const Tool(
            name: 'change_background_color',
            description: 'Changes the app background color',
            parameters: {
              'type': 'object',
              'properties': {
                'color': {
                  'type': 'string',
                  'description': 'Color name',
                  'enum': ['red', 'blue'],
                },
              },
              'required': ['color'],
            },
          ),
        ],
      );

      expect(
        chat.createToolsPrompt(),
        contains(
          'declaration:change_background_color{'
          'description:<escape>Changes the app background color<escape>,'
          'parameters:{properties:{color:{description:<escape>Color name<escape>,'
          'enum:[<escape>red<escape>,<escape>blue<escape>],'
          'type:<escape>STRING<escape>}},required:[<escape>color<escape>],'
          'type:<escape>OBJECT<escape>}}',
        ),
      );
    });
  });

  // Edge cases the template handles and we did not. Same oracle as above.
  group('FunctionGemma Tools Prompt - edge cases', () {
    String promptForParameters(
      Map<String, dynamic> parameters, {
      String name = 't',
    }) {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [Tool(name: name, description: 'd', parameters: parameters)],
      );
      return chat.createToolsPrompt();
    }

    test('rejects a union-typed property with an actionable error', () {
      expect(
        () => promptForParameters({
          'type': 'object',
          'properties': {
            'x': {
              'type': ['string', 'null'],
              'description': 'u',
            },
          },
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('union'), contains('nullable')),
          ),
        ),
      );
    });

    test('emits a parameters block for a no-argument tool', () {
      expect(
        promptForParameters({
          'type': 'object',
          'properties': <String, dynamic>{},
        }, name: 'get_time'),
        contains(
          'declaration:get_time{description:<escape>d<escape>,'
          'parameters:{type:<escape>OBJECT<escape>}}',
        ),
      );
    });

    test('emits required even when the tool declares no properties', () {
      expect(
        promptForParameters({
          'type': 'object',
          'required': ['a'],
        }),
        contains(
          'parameters:{required:[<escape>a<escape>],type:<escape>OBJECT<escape>}}',
        ),
      );
    });

    test('omits the parameters block when parameters are empty', () {
      final prompt = promptForParameters(<String, dynamic>{});
      expect(prompt, contains('declaration:t{description:<escape>d<escape>}'));
      expect(prompt, isNot(contains('parameters')));
    });

    test('rejects a property with no type instead of guessing STRING', () {
      // Guessing STRING makes the model return `<escape>5<escape>` for a
      // parameter the developer meant as a number, and the tool then receives
      // "5". A silent wrong type is worse than a loud error.
      expect(
        () => promptForParameters({
          'type': 'object',
          'properties': {
            'x': {'description': 'no type here'},
          },
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('"x"'), contains('type')),
          ),
        ),
      );
    });

    test('renders doubles the way Python does, as the template would', () {
      // The template is Jinja: numbers reach the prompt through Python's
      // `str()`. Dart switches to exponent notation at different magnitudes.
      expect(
        promptForParameters({
          'type': 'object',
          'properties': {
            'e': {
              'type': 'string',
              'description': 'x',
              'enum': [1.0, 1e16, 1e-5, 0.1, 1e21],
            },
          },
        }),
        contains('enum:[1.0,1e+16,1e-05,0.1,1e+21]'),
      );
    });

    test('keeps an empty required inside items, unlike at the object level', () {
      // The template guards empty `required` at the object level but not inside
      // `items`, so the two are not symmetric. Mirroring the object guard into
      // items silently dropped `required:[]`.
      expect(
        promptForParameters({
          'type': 'object',
          'properties': {
            'a': {
              'type': 'array',
              'description': 'x',
              'items': {'type': 'string', 'required': <String>[]},
            },
          },
        }),
        contains('items:{required:[],type:<escape>STRING<escape>}'),
      );
    });

    test('drops an empty required at the object level', () {
      expect(
        promptForParameters({
          'type': 'object',
          'properties': {
            'o': {
              'type': 'object',
              'description': 'x',
              'properties': {
                'y': {'type': 'string', 'description': 'y'},
              },
              'required': <String>[],
            },
          },
        }),
        isNot(contains('required:[]')),
      );
    });

    test('sorts stably above Dart\'s 32-element insertion-sort threshold', () {
      // Jinja's `sorted` is stable; Dart's `List.sort` switches to an unstable
      // quicksort past 32 elements. Case-insensitive ties must keep insertion
      // order, so `K07` (inserted first) stays ahead of `k07`.
      final properties = <String, dynamic>{
        for (var i = 0; i < 20; i++)
          'K${i.toString().padLeft(2, '0')}': {
            'type': 'string',
            'description': 'u',
          },
        for (var i = 0; i < 20; i++)
          'k${i.toString().padLeft(2, '0')}': {
            'type': 'string',
            'description': 'l',
          },
      };

      final prompt = promptForParameters({
        'type': 'object',
        'properties': properties,
      });

      for (var i = 0; i < 20; i++) {
        final n = i.toString().padLeft(2, '0');
        expect(
          prompt.indexOf('K$n:{'),
          lessThan(prompt.indexOf('k$n:{')),
          reason: 'tie K$n/k$n must keep insertion order',
        );
      }
    });
  });

  // Four places where the template renders something a model cannot use, and we
  // deliberately do not follow it. Pinned so nobody "restores parity" later.
  group('FunctionGemma Tools Prompt - deliberate divergences', () {
    String promptForParameters(Map<String, dynamic> parameters) {
      final chat = InferenceChat(
        sessionCreator: null,
        maxTokens: 1024,
        modelType: ModelType.functionGemma,
        supportsFunctionCalls: true,
        tools: [Tool(name: 't', description: 'd', parameters: parameters)],
      );
      return chat.createToolsPrompt();
    }

    test('an explicit null description renders empty, not the word None', () {
      // Jinja prints Python's `None` for a null description.
      expect(
        promptForParameters({
          'type': 'object',
          'properties': {
            'x': {'type': 'string', 'description': null},
          },
        }),
        contains(
          'x:{description:<escape><escape>,type:<escape>STRING<escape>}',
        ),
      );
    });

    test('parameters without a type still close the block properly', () {
      // The template leaves `parameters:{` unclosed with a trailing comma here.
      expect(
        promptForParameters({
          'properties': {
            'x': {'type': 'string', 'description': 'x'},
          },
        }),
        contains(',type:<escape>OBJECT<escape>}}'),
      );
    });

    test('a stray key on an object property is not promoted to a property', () {
      // The template falls back to iterating the schema itself when it has no
      // `properties`, which turns `additionalProperties` into a fake parameter.
      final prompt = promptForParameters({
        'type': 'object',
        'properties': {
          'o': {
            'type': 'object',
            'description': 'x',
            'additionalProperties': false,
          },
        },
      });

      expect(
        prompt,
        contains('o:{description:<escape>x<escape>,properties:{}'),
      );
      expect(prompt, isNot(contains('additionalProperties')));
    });

    test('a non-map property schema is skipped, not rendered degenerate', () {
      final prompt = promptForParameters({
        'type': 'object',
        'properties': {
          'bad': true,
          'ok': {'type': 'string', 'description': 'y'},
        },
      });

      expect(prompt, isNot(contains('bad')));
      expect(prompt, contains('properties:{ok:'));
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
