import 'dart:async';
import 'dart:js_interop';

import '../availability_types.dart';
import 'language_model_interop.dart';

/// Web facade over the Chrome **Prompt API** (`self.LanguageModel`),
/// matching the public API of the native `BuiltInAi` facade
/// (`../availability.dart`) field-for-field and method-for-method so app
/// code (and `gemma_bootstrap.dart`) never has to branch on platform.
abstract final class BuiltInAi {
  /// Bounds the availability probe. Mirrors the native facade's field
  /// 1:1 — see its doc comment for the rationale (a stuck/uninitialized OS
  /// AI stack must not hang callers). On web this bounds the
  /// `LanguageModel.availability()` JS promise.
  static Duration debugProbeTimeout = const Duration(seconds: 20);

  /// Current availability of the Chrome Prompt API model (Gemini Nano).
  ///
  /// `hasLanguageModel == false` (Firefox, Safari, mobile Chrome, or desktop
  /// Chrome without the Prompt API enabled) maps to
  /// [BuiltInAiAvailability.unavailableDeviceUnsupported] — no JS
  /// `ReferenceError` ever escapes. Never hangs: a probe that doesn't
  /// resolve within [debugProbeTimeout] resolves to
  /// [BuiltInAiAvailability.unavailableOther].
  static Future<BuiltInAiAvailability> availability() async {
    if (!hasLanguageModel) {
      return BuiltInAiAvailability.unavailableDeviceUnsupported;
    }
    try {
      final statusJs = await LanguageModel.availability().toDart.timeout(
        debugProbeTimeout,
      );
      return _mapStatus(statusJs.toDart);
    } on TimeoutException {
      return BuiltInAiAvailability.unavailableOther;
    }
  }

  static BuiltInAiAvailability _mapStatus(String status) => switch (status) {
    'available' => BuiltInAiAvailability.available,
    'downloadable' => BuiltInAiAvailability.downloadable,
    'downloading' => BuiltInAiAvailability.downloading,
    // Chrome's 'unavailable' carries no reason (disk floor, VRAM, missing
    // origin-trial/flag, …) — the unclassified bucket is honest here; the
    // README troubleshooting table covers remedies for every entry.
    _ => BuiltInAiAvailability.unavailableOther,
  };

  /// Ensures the Prompt API model is ready to use, downloading it if
  /// [BuiltInAiAvailability.downloadable] / [BuiltInAiAvailability.downloading].
  ///
  /// On the Prompt API, `LanguageModel.create()` itself performs (and
  /// dedupes) the download — there is no separate "kick off" call. The
  /// bootstrap session created to trigger it is destroyed once ready; Chrome
  /// keeps the downloaded weights cached regardless.
  ///
  /// [onProgress] receives a REAL 0..100 percentage from the browser's
  /// `downloadprogress` event (`e.loaded`, a 0..1 fraction) — an
  /// improvement over the native Android path, which cannot always report a
  /// total. [timeout] bounds the whole wait; the in-flight `create()` call
  /// is aborted via `AbortController` on timeout so it doesn't dangle.
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
        await _download(onProgress: onProgress, timeout: timeout);
    }
  }

  static Future<void> _download({
    required void Function(int percent)? onProgress,
    required Duration timeout,
  }) async {
    final controller = AbortController();
    LanguageModelSession? session;
    try {
      final options = buildCreateOptions(
        signal: controller.signal,
        onDownloadProgress: onProgress == null
            ? null
            : (loaded) => onProgress((loaded * 100).clamp(0, 100).round()),
      );
      session = await LanguageModel.create(options).toDart.timeout(
        timeout,
        onTimeout: () {
          try {
            controller.abort();
          } catch (_) {
            // Best-effort — the create() promise below still gets a
            // TimeoutException thrown into it either way.
          }
          throw TimeoutException(
            'Built-in AI feature download did not complete in $timeout',
            timeout,
          );
        },
      );
    } on TimeoutException {
      rethrow;
    } catch (e) {
      // A create() failure after kickoff (e.g. the browser reports it
      // became unavailable mid-download) surfaces as an opaque JS error —
      // wrap it so callers get the same exception type the native path
      // throws for the equivalent case.
      throw BuiltInAiUnavailableException(
        BuiltInAiAvailability.unavailableOther,
        'Built-in AI became unavailable during download: $e',
      );
    } finally {
      // Release the bootstrap session; Chrome keeps the downloaded weights
      // cached regardless of the session's lifetime.
      try {
        session?.destroy();
      } catch (_) {
        // destroy() is idempotent-in-intent; ignore a double-release.
      }
    }
  }
}
