/// Shared, arm-neutral types for the built-in OS AI engine.
///
/// Deliberately **zero imports** — no `flutter`, no pigeon, no `dart:io` /
/// `dart:js_interop`. This file is the compile-time proof that
/// [BuiltInAiAvailability] and [BuiltInAiUnavailableException] are safe to
/// export from BOTH the native arm (`availability.dart`, which layers the
/// pigeon client on top) and the web arm (`web/availability_web.dart`, which
/// layers the Chrome Prompt API `LanguageModel` JS interop on top) without
/// either arm pulling the other's platform channel into its import graph.
library;

/// Availability of the OS built-in model, surfaced to app code.
///
/// Native: mirrors the frozen wire enum `AvailabilityStatus` one-to-one (see
/// `availability.dart`'s `mapAvailability`). Web: mapped from the Chrome
/// Prompt API's `LanguageModel.availability()` string result (see
/// `web/availability_web.dart`) — Chrome has only four states
/// (`unavailable`/`downloadable`/`downloading`/`available`), so
/// `unavailableOsTooOld` / `unavailableDisabled` are native-only values; web
/// folds every unsupported/unclassified case into `unavailableOther` /
/// `unavailableDeviceUnsupported`.
enum BuiltInAiAvailability {
  available,
  downloadable,
  downloading,
  unavailableDeviceUnsupported,
  unavailableOsTooOld,
  unavailableDisabled,
  unavailableOther,
}

/// Thrown by `BuiltInAi.ensureReady` when the OS/browser model can't be made
/// ready (device unsupported, OS too old, feature disabled, or an
/// unclassified failure). [status] is the terminal availability that caused
/// the failure.
class BuiltInAiUnavailableException implements Exception {
  BuiltInAiUnavailableException(this.status, this.message);

  final BuiltInAiAvailability status;
  final String message;

  @override
  String toString() => 'BuiltInAiUnavailableException($status): $message';
}
