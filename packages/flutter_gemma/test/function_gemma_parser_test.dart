import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/function_call_parser.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';

void main() {
  group('FunctionGemma Parser', () {
    test('parses function call with single parameter', () {
      const input =
          '<start_function_call>call:get_weather{location:<escape>San Francisco<escape>}<end_function_call>';

      final result = FunctionCallParser.parse(
        input,
        modelType: ModelType.functionGemma,
      );

      expect(result, isNotNull);
      expect(result!.name, equals('get_weather'));
      expect(result.args['location'], equals('San Francisco'));
    });

    test('parses function call with multiple parameters', () {
      const input =
          '<start_function_call>call:get_weather{location:<escape>Tokyo<escape>,unit:<escape>celsius<escape>}<end_function_call>';

      final result = FunctionCallParser.parse(
        input,
        modelType: ModelType.functionGemma,
      );

      expect(result, isNotNull);
      expect(result!.name, equals('get_weather'));
      expect(result.args['location'], equals('Tokyo'));
      expect(result.args['unit'], equals('celsius'));
    });

    test('returns null for invalid format', () {
      const input = 'Just some regular text';

      final result = FunctionCallParser.parse(
        input,
        modelType: ModelType.functionGemma,
      );

      expect(result, isNull);
    });

    test('isFunctionCallStart detects FunctionGemma format', () {
      expect(
        FunctionCallParser.isFunctionCallStart(
          '<start_function_call>call:test',
          modelType: ModelType.functionGemma,
        ),
        isTrue,
      );
    });

    test('isFunctionCallStart does not detect JSON for FunctionGemma', () {
      expect(
        FunctionCallParser.isFunctionCallStart(
          '{"name": "test"}',
          modelType: ModelType.functionGemma,
        ),
        isFalse,
      );
    });

    test('isFunctionCallComplete detects complete FunctionGemma call', () {
      const input = '<start_function_call>call:test{}<end_function_call>';

      expect(
        FunctionCallParser.isFunctionCallComplete(
          input,
          modelType: ModelType.functionGemma,
        ),
        isTrue,
      );
    });

    test('isFunctionCallComplete returns false for incomplete call', () {
      const input = '<start_function_call>call:test{param:<escape>value';

      expect(
        FunctionCallParser.isFunctionCallComplete(
          input,
          modelType: ModelType.functionGemma,
        ),
        isFalse,
      );
    });
  });

  // Argument shapes below are golden strings rendered by FunctionGemma's own
  // `chat_template.jinja` (its `format_argument` macro, `escape_keys=False`):
  //   string  -> <escape>value<escape>
  //   number  -> bare (42, -3, 1.5, -0.25)
  //   boolean -> bare (true / false)
  //   list    -> [item,item]  (items recurse: strings escaped, numbers bare)
  //   object  -> {key:value}  (bare keys, alphabetically sorted)
  //
  // The template ships with the model; an ungated copy lives at
  // huggingface.co/onnx-community/functiongemma-270m-it-ONNX. To re-derive these
  // strings after a template change, render `format_argument` with jinja2.
  group('FunctionGemma Parser - canonical argument types (#366)', () {
    FunctionCallResponse parseCall(String input) {
      final result = FunctionCallParser.parse(
        input,
        modelType: ModelType.functionGemma,
      );
      expect(result, isNotNull, reason: 'failed to parse: $input');
      return result!;
    }

    test('reporter repro: string + array + number in one call', () {
      final result = parseCall(
        '<start_function_call>call:move_files{destination:<escape>Documents<escape>,'
        'extensions:[<escape>pdf<escape>],min_size_mb:100}<end_function_call>',
      );

      expect(result.name, equals('move_files'));
      expect(result.args['destination'], equals('Documents'));
      expect(result.args['extensions'], equals(['pdf']));
      expect(result.args['min_size_mb'], equals(100));
      expect(result.args['min_size_mb'], isA<int>());
    });

    test('bare integer parses as int', () {
      final result = parseCall(
        '<start_function_call>call:f{count:42}<end_function_call>',
      );

      expect(result.args['count'], equals(42));
      expect(result.args['count'], isA<int>());
    });

    test('bare negative integer parses as int', () {
      final result = parseCall(
        '<start_function_call>call:f{older_than_days:-3}<end_function_call>',
      );

      expect(result.args['older_than_days'], equals(-3));
      expect(result.args['older_than_days'], isA<int>());
    });

    test('bare float parses as double', () {
      final result = parseCall(
        '<start_function_call>call:f{threshold:1.5}<end_function_call>',
      );

      expect(result.args['threshold'], equals(1.5));
      expect(result.args['threshold'], isA<double>());
    });

    test('bare negative float parses as double', () {
      final result = parseCall(
        '<start_function_call>call:f{delta:-0.25}<end_function_call>',
      );

      expect(result.args['delta'], equals(-0.25));
      expect(result.args['delta'], isA<double>());
    });

    test('bare booleans parse as bool', () {
      final result = parseCall(
        '<start_function_call>call:f{dry_run:false,recursive:true}<end_function_call>',
      );

      expect(result.args['recursive'], isTrue);
      expect(result.args['dry_run'], isFalse);
      expect(result.args['recursive'], isA<bool>());
    });

    test('array of escaped strings parses as List<String>', () {
      final result = parseCall(
        '<start_function_call>call:f{exts:[<escape>pdf<escape>,<escape>docx<escape>]}'
        '<end_function_call>',
      );

      expect(result.args['exts'], equals(['pdf', 'docx']));
    });

    test('array of bare numbers parses as List of num', () {
      final result = parseCall(
        '<start_function_call>call:f{sizes:[10,20,30]}<end_function_call>',
      );

      expect(result.args['sizes'], equals([10, 20, 30]));
    });

    test('empty array parses as empty List, not dropped', () {
      final result = parseCall(
        '<start_function_call>call:f{tags:[]}<end_function_call>',
      );

      expect(result.args.containsKey('tags'), isTrue);
      expect(result.args['tags'], isEmpty);
      expect(result.args['tags'], isA<List>());
    });

    test('nested object parses as Map with bare keys', () {
      final result = parseCall(
        '<start_function_call>call:f{nested:{a:<escape>x<escape>,b:2}}<end_function_call>',
      );

      expect(result.args['nested'], equals({'a': 'x', 'b': 2}));
    });

    test(
      'escaped string containing comma, brackets and digits stays intact',
      () {
        final result = parseCall(
          '<start_function_call>call:f{note:<escape>done, 100% [ok]<escape>}'
          '<end_function_call>',
        );

        expect(result.args['note'], equals('done, 100% [ok]'));
        expect(result.args.length, equals(1));
      },
    );

    test('mixed call keeps every argument with its own type', () {
      final result = parseCall(
        '<start_function_call>call:f{a:<escape>s<escape>,b:[1,2],c:true,d:-1.5,'
        'e:[<escape>x<escape>]}<end_function_call>',
      );

      expect(result.args['a'], equals('s'));
      expect(result.args['b'], equals([1, 2]));
      expect(result.args['c'], isTrue);
      expect(result.args['d'], equals(-1.5));
      expect(result.args['e'], equals(['x']));
    });

    test('unknown bare token is kept as String, never dropped', () {
      final result = parseCall(
        '<start_function_call>call:f{weird:100abc}<end_function_call>',
      );

      expect(result.args['weird'], equals('100abc'));
    });
  });

  group('JSON Parser (existing models)', () {
    test('still works for gemmaIt', () {
      const input =
          '<tool_code>{"name": "get_weather", "parameters": {"location": "NYC"}}</tool_code>';

      final result = FunctionCallParser.parse(
        input,
        modelType: ModelType.gemmaIt,
      );

      expect(result, isNotNull);
      expect(result!.name, equals('get_weather'));
      expect(result.args['location'], equals('NYC'));
    });

    test('still works for null modelType (backward compatibility)', () {
      const input = '{"name": "test", "parameters": {"key": "value"}}';

      final result = FunctionCallParser.parse(input);

      expect(result, isNotNull);
      expect(result!.name, equals('test'));
      expect(result.args['key'], equals('value'));
    });

    test('isFunctionCallStart works for JSON models', () {
      expect(
        FunctionCallParser.isFunctionCallStart(
          '{"name": "test"}',
          modelType: ModelType.gemmaIt,
        ),
        isTrue,
      );
    });

    test('isFunctionCallComplete works for JSON models', () {
      const input = '{"name": "test", "parameters": {}}';

      expect(
        FunctionCallParser.isFunctionCallComplete(
          input,
          modelType: ModelType.gemmaIt,
        ),
        isTrue,
      );
    });
  });
}
