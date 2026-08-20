import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show InferenceModelSession, SessionMetrics;

import 'language_model_interop.dart';
import 'readable_stream_pump.dart';

/// One-time guard so the `measureContextUsage` → char-heuristic fallback
/// warns once per isolate rather than on every call. Mirrors the native
/// session's `_tokenFallbackWarned`.
bool _tokenFallbackWarnedWeb = false;

@visibleForTesting
void resetTokenFallbackWarningWeb() => _tokenFallbackWarnedWeb = false;

bool _imageSkippedWarnedWeb = false;

@visibleForTesting
void resetImageSkippedWarningWeb() => _imageSkippedWarnedWeb = false;

/// A generation session on the Chrome Prompt API (`LanguageModelSession`).
///
/// Buffers query chunks in a `StringBuffer` (the same shape
/// `flutter_gemma_onnx`'s `OnnxSession` uses) and drains them into one
/// `prompt()`/`promptStreaming()` call — the Prompt API's session is
/// stateful (multi-turn context accrues in the JS session itself), so no
/// manual history replay is needed here, matching the native session's
/// posture.
class BuiltInAiSessionWeb extends InferenceModelSession {
  BuiltInAiSessionWeb({
    required this.session,
    required this.modelType,
    required this.onClose,
    this.fileType = ModelFileType.builtIn,
    this.supportImage = false,
    this.systemInstruction,
  });

  final LanguageModelSession session;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final String? systemInstruction;
  final VoidCallback onClose;

  final StringBuffer _queryBuffer = StringBuffer();
  bool _isClosed = false;

  /// The `AbortController` backing the generation currently in flight (if
  /// any) — [stopGeneration] aborts it. Only one generation is ever in
  /// flight per session (buffered-chunk sessions are single-turn-at-a-time
  /// by construction), so a single field suffices.
  AbortController? _activeAbort;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Session is closed');
    }
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();
    if (message.hasImage && !_imageSkippedWarnedWeb) {
      _imageSkippedWarnedWeb = true;
      gemmaLog(
        '[BuiltInAI/web] Image input is dropped on the web Prompt API path '
        '(v1, text-only).',
      );
    }
    final prompt = message.transformToChatPrompt(
      type: modelType,
      fileType: fileType,
    );
    _queryBuffer.write(prompt);
  }

  String _drainBuffer() {
    final text = _queryBuffer.toString();
    _queryBuffer.clear();
    return text;
  }

  @override
  Future<String> getResponse() async {
    _assertNotClosed();
    final text = _drainBuffer();
    final abort = AbortController();
    _activeAbort = abort;
    try {
      final options = buildPromptOptions(signal: abort.signal);
      final result = await session.prompt(text.toJS, options).toDart;
      return result.toDart;
    } catch (e) {
      // stopGeneration() during a non-streaming prompt() discards the whole
      // call — treat the resulting AbortError as a clean (empty) stop rather
      // than a failure, same posture as the streaming path.
      if (_isAbortError(e)) return '';
      rethrow;
    } finally {
      if (identical(_activeAbort, abort)) _activeAbort = null;
    }
  }

  @override
  Stream<String> getResponseAsync() {
    _assertNotClosed();
    final text = _drainBuffer();
    final abort = AbortController();
    _activeAbort = abort;

    final controller = StreamController<String>();
    StreamSubscription<String>? subscription;
    var finished = false;

    void cleanup() {
      if (finished) return;
      finished = true;
      if (identical(_activeAbort, abort)) _activeAbort = null;
      // Abort the in-flight `promptStreaming` on EVERY terminal path — most
      // importantly consumer-cancel (barge-in), where only cancelling the pump
      // subscription would leave the JS generation running browser-side. The
      // AbortSignal is the Prompt API's sanctioned stop; `abort()` is
      // idempotent and a no-op once generation has completed (onDone), and this
      // call's AbortController is per-invocation so the next turn is unaffected.
      abort.abort();
      subscription?.cancel();
    }

    controller.onListen = () {
      final JSObject readableStream;
      try {
        final options = buildPromptOptions(signal: abort.signal);
        readableStream = session.promptStreaming(text.toJS, options);
      } catch (e, st) {
        controller.addError(e, st);
        cleanup();
        controller.close();
        return;
      }

      subscription = pumpText(readableStream).listen(
        (chunk) {
          if (!controller.isClosed) controller.add(chunk);
        },
        onError: (Object error, StackTrace st) {
          cleanup();
          if (controller.isClosed) return;
          // Cancellation is not a failure — stopGeneration() aborting the
          // in-flight fetch/read surfaces as an AbortError; end the stream
          // cleanly instead of propagating it as an error.
          if (_isAbortError(error)) {
            controller.close();
          } else {
            controller.addError(error, st);
            controller.close();
          }
        },
        onDone: () {
          cleanup();
          if (!controller.isClosed) controller.close();
        },
      );
    };

    controller.onCancel = () => cleanup();

    return controller.stream;
  }

  @override
  Future<int> sizeInTokens(String text) async {
    _assertNotClosed();
    try {
      final usage = await session.measureContextUsage(text.toJS).toDart;
      return usage.toDartInt;
    } catch (_) {
      // `measureContextUsage` is the current name; some earlier builds only
      // exposed the legacy `measureInputUsage`. Try it before falling back
      // to the char heuristic.
      try {
        final legacy = session.callMethod<JSPromise<JSNumber>>(
          'measureInputUsage'.toJS,
          text.toJS,
        );
        final usage = await legacy.toDart;
        return usage.toDartInt;
      } catch (e) {
        if (!_tokenFallbackWarnedWeb) {
          _tokenFallbackWarnedWeb = true;
          gemmaLog(
            '[BuiltInAI/web] measureContextUsage is unavailable on this '
            'host ($e); falling back to a (text.length / 4) estimate. '
            'Counts are approximate.',
          );
        }
        return (text.length / 4).ceil();
      }
    }
  }

  @override
  Future<void> stopGeneration() async {
    final abort = _activeAbort;
    if (abort == null) return;
    try {
      abort.abort();
    } catch (_) {
      // abort() on an already-settled controller is a no-op per spec; guard
      // defensively in case a host throws instead.
    }
  }

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    final abort = _activeAbort;
    _activeAbort = null;
    if (abort != null) {
      try {
        abort.abort();
      } catch (_) {}
    }
    onClose();
    try {
      session.destroy();
    } catch (_) {
      // destroy() is documented sync-void; guard so a double-release (e.g.
      // a racing close() call) can't throw out of this method.
    }
  }
}

/// Best-effort detection of a JS `AbortError` surfaced through
/// `dart:js_interop`'s promise-rejection conversion. Checked defensively —
/// both against a JS `DOMException`-shaped object's `.name` and against the
/// stringified error — because Chrome versions differ in exactly what shape
/// a rejected `AbortController` signal surfaces as.
bool _isAbortError(Object error) {
  // No `is`/`as` runtime check against the JSObject interop type (unreliable
  // across compile modes) — just attempt the property read and fall through
  // to the string check if `error` isn't JS-interop-shaped at all.
  try {
    final name = (error as JSObject)
        .getProperty<JSString?>('name'.toJS)
        ?.toDart;
    if (name == 'AbortError') return true;
  } catch (_) {
    // Not a DOMException-shaped object — fall through to the string check.
  }
  return error.toString().contains('AbortError');
}
