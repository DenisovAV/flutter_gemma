import 'dart:developer' as developer;

import '../../pigeon.g.dart';

List<PreferredBackend> ffiBackendFallbackOrder(
  PreferredBackend? preferredBackend,
) =>
    switch (preferredBackend) {
      PreferredBackend.npu => const [
          PreferredBackend.npu,
          PreferredBackend.gpu,
          PreferredBackend.cpu,
        ],
      PreferredBackend.gpu || null => const [
          PreferredBackend.gpu,
          PreferredBackend.cpu,
        ],
      PreferredBackend.cpu => const [PreferredBackend.cpu],
    };

String ffiBackendWireName(PreferredBackend backend) => switch (backend) {
      PreferredBackend.npu => 'npu',
      PreferredBackend.gpu => 'gpu',
      PreferredBackend.cpu => 'cpu',
    };

class BackendInitAttemptFailure {
  const BackendInitAttemptFailure({
    required this.backend,
    required this.error,
    required this.stackTrace,
  });

  final PreferredBackend backend;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => '${ffiBackendWireName(backend)}: $error';
}

class BackendInitException implements Exception {
  const BackendInitException({required this.attempts});

  final List<BackendInitAttemptFailure> attempts;

  BackendInitAttemptFailure get lastAttempt => attempts.last;

  @override
  String toString() {
    final failures = attempts.map((attempt) => attempt.toString()).join('; ');
    return 'BackendInitException: all FFI backends failed. '
        'Last attempted ${ffiBackendWireName(lastAttempt.backend)}. '
        'Attempts: $failures';
  }
}

Future<({T client, PreferredBackend activeBackend})> initializeFfiRuntime<T>({
  required PreferredBackend? preferredBackend,
  required String logTag,
  required T Function() createClient,
  required Future<void> Function(T client, PreferredBackend backend)
      initializeClient,
  required void Function(T client) shutdownClient,
}) async {
  final attempts = <BackendInitAttemptFailure>[];
  final backends = ffiBackendFallbackOrder(preferredBackend);

  if (backends.isEmpty) {
    throw StateError('No FFI backend candidates are available.');
  }

  for (final backend in backends) {
    final client = createClient();
    try {
      await initializeClient(client, backend);
      return (client: client, activeBackend: backend);
    } on Exception catch (error, stackTrace) {
      attempts.add(
        BackendInitAttemptFailure(
          backend: backend,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      shutdownClient(client);
      developer.log(
        '$logTag ${ffiBackendWireName(backend)} backend failed: $error',
        name: 'flutter_gemma',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  if (attempts.isEmpty) {
    throw StateError('No FFI backend candidates were attempted.');
  }

  final exception = BackendInitException(attempts: List.unmodifiable(attempts));
  Error.throwWithStackTrace(exception, exception.lastAttempt.stackTrace);
}
