@TestOn('linux || windows || mac-os')
library;

import 'package:flutter_gemma/desktop/grpc_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const port = int.fromEnvironment('SMOKE_TEST_PORT', defaultValue: 50051);
  const modelPath = String.fromEnvironment('SMOKE_TEST_MODEL_PATH');

  late LiteRtLmClient client;

  setUp(() async {
    client = LiteRtLmClient();
    await client.connect(host: '127.0.0.1', port: port);
  });

  tearDown(() async {
    await client.disconnect();
  });

  test('Server responds to health check before model load', () async {
    final healthy = await client.healthCheck();
    expect(healthy, isFalse);
  });

  test('Initialize with real model succeeds', () async {
    if (modelPath.isEmpty) {
      markTestSkipped('SMOKE_TEST_MODEL_PATH not set');
      return;
    }
    await client.initialize(
      modelPath: modelPath,
      backend: 'cpu',
      maxTokens: 512,
      maxNumImages: 0,
    );
    final healthy = await client.healthCheck();
    expect(healthy, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  // Last: nonexistent model may crash the JVM server on some platforms
  test('Initialize with nonexistent model returns error', () async {
    expect(
      () => client.initialize(
        modelPath: '/nonexistent/model.litertlm',
        backend: 'cpu',
        maxTokens: 512,
      ),
      throwsA(isA<Exception>()),
    );
  });
}
