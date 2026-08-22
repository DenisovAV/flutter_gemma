@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `ReadableStream<string>` — the return type of
/// `LanguageModelSession.promptStreaming`. Typed opaque [JSObject] with a
/// `getReader()` extension (mirrors the `AsyncIterator` pump pattern in
/// `litert_lm_web.dart`, but the Prompt API returns a real Web Streams
/// `ReadableStream`, not an async iterable).
extension ReadableStreamReader on JSObject {
  external ReadableStreamDefaultReader getReader();
}

/// `ReadableStreamDefaultReader<string>`.
extension type ReadableStreamDefaultReader._(JSObject _) implements JSObject {
  /// Resolves to `{value: string|undefined, done: boolean}`.
  external JSPromise<JSObject> read();
  external JSPromise<JSAny?> cancel([JSAny? reason]);

  /// Releases the reader's lock on the stream so it can be GC'd. Synchronous
  /// per the Web Streams spec.
  external void releaseLock();
}

/// Pumps a Prompt API `ReadableStream<string>` into a Dart `Stream<String>`,
/// applying the mandatory delta/cumulative defensive guard.
///
/// The spec'd behavior is that each chunk is a DELTA (only the newly
/// generated text). Early Chrome builds streamed CUMULATIVE chunks (the
/// whole response so far). This guard makes both shapes look like deltas to
/// the caller: if a chunk starts with everything accumulated so far, only
/// the suffix is emitted; otherwise the chunk is emitted as-is (already a
/// delta).
///
/// Controller-based (not `async*`) so cancelling the returned stream's
/// subscription calls `reader.cancel()` on the underlying JS stream — an
/// abandoned Dart stream must not leave the browser still generating.
Stream<String> pumpText(JSObject readableStream) {
  final controller = StreamController<String>();
  late final ReadableStreamDefaultReader reader;
  var acc = '';
  var cancelled = false;
  // Early Chrome builds streamed CUMULATIVE chunks (whole response so far);
  // the spec'd shape is DELTA (only the new text). We can't tell from the
  // first chunk, so decide ONCE on the second: if it starts with the first
  // chunk it's cumulative, else delta — then hold that mode for the whole
  // stream. This NARROWS but does not eliminate misclassification: a genuine
  // delta whose 2nd chunk happens to start with the whole 1st chunk would still
  // be read as cumulative. Deciding per-chunk would widen that window to every
  // chunk, so chunk-2-only is the better tradeoff for real (subword) streams.
  bool? cumulative; // null until decided

  Future<void> pumpLoop() async {
    try {
      while (true) {
        if (cancelled || controller.isClosed) return;
        final step = await reader.read().toDart;
        final done = step.getProperty<JSBoolean>('done'.toJS).toDart;
        if (done) break;
        final value = step.getProperty<JSString?>('value'.toJS)?.toDart;
        if (value == null || value.isEmpty) continue;

        final String delta;
        if (acc.isEmpty) {
          // First chunk — can't classify yet; emit verbatim, remember it.
          delta = value;
          acc = value;
        } else {
          cumulative ??= value.startsWith(acc); // decide once, on chunk 2
          if (cumulative!) {
            delta = value.length >= acc.length
                ? value.substring(acc.length)
                : value; // defensive: a shorter "cumulative" chunk = treat raw
            acc = value;
          } else {
            delta = value;
            acc += value;
          }
        }
        if (delta.isNotEmpty && !controller.isClosed) controller.add(delta);
      }
      if (!controller.isClosed) await controller.close();
    } catch (e, st) {
      if (!controller.isClosed) {
        controller.addError(e, st);
        await controller.close();
      }
    } finally {
      // Release the reader lock so the JS ReadableStream can be GC'd
      // deterministically on normal completion / error. The onCancel path calls
      // reader.cancel(), which per the Streams spec ALSO releases the lock, so
      // guard against a double-release throw here.
      try {
        reader.releaseLock();
      } catch (_) {}
    }
  }

  controller.onListen = () {
    reader = readableStream.getReader();
    unawaited(pumpLoop());
  };
  controller.onCancel = () {
    cancelled = true;
    try {
      reader.cancel();
    } catch (_) {
      // Reader may already be released (stream fully drained) — cancelling a
      // released reader throws; the pump loop already returned in that case.
    }
  };

  return controller.stream;
}
