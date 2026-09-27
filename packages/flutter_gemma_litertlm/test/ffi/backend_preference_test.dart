import 'package:flutter_gemma_litertlm/src/ffi/backend_preference.dart';
import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ffiBackendFallbackOrder', () {
    test('tries NPU, then GPU, then CPU for an NPU preference', () {
      expect(ffiBackendFallbackOrder(PreferredBackend.npu), const [
        PreferredBackend.npu,
        PreferredBackend.gpu,
        PreferredBackend.cpu,
      ]);
    });

    test('tries GPU, then CPU for a GPU preference', () {
      expect(ffiBackendFallbackOrder(PreferredBackend.gpu), const [
        PreferredBackend.gpu,
        PreferredBackend.cpu,
      ]);
    });

    test('tries GPU, then CPU when no preference is provided', () {
      expect(ffiBackendFallbackOrder(null), const [
        PreferredBackend.gpu,
        PreferredBackend.cpu,
      ]);
    });

    test('tries only CPU for a CPU preference', () {
      expect(ffiBackendFallbackOrder(PreferredBackend.cpu), const [
        PreferredBackend.cpu,
      ]);
    });
  });

  group('ffiBackendWireName', () {
    test('serializes backend preferences for LiteRT-LM', () {
      expect(ffiBackendWireName(PreferredBackend.npu), 'npu');
      expect(ffiBackendWireName(PreferredBackend.gpu), 'gpu');
      expect(ffiBackendWireName(PreferredBackend.cpu), 'cpu');
    });
  });

  group('initializeFfiRuntime', () {
    test(
      'returns the first successfully initialized fallback backend',
      () async {
        final clients = <_FakeClient>[];

        final runtime = await initializeFfiRuntime<_FakeClient>(
          preferredBackend: PreferredBackend.gpu,
          logTag: '[Test]',
          createClient: () {
            final client = _FakeClient();
            clients.add(client);
            return client;
          },
          initializeClient: (client, backend) async {
            client.backend = backend;
            if (backend == PreferredBackend.gpu) {
              throw Exception('gpu unavailable');
            }
          },
          shutdownClient: (client) => client.shutdown(),
        );

        expect(runtime.activeBackend, PreferredBackend.cpu);
        expect(runtime.client, same(clients[1]));
        expect(clients[0].isShutdown, isTrue);
        expect(clients[1].isShutdown, isFalse);
      },
    );

    test('throws an inspectable exception with all backend attempts', () async {
      final clients = <_FakeClient>[];

      await expectLater(
        initializeFfiRuntime<_FakeClient>(
          preferredBackend: PreferredBackend.npu,
          logTag: '[Test]',
          createClient: () {
            final client = _FakeClient();
            clients.add(client);
            return client;
          },
          initializeClient: (client, backend) async {
            client.backend = backend;
            throw Exception('${ffiBackendWireName(backend)} failed');
          },
          shutdownClient: (client) => client.shutdown(),
        ),
        throwsA(
          isA<BackendInitException>()
              .having(
                (exception) =>
                    exception.attempts.map((attempt) => attempt.backend),
                'attempted backends',
                [
                  PreferredBackend.npu,
                  PreferredBackend.gpu,
                  PreferredBackend.cpu,
                ],
              )
              .having(
                (exception) => exception.lastAttempt.backend,
                'last attempt',
                PreferredBackend.cpu,
              ),
        ),
      );

      expect(clients, hasLength(3));
      expect(clients.every((client) => client.isShutdown), isTrue);
    });

    test('requires at least one failed backend attempt', () {
      expect(
        () => BackendInitException(attempts: const []),
        throwsArgumentError,
      );
    });

    test(
      'does not catch programming errors as backend fallback failures',
      () async {
        final error = AssertionError('bug');
        late _FakeClient client;

        await expectLater(
          initializeFfiRuntime<_FakeClient>(
            preferredBackend: PreferredBackend.cpu,
            logTag: '[Test]',
            createClient: () => client = _FakeClient(),
            initializeClient: (_, __) async => throw error,
            shutdownClient: (client) => client.shutdown(),
          ),
          throwsA(same(error)),
        );

        expect(client.isShutdown, isFalse);
      },
    );
  });

  group('encoderBackendWireName (vision + audio encoders)', () {
    // The VISION encoder graph carries STABLEHLO_COMPOSITE ops the Metal /
    // WebGPU LiteRT delegates can't prepare (hard-fails at conversation_create,
    // no fallback — LiteRT-LM#2461), so CPU is the op-safe default there. AUDIO
    // runs on either backend; CPU is a conservative default. Both stay
    // overridable: a vision model whose section bakes a gpu-only
    // backend_constraint would otherwise hard-fail on CPU, and Gemma 3n audio is
    // ~2x faster on GPU.
    test('defaults to cpu when no encoder backend is set (null)', () {
      expect(encoderBackendWireName(null), 'cpu');
    });

    test('passes an explicit override through unchanged', () {
      expect(encoderBackendWireName(PreferredBackend.gpu), 'gpu');
      expect(encoderBackendWireName(PreferredBackend.npu), 'npu');
      expect(encoderBackendWireName(PreferredBackend.cpu), 'cpu');
    });
  });

  group('activationDataTypeWireValue', () {
    // The numbers are LiteRT-LM's ActivationDataType order in
    // executor_settings_base.h, which the C setter casts the int to. A wrong
    // number is silent: F16 for F32 builds an engine that still writes the
    // wrong digits the setting was meant to fix.
    test('null leaves the engine setting untouched', () {
      expect(activationDataTypeWireValue(null), isNull);
    });

    test('matches the C API numbering', () {
      expect(activationDataTypeWireValue(ActivationDataType.float32), 0);
      expect(activationDataTypeWireValue(ActivationDataType.float16), 1);
    });

    test('offers only the two float types', () {
      // I16 (2) and I8 (3) are in LiteRT-LM's enum and deliberately not in
      // ours: at the pinned version they are not half precision the way F16 is,
      // and an unsupported type fails engine init, which reads as a quiet fall
      // back to CPU. Adding one back means adding a number here too.
      expect(ActivationDataType.values, [
        ActivationDataType.float32,
        ActivationDataType.float16,
      ]);
    });
  });
}

class _FakeClient {
  PreferredBackend? backend;
  bool isShutdown = false;

  void shutdown() {
    isShutdown = true;
  }
}
