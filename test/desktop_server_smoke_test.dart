@TestOn('linux || windows || mac-os')
library;

import 'package:flutter_gemma/desktop/grpc_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const port = int.fromEnvironment('SMOKE_TEST_PORT', defaultValue: 50051);
  const modelPath = String.fromEnvironment('SMOKE_TEST_MODEL_PATH');

  test('Desktop server smoke test', () async {
    if (modelPath.isEmpty) {
      markTestSkipped('SMOKE_TEST_MODEL_PATH not set');
      return;
    }

    final client = LiteRtLmClient();
    await client.connect(host: '127.0.0.1', port: port);

    // Before model load — not healthy yet
    final healthBefore = await client.healthCheck();
    expect(healthBefore, isFalse);

    // Initialize with real model
    await client.initialize(
      modelPath: modelPath,
      backend: 'cpu',
      maxTokens: 512,
      maxNumImages: 0,
    );

    // After model load — healthy
    final healthAfter = await client.healthCheck();
    expect(healthAfter, isTrue);

    // Nonexistent model returns error
    expect(
      () => client.initialize(
        modelPath: '/nonexistent/model.litertlm',
        backend: 'cpu',
        maxTokens: 512,
      ),
      throwsA(isA<Exception>()),
    );

    await client.disconnect();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
