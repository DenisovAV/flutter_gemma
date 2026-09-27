import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';

/// Whether this host ships an NPU dispatch stack at all.
///
/// Exactly two do: Android carries the Qualcomm QNN stack and Windows carries
/// Intel's (`LiteRtDispatch.dll` + OpenVino + TBB), each in its own native
/// tarball. Nothing ships for macOS, Linux or iOS.
///
/// This gate exists because `backend: "npu"` is a string the native runtime
/// accepts WITHOUT complaint on a host that cannot honour it. Since
/// [initializeFfiRuntime] reports the first candidate whose init did not throw,
/// a Mac asking for NPU got a model claiming `activeBackend == npu` —
/// measured, on macOS, with a Gemma 4 E2B `.litertlm`.
/// `InferenceModel.activeBackend` promises to "reflect any fallback the plugin
/// performed internally", so that was a false report: a benchmark asking for
/// NPU attributed its CPU or GPU numbers to an NPU the machine does not have.
bool get hostShipsNpuDispatch => npuDispatchShipsFor(
  Platform.operatingSystem,
  androidHasFastRpc: _androidHasFastRpc,
);

/// The rule behind [hostShipsNpuDispatch], as a pure function.
///
/// Split out because `Platform.operatingSystem` has no override seam — `dart:io`'s
/// `IOOverrides` covers files, directories and sockets, not the platform — so the
/// Android and Windows arms are otherwise unreachable from a `flutter test` run
/// on a Mac, and a test can only restate the implementation back at itself.
bool npuDispatchShipsFor(
  String operatingSystem, {
  required bool androidHasFastRpc,
}) => switch (operatingSystem) {
  'windows' => true,
  'android' => androidHasFastRpc,
  _ => false,
};

bool? _fastRpcProbe;

/// Whether Qualcomm's FastRPC bridge resolves in this process.
///
/// The OS is the wrong granularity on Android. The Qualcomm stack ships in every
/// `android_arm64` build, so a Tensor, Exynos or Dimensity phone has all eleven
/// libraries in its APK and no Hexagon DSP to run them on. Offering `npu` there
/// costs a 55.1 MiB zip extraction out of the APK into `codeCacheDir` — measured
/// on the native-v0.17.1 bundle, of which 44 MiB is the four per-SoC Skels — and
/// that extraction runs on the platform thread inside a `MethodChannel` handler,
/// so it stalls input dispatch and the Choreographer. Then `engine_create` fails
/// anyway. `codeCacheDir` is cache-class storage, so "Clear cache" and every app
/// upgrade make it happen again.
///
/// `libcdsprpc.so` is the precondition for the chain: the per-SoC `QnnHtp*Stub`
/// libraries carry it as a `DT_NEEDED`, and the core plugin's manifest declares
/// it `required="false"` so it resolves in the app's namespace where it exists.
/// So one `dlopen` answers the silicon question, before the gate lets anything
/// reach the channel that does the extracting.
///
/// Probed once: the answer cannot change within a process.
bool get _androidHasFastRpc => _fastRpcProbe ??= () {
  try {
    DynamicLibrary.open('libcdsprpc.so');
    return true;
  } on Object {
    return false;
  }
}();

/// The backends to try, in order, for a [preferredBackend] request.
///
/// [npuDispatchAvailable] overrides [hostShipsNpuDispatch] — tests need both
/// answers, and a platform-dependent default cannot give them one.
List<PreferredBackend> ffiBackendFallbackOrder(
  PreferredBackend? preferredBackend, {
  bool? npuDispatchAvailable,
}) => switch (preferredBackend) {
  PreferredBackend.npu => [
    // Offered only where a dispatch stack exists. Dropping it here is what
    // makes the reported `activeBackend` true on the other four platforms.
    if (npuDispatchAvailable ?? hostShipsNpuDispatch) PreferredBackend.npu,
    PreferredBackend.gpu,
    PreferredBackend.cpu,
  ],
  PreferredBackend.gpu ||
  null => const [PreferredBackend.gpu, PreferredBackend.cpu],
  PreferredBackend.cpu => const [PreferredBackend.cpu],
};

String ffiBackendWireName(PreferredBackend backend) => switch (backend) {
  PreferredBackend.npu => 'npu',
  PreferredBackend.gpu => 'gpu',
  PreferredBackend.cpu => 'cpu',
};

/// Wire name for an ENCODER backend (vision / audio), defaulting to `cpu` when
/// unset. Shared by both because their defaulting is identical (`null → cpu`).
///
/// Why CPU differs per encoder:
/// - VISION: its graph carries `STABLEHLO_COMPOSITE` ops the Metal (iOS/macOS)
///   and WebGPU (Windows/Linux) LiteRT delegates cannot prepare — it hard-fails
///   at `conversation_create` with no backend fallback (LiteRT-LM#2461, open
///   upstream). CPU is the mandatory-safe default (matching the vision
///   *adapter*, which LiteRT-LM already pins to CPU unconditionally).
/// - AUDIO: runs fine on either backend (verified on Metal); CPU is a
///   conservative default, but GPU is often faster (Gemma 3n audio ~2× CPU).
///
/// Both stay overridable: pass `PreferredBackend.gpu` for a vision model whose
/// section bakes a gpu-only `backend_constraint`, or for faster GPU audio.
String encoderBackendWireName(PreferredBackend? encoderBackend) =>
    encoderBackend == null ? 'cpu' : ffiBackendWireName(encoderBackend);

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
  // FutureOr: LiteRtLmFfiClient.shutdown() is async (it waits for in-flight
  // conversation creates before engine_delete); test fakes tear down
  // synchronously. Awaiting covers both, so a failed backend is fully released
  // before the next one allocates an engine.
  required FutureOr<void> Function(T client) shutdownClient,
  bool? npuDispatchAvailable,
}) async {
  final attempts = <BackendInitAttemptFailure>[];
  final backends = ffiBackendFallbackOrder(
    preferredBackend,
    npuDispatchAvailable: npuDispatchAvailable,
  );

  if (backends.isEmpty) {
    throw StateError('No FFI backend candidates are available.');
  }

  // Said out loud rather than dropped: the request cannot be honoured here, and
  // a caller who reads `activeBackend` will see gpu or cpu with no explanation
  // of why the thing they asked for is absent.
  //
  // Through `gemmaLog`, not `developer.log`, even though the attempt failures
  // below use the latter. flutter_tools never subscribes to the VM-service
  // `Logging` stream, so `developer.log` reaches DevTools and an IDE console but
  // NOT a `flutter run` terminal — and this is a message for whoever typed the
  // backend name. `clampLitertlmContextTokens` reports the same kind of thing
  // ("you asked for X, you are getting Y") the same way, one file over.
  if (preferredBackend == PreferredBackend.npu &&
      !backends.contains(PreferredBackend.npu)) {
    gemmaLog(
      '⚠️  $logTag npu was requested, but no NPU dispatch stack ships for '
      '${Platform.operatingSystem} — trying '
      '${backends.map(ffiBackendWireName).join(" -> ")} instead. '
      'NPU is available on Android (Qualcomm) and Windows (Intel '
      'LunarLake/PantherLake). Read InferenceModel.activeBackend for what '
      'actually ran; it survives a release build, this line does not.',
    );
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
      await shutdownClient(client);
      // Both, for two readers. `developer.log` carries the structured error and
      // stack trace to DevTools, which is where they are useful. But
      // flutter_tools never subscribes to the VM-service `Logging` stream, so on
      // its own that made every GPU→CPU fallback invisible in a `flutter run`
      // terminal — the same silent-fallback defect the NPU notice above exists
      // to prevent, one branch away. `gemmaLog` reaches the terminal.
      developer.log(
        '$logTag ${ffiBackendWireName(backend)} backend failed: $error',
        name: 'flutter_gemma',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      gemmaLog(
        '⚠️  $logTag ${ffiBackendWireName(backend)} backend failed, trying the '
        'next candidate: $error. InferenceModel.activeBackend reports what '
        'actually ran, in release builds too.',
      );
    }
  }

  if (attempts.isEmpty) {
    throw StateError('No FFI backend candidates were attempted.');
  }

  final exception = BackendInitException(attempts: attempts);
  Error.throwWithStackTrace(exception, exception.lastAttempt.stackTrace);
}
