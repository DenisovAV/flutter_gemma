import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('carries the resolved modelPath and optional tokenizerPath', () {
    const c = RuntimeConfig(
      maxTokens: 512,
      modelPath: '/tmp/m.litertlm',
      tokenizerPath: '/tmp/tok.json',
    );
    expect(c.modelPath, '/tmp/m.litertlm');
    expect(c.tokenizerPath, '/tmp/tok.json');
  });

  test('tokenizerPath defaults to null for inference', () {
    const c = RuntimeConfig(maxTokens: 256, modelPath: '/m');
    expect(c.tokenizerPath, isNull);
  });
}
