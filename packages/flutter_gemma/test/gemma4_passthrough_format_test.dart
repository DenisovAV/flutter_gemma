import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/parsing/function_call_format_factory.dart';
import 'package:flutter_gemma/core/parsing/sdk_passthrough_function_call_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FunctionCallFormatFactory for ModelType.gemma4', () {
    test('returns SdkPassthroughFunctionCallFormat', () {
      final format = FunctionCallFormatFactory.create(ModelType.gemma4);
      expect(format, isA<SdkPassthroughFunctionCallFormat>());
    });

    test('passthrough never reports a function call in text stream', () {
      final format = SdkPassthroughFunctionCallFormat();
      // Even text that looks like a tool call from another format is NOT a
      // function call here: SDK produces structured tool_calls separately.
      expect(format.isFunctionCallStart('<|tool_call>call:foo{}<tool_call|>'),
          isFalse);
      expect(format.isFunctionCallComplete('<|tool_call>call:foo{}<tool_call|>'),
          isFalse);
      expect(format.isDefinitelyText('any plain text'), isTrue);
      expect(format.parse('<|tool_call>call:foo{}<tool_call|>'), isNull);
      expect(format.parseAll('<|tool_call>call:foo{}<tool_call|>'), isEmpty);
    });
  });
}
