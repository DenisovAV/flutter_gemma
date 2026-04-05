@TestOn('linux || windows || mac-os')
library;

import 'package:flutter_gemma/desktop/grpc_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const port = int.fromEnvironment('SMOKE_TEST_PORT', defaultValue: 50051);

  late LiteRtLmClient client;

  setUp(() async {
    client = LiteRtLmClient();
    await client.connect(port: port);
  });

  tearDown(() async {
    await client.disconnect();
  });

  test('Server responds to health check', () async {
    final healthy = await client.healthCheck();
    expect(healthy, isTrue);
  });

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
