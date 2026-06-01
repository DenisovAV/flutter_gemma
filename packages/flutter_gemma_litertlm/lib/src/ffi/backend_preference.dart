import 'dart:developer' as developer;

import 'package:flutter_gemma/pigeon.g.dart';

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

/// Failure details for a single FFI backend initialization attempt.
class BackendInitAttemptFailure {
  const BackendInitAttemptFailure({
    required this.backend,
    required this.error,
    required this.stackTrace,
  });

  /// Backend used for this initialization attempt.
  final PreferredBackend backend;

  /// Error reported while initializing [backend].
  final Object error;

  /// Stack trace captured with [error].
  final StackTrace stackTrace;

  @override
  String toString() => '${ffiBackendWireName(backend)}: $error';
}

/// Exception thrown after every FFI backend fallback attempt fails.
class BackendInitException implements Exception {
  BackendInitException({required Iterable<BackendInitAttemptFailure> attempts})
      : attempts = List.unmodifiable(attempts) {
    if (this.attempts.isEmpty) {
      throw ArgumentError.value(
        attempts,
        'attempts',
        'must contain at least one failed backend attempt',
      );
    }
  }

  /// Failed backend attempts in the order they were tried.
  final List<BackendInitAttemptFailure> attempts;

  /// Last backend attempt, usually the most actionable failure.
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

  final exception = BackendInitException(attempts: attempts);
  Error.throwWithStackTrace(exception, exception.lastAttempt.stackTrace);
}
