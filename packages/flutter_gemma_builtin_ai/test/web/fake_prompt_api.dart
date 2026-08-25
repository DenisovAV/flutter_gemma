@JS()
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Test-only helpers for building a fake `self.LanguageModel` and driving it
/// from browser unit tests (`flutter test --platform chrome`). No real
/// Gemini Nano model is ever downloaded — everything here is a hand-built JS
/// object planted on `globalContext`.

/// Builds a `JSPromise<T>` with full control over resolve/reject timing and
/// value, unlike `Future<T>.toJS` (which always wraps a rejection in a
/// generic boxed-Dart-error `Error` object — useless for simulating a
/// specific DOMException shape like `{name: 'AbortError'}`).
JSPromise<T> jsPromiseOf<T extends JSAny?>(
  void Function(
    void Function(T value) resolve,
    void Function(JSAny? reason) reject,
  )
  executor,
) {
  return JSPromise<T>(
    ((JSFunction resolve, JSFunction reject) {
      executor(
        (value) => resolve.callAsFunction(resolve, value),
        (reason) => reject.callAsFunction(reject, reason),
      );
    }).toJS,
  );
}

/// A DOMException-shaped fake error: `{name, message}`.
JSObject fakeDomException(String name, [String message = '']) {
  final o = JSObject();
  o.setProperty('name'.toJS, name.toJS);
  o.setProperty('message'.toJS, message.toJS);
  return o;
}

/// Reads the `aborted` flag off a real browser `AbortSignal` (production
/// code creates a REAL `AbortController`/`AbortSignal` — only `LanguageModel`
/// itself is faked, so `.aborted` here reflects genuine abort state).
bool isSignalAborted(JSObject? signal) =>
    signal?.getProperty<JSBoolean?>('aborted'.toJS)?.toDart ?? false;

/// Fires the `downloadprogress` handler a `monitor(m)` callback registered
/// via `m.addEventListener('downloadprogress', handler)`, and records every
/// `loaded` fraction delivered.
class MonitorRecorder {
  JSFunction? _handler;
  final List<double> firedLoaded = [];

  /// Extracts and invokes the `monitor` option (if present) with a fake
  /// EventTarget-shaped `m`, capturing the `downloadprogress` handler.
  void wireFromOptions(JSObject? options) {
    final monitor = options?.getProperty<JSFunction?>('monitor'.toJS);
    if (monitor == null) return;
    final m = JSObject();
    m.setProperty(
      'addEventListener'.toJS,
      ((JSString type, JSFunction handler) {
        if (type.toDart == 'downloadprogress') _handler = handler;
      }).toJS,
    );
    monitor.callAsFunction(null, m);
  }

  void fire(double loaded) {
    final handler = _handler;
    if (handler == null) return;
    final event = JSObject();
    event.setProperty('loaded'.toJS, loaded.toJS);
    handler.callAsFunction(null, event);
    firedLoaded.add(loaded);
  }
}

/// A fake `LanguageModelSession` (any JSObject-shaped value works — the
/// production `LanguageModel.create()` return type is a static-interop view,
/// not a runtime-checked type).
class FakeSession {
  FakeSession({
    this.onPrompt,
    this.streamChunks,
    this.cumulativeStream = false,

    /// When true, `measureContextUsage` is PRESENT but its promise REJECTS —
    /// simulates a real tokenizer failure (session destroyed, quota, …) that
    /// `sizeInTokens` must propagate rather than mask behind the char heuristic.
    this.measureThrows = false,

    /// When true, NEITHER `measureContextUsage` nor `measureInputUsage` is
    /// defined on the session — the genuinely-absent case that legitimately
    /// falls back to the char heuristic.
    this.omitMeasure = false,
  }) {
    jsObject = JSObject();
    var destroyed = false;
    jsObject.setProperty(
      'destroy'.toJS,
      (() {
        if (destroyed) throw StateError('destroy() called twice');
        destroyed = true;
        destroyCount++;
      }).toJS,
    );
    jsObject.setProperty(
      'prompt'.toJS,
      ((JSString input, [JSObject? options]) {
        promptCalls.add(input.toDart);
        final signal = options?.getProperty<JSObject?>('signal'.toJS);
        return jsPromiseOf<JSString>((resolve, reject) async {
          await Future<void>.delayed(Duration.zero);
          if (isSignalAborted(signal)) {
            reject(fakeDomException('AbortError'));
            return;
          }
          resolve((onPrompt?.call(input.toDart) ?? '').toJS);
        });
      }).toJS,
    );
    jsObject.setProperty(
      'promptStreaming'.toJS,
      ((JSString input, [JSObject? options]) {
        promptStreamingCalls.add(input.toDart);
        final signal = options?.getProperty<JSObject?>('signal'.toJS);
        lastStreamingSignal = signal;
        final chunks = streamChunks?.call(input.toDart) ?? const <String>[];
        return _fakeReadableStream(
          cumulativeStream ? _toCumulative(chunks) : chunks,
          signal,
        );
      }).toJS,
    );
    if (!omitMeasure) {
      jsObject.setProperty(
        'measureContextUsage'.toJS,
        ((JSString input) {
          return jsPromiseOf<JSNumber>((resolve, reject) {
            if (measureThrows) {
              reject(
                fakeDomException('InvalidStateError', 'session destroyed'),
              );
              return;
            }
            resolve(input.toDart.length.toDouble().toJS);
          });
        }).toJS,
      );
    }
  }

  final String Function(String input)? onPrompt;
  final List<String> Function(String input)? streamChunks;
  final bool cumulativeStream;
  final bool measureThrows;
  final bool omitMeasure;

  late final JSObject jsObject;
  final List<String> promptCalls = [];
  final List<String> promptStreamingCalls = [];

  /// The `signal` passed to the most recent `promptStreaming` call — lets a
  /// test assert consumer-cancel/stop aborted the in-flight generation via
  /// `isSignalAborted(session.lastStreamingSignal)`.
  JSObject? lastStreamingSignal;
  int destroyCount = 0;

  static List<String> _toCumulative(List<String> deltas) {
    var acc = '';
    return [for (final d in deltas) acc = acc + d];
  }
}

JSObject _fakeReadableStream(List<String> chunks, JSObject? signal) {
  var index = 0;
  var cancelled = false;

  JSPromise<JSObject> readImpl() {
    return jsPromiseOf<JSObject>((resolve, reject) async {
      await Future<void>.delayed(Duration.zero);
      if (cancelled) {
        final r = JSObject();
        r.setProperty('done'.toJS, true.toJS);
        resolve(r);
        return;
      }
      if (isSignalAborted(signal)) {
        reject(fakeDomException('AbortError'));
        return;
      }
      if (index >= chunks.length) {
        final r = JSObject();
        r.setProperty('done'.toJS, true.toJS);
        resolve(r);
        return;
      }
      final chunk = chunks[index++];
      final r = JSObject();
      r.setProperty('done'.toJS, false.toJS);
      r.setProperty('value'.toJS, chunk.toJS);
      resolve(r);
    });
  }

  final reader = JSObject();
  reader.setProperty('read'.toJS, (() => readImpl()).toJS);
  reader.setProperty(
    'cancel'.toJS,
    (([JSAny? reason]) {
      cancelled = true;
      return jsPromiseOf<JSAny?>((resolve, reject) => resolve(null));
    }).toJS,
  );

  final stream = JSObject();
  stream.setProperty('getReader'.toJS, (() => reader).toJS);
  return stream;
}

/// Builds a fake `self.LanguageModel` static object and plants it on
/// [globalContext] under the key `'LanguageModel'`. Call [FakeLanguageModel.dispose]
/// (or use the `withFakeLanguageModel` helper) to remove it afterwards.
class FakeLanguageModel {
  FakeLanguageModel({
    this._availability,
    this._create,
    this._maxTemperature = 2.0,
    this._maxTopK = 8,

    /// When true, `availability()` returns a Promise that never
    /// settles — simulates a stuck probe for the timeout test.
    bool neverResolveAvailability = false,

    /// When true, `create()` returns a Promise that never settles —
    /// simulates a download that never completes for the timeout test.
    bool neverResolveCreate = false,

    /// When true, `availability()` returns a Promise that REJECTS — simulates a
    /// transient browser/API failure the probe must map to `unavailableOther`
    /// rather than letting the raw JS error escape.
    bool rejectAvailability = false,
  }) {
    _jsObject = JSObject();
    _jsObject.setProperty(
      'availability'.toJS,
      (([JSObject? options]) {
        availabilityCalls++;
        if (neverResolveAvailability) {
          return jsPromiseOf<JSString>((resolve, reject) {});
        }
        if (rejectAvailability) {
          return jsPromiseOf<JSString>(
            (resolve, reject) =>
                reject(fakeDomException('UnknownError', 'boom')),
          );
        }
        final status = _availability?.call(options) ?? 'unavailable';
        return jsPromiseOf<JSString>((resolve, reject) => resolve(status.toJS));
      }).toJS,
    );
    _jsObject.setProperty(
      'create'.toJS,
      (([JSObject? options]) {
        createCalls.add(options);
        if (neverResolveCreate) {
          return jsPromiseOf<FakeSessionJs>((resolve, reject) {});
        }
        final session = _create?.call(options) ?? FakeSession();
        lastSession = session;
        return jsPromiseOf<FakeSessionJs>(
          (resolve, reject) => resolve(session.jsObject as FakeSessionJs),
        );
      }).toJS,
    );
    _jsObject.setProperty(
      'params'.toJS,
      (() {
        final p = JSObject();
        p.setProperty('maxTemperature'.toJS, _maxTemperature.toJS);
        p.setProperty('maxTopK'.toJS, _maxTopK.toJS);
        p.setProperty('defaultTemperature'.toJS, 1.0.toJS);
        p.setProperty('defaultTopK'.toJS, 3.toJS);
        return jsPromiseOf<JSObject>((resolve, reject) => resolve(p));
      }).toJS,
    );
  }

  final String Function([JSObject? options])? _availability;
  final FakeSession Function([JSObject? options])? _create;
  final double _maxTemperature;
  final int _maxTopK;

  late final JSObject _jsObject;
  int availabilityCalls = 0;
  final List<JSObject?> createCalls = [];
  FakeSession? lastSession;

  /// Plants this fake on `globalContext.LanguageModel`.
  void install() {
    globalContext.setProperty('LanguageModel'.toJS, _jsObject);
  }

  /// Removes `LanguageModel` from `globalContext` entirely (true absence,
  /// not just `undefined`) — required for the "unsupported browser" case.
  static void uninstall() {
    globalContext.delete('LanguageModel'.toJS);
  }
}

/// Opaque cast target — `FakeSession.jsObject` is a plain [JSObject]; the
/// production `LanguageModel.create()` static member declares its return
/// type as the `LanguageModelSession` extension type, which is a compile-time
/// view over the same underlying JSObject with no runtime tag, so any
/// JSObject shaped correctly satisfies it.
extension type FakeSessionJs._(JSObject _) implements JSObject {}
