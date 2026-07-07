import 'dart:async';

import 'package:flutter/services.dart';

import '../pigeon.g.dart';

/// Shared pigeon client for the built-in AI host. Library-level (non-private)
/// so the availability facade, the engine and the sessions all drive the SAME
/// channel instance — mirrors the mediapipe `platformService` pattern.
final builtInAiService = BuiltInAiService();

/// Native → Dart event stream shared by every built-in AI session and the
/// download-progress reporting in [BuiltInAi.ensureReady]. Data events:
/// - token: `{partialResult: String, done: bool, sessionId: int}`
/// - error: `{code: 'ERROR', message: String, sessionId: int}`
/// - download: `{code: 'DOWNLOAD_PROGRESS', bytesDownloaded: int, bytesTotal: int}`
const builtInAiEventChannel = EventChannel('flutter_gemma_builtin_ai_stream');

/// Availability of the OS built-in model, surfaced to app code. Mirrors the
/// frozen wire enum [AvailabilityStatus] one-to-one.
enum BuiltInAiAvailability {
  available,
  downloadable,
  downloading,
  unavailableDeviceUnsupported,
  unavailableOsTooOld,
  unavailableDisabled,
  unavailableOther,
}

/// Maps the frozen pigeon wire enum onto the public [BuiltInAiAvailability].
BuiltInAiAvailability mapAvailability(AvailabilityStatus status) =>
    switch (status) {
      AvailabilityStatus.available => BuiltInAiAvailability.available,
      AvailabilityStatus.downloadable => BuiltInAiAvailability.downloadable,
      AvailabilityStatus.downloading => BuiltInAiAvailability.downloading,
      AvailabilityStatus.unavailableDeviceUnsupported =>
        BuiltInAiAvailability.unavailableDeviceUnsupported,
      AvailabilityStatus.unavailableOsTooOld =>
        BuiltInAiAvailability.unavailableOsTooOld,
      AvailabilityStatus.unavailableDisabled =>
        BuiltInAiAvailability.unavailableDisabled,
      AvailabilityStatus.unavailableOther =>
        BuiltInAiAvailability.unavailableOther,
    };

/// Thrown by [BuiltInAi.ensureReady] when the OS model can't be made ready
/// (device unsupported, OS too old, feature disabled, or an unclassified
/// failure). [status] is the terminal availability that caused the failure.
class BuiltInAiUnavailableException implements Exception {
  BuiltInAiUnavailableException(this.status, this.message);

  final BuiltInAiAvailability status;
  final String message;

  @override
  String toString() => 'BuiltInAiUnavailableException($status): $message';
}

/// App-facing entry point for probing and preparing the OS built-in model.
abstract final class BuiltInAi {
  /// Current availability of the OS built-in model.
  static Future<BuiltInAiAvailability> availability() async {
    final status = await builtInAiService.checkAvailability();
    return mapAvailability(status);
  }

  /// Ensures the OS model is ready to use, downloading the feature if the OS
  /// exposes it as [BuiltInAiAvailability.downloadable].
  ///
  /// - [BuiltInAiAvailability.available] → resolves immediately.
  /// - `unavailable*` → throws [BuiltInAiUnavailableException] (no download).
  /// - [BuiltInAiAvailability.downloadable] → calls `downloadFeature()`, then
  ///   polls until the model reports available (feeding [onProgress] from the
  ///   event channel's `DOWNLOAD_PROGRESS` events).
  /// - [BuiltInAiAvailability.downloading] → waits (no new download kicked off).
  ///
  /// [onProgress] receives an integer percentage 0..100 as bytes arrive.
  /// [timeout] bounds the whole wait; a [TimeoutException] is thrown if the
  /// model is not available in time.
  static Future<void> ensureReady({
    void Function(int percent)? onProgress,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final initial = await availability();
    switch (initial) {
      case BuiltInAiAvailability.available:
        return;
      case BuiltInAiAvailability.unavailableDeviceUnsupported:
      case BuiltInAiAvailability.unavailableOsTooOld:
      case BuiltInAiAvailability.unavailableDisabled:
      case BuiltInAiAvailability.unavailableOther:
        throw BuiltInAiUnavailableException(
          initial,
          'Built-in AI is not available: $initial',
        );
      case BuiltInAiAvailability.downloadable:
      case BuiltInAiAvailability.downloading:
        await _download(
          kickOff: initial == BuiltInAiAvailability.downloadable,
          onProgress: onProgress,
          timeout: timeout,
        );
    }
  }

  static Future<void> _download({
    required bool kickOff,
    required void Function(int percent)? onProgress,
    required Duration timeout,
  }) async {
    final ready = Completer<void>();
    StreamSubscription<Object?>? sub;

    // Surface download progress; the terminal signal (availability flipping to
    // `available`) comes from polling below, not from the event stream, so a
    // host that never emits progress still resolves.
    if (onProgress != null) {
      sub = builtInAiEventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map && event['code'] == 'DOWNLOAD_PROGRESS') {
            final downloaded = (event['bytesDownloaded'] as num?)?.toInt() ?? 0;
            final total = (event['bytesTotal'] as num?)?.toInt() ?? 0;
            if (total > 0) {
              onProgress(((downloaded / total) * 100).clamp(0, 100).round());
            }
          }
        },
        onError: (Object _) {}, // progress-only; ignore stream errors here
      );
    }

    Future<void> poll() async {
      // Poll availability until the model is ready or a terminal failure lands.
      while (!ready.isCompleted) {
        final status = await availability();
        switch (status) {
          case BuiltInAiAvailability.available:
            if (!ready.isCompleted) ready.complete();
            return;
          case BuiltInAiAvailability.downloadable:
          case BuiltInAiAvailability.downloading:
            await Future<void>.delayed(const Duration(milliseconds: 200));
          case BuiltInAiAvailability.unavailableDeviceUnsupported:
          case BuiltInAiAvailability.unavailableOsTooOld:
          case BuiltInAiAvailability.unavailableDisabled:
          case BuiltInAiAvailability.unavailableOther:
            if (!ready.isCompleted) {
              ready.completeError(
                BuiltInAiUnavailableException(
                  status,
                  'Built-in AI became unavailable during download: $status',
                ),
              );
            }
            return;
        }
      }
    }

    try {
      if (kickOff) {
        // Fire-and-forget: the OS routes the AICore feature download through a
        // system-managed queue that can sit silent for minutes-to-hours (or, on
        // a freshly-provisioned/CI device, never get a scheduler slot at all).
        // The ML Kit `download()` Flow gives NO terminal-emission guarantee, so
        // AWAITING it can hang indefinitely. We therefore never block on it —
        // the sole readiness signal is availability polling below, and the whole
        // wait is bounded by [timeout]. (A silent failure inside the kick-off is
        // surfaced by the poll loop / timeout, not lost.)
        unawaited(
          builtInAiService.downloadFeature().catchError((Object _) {
            // Swallow here — poll() observes the real availability outcome and
            // the timeout bounds the wait; a kick-off error must not escape the
            // fire-and-forget and crash the isolate.
          }),
        );
      }
      unawaited(poll());
      await ready.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Built-in AI feature download did not complete in $timeout',
          timeout,
        ),
      );
    } finally {
      await sub?.cancel();
    }
  }
}
