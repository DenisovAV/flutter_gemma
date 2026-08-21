@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// JS interop for the Chrome **Prompt API** (`self.LanguageModel`), verified
/// against the Aug-2026 shipped surface. Unlike `@litert-lm/core`
/// (`litert_lm_web.dart`), there is **no CDN script, no `<script>` tag to add
/// to `index.html`** — `LanguageModel` is a bare global the browser itself
/// exposes when the Prompt API is enabled (origin trial / flag / extension
/// context). The ONE seam every caller must gate on is [hasLanguageModel]
/// (`'LanguageModel' in self`).
///
/// API surface mirrored (https://developer.chrome.com/docs/ai/prompt-api):
/// ```js
/// const status = await LanguageModel.availability(opts?);
/// const session = await LanguageModel.create(opts?);
/// const params = await LanguageModel.params();
///
/// const text = await session.prompt(input, opts?);
/// const stream = session.promptStreaming(input, opts?); // ReadableStream<string>
/// await session.append(input);
/// const clone = await session.clone(opts?);
/// session.destroy();
/// const used = await session.measureContextUsage(input);
/// session.contextUsage; session.contextWindow; // getters
/// ```
///
/// `create`/`availability` options and `prompt`/`promptStreaming` options are
/// built with `jsify()` from a plain Dart `Map` (see [buildCreateOptions] /
/// [buildPromptOptions]) rather than a `@staticInterop` `factory` — the same
/// opaque-`JSObject`-via-jsify move `litert_lm_web.dart` uses for forward
/// compatibility with an evolving upstream shape.
@JS('LanguageModel')
extension type LanguageModel._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability([JSObject? options]);
  external static JSPromise<LanguageModelSession> create([JSObject? options]);
  external static JSPromise<JSObject> params();
}

extension type LanguageModelSession._(JSObject _) implements JSObject {
  external JSPromise<JSString> prompt(JSAny input, [JSObject? options]);

  /// Returns a `ReadableStream<string>` — typed as the opaque [JSObject]
  /// since `dart:js_interop` has no first-class ReadableStream type. Driven
  /// via [readable_stream_pump.dart]'s `pumpText`.
  external JSObject promptStreaming(JSAny input, [JSObject? options]);

  external JSPromise<JSAny?> append(JSAny input);
  external JSPromise<LanguageModelSession> clone([JSObject? options]);

  /// Synchronous, per spec — releases the session immediately.
  external void destroy();

  external JSPromise<JSNumber> measureContextUsage(JSAny input);

  external double get contextUsage;
  external double get contextWindow;
}

/// `AbortController` — used to cancel an in-flight `create`/`prompt`/
/// `promptStreaming` call (passed as `signal` in the options object) and to
/// bound `ensureReady`'s download wait.
extension type AbortController._(JSObject _) implements JSObject {
  external factory AbortController();

  external JSObject get signal;
  external void abort([JSAny? reason]);
}

extension type AbortSignal._(JSObject _) implements JSObject {
  external bool get aborted;
}

/// `'LanguageModel' in self` — the ONE feature-detection seam every web-arm
/// entry point gates on. `false` on every browser/platform without the
/// Prompt API (Firefox, Safari, mobile Chrome, desktop Chrome below the
/// enabling flag/origin-trial) — those degrade cleanly to
/// `BuiltInAiAvailability.unavailableDeviceUnsupported`, never a JS
/// `ReferenceError`.
bool get hasLanguageModel => globalContext.has('LanguageModel');

/// `typeof LanguageModel.params === 'function'`. The static `params()`
/// (`defaultTopK`/`maxTopK`/`maxTemperature` sampler bounds) was present in
/// early Prompt-API builds but **removed from the shipped surface by Chrome
/// 151** (only `availability` + `create` remain static). Gate the sampler
/// clamp on this so a browser without `params()` skips it silently instead of
/// throwing a `TypeError: LanguageModel.params is not a function` on every
/// session — `create()` validates the values regardless.
bool get hasLanguageModelParams {
  final lm = globalContext.getProperty<JSObject?>('LanguageModel'.toJS);
  return lm != null && lm.has('params');
}

/// Builds the `create`/`availability` options object:
/// `{ initialPrompts, temperature, topK, expectedInputs, expectedOutputs,
///   signal, monitor }`. `temperature`/`topK` are included ONLY together (or
/// neither) — the Prompt API rejects one without the other.
///
/// [onDownloadProgress], if given, is wired as `monitor(m) =>
/// m.addEventListener('downloadprogress', e => onDownloadProgress(e.loaded))`
/// — `e.loaded` is a fraction in `[0, 1]`.
JSObject buildCreateOptions({
  String? systemInstruction,
  double? temperature,
  int? topK,
  List<String>? expectedInputTypes,
  JSObject? signal,
  void Function(double loaded)? onDownloadProgress,
}) {
  final map = <String, Object?>{
    if (systemInstruction != null && systemInstruction.isNotEmpty)
      'initialPrompts': [
        {'role': 'system', 'content': systemInstruction},
      ],
    if (temperature != null && topK != null) ...{
      'temperature': temperature,
      'topK': topK,
    },
    if (expectedInputTypes != null && expectedInputTypes.isNotEmpty)
      'expectedInputs': [
        for (final t in expectedInputTypes) {'type': t},
      ],
    'signal': ?signal,
  };
  final jsOptions = map.jsify()! as JSObject;
  if (onDownloadProgress != null) {
    jsOptions.setProperty(
      'monitor'.toJS,
      ((JSObject monitor) {
        monitor.callMethod(
          'addEventListener'.toJS,
          'downloadprogress'.toJS,
          ((JSObject event) {
            final loaded = event
                .getProperty<JSNumber>('loaded'.toJS)
                .toDartDouble;
            onDownloadProgress(loaded);
          }).toJS,
        );
      }).toJS,
    );
  }
  return jsOptions;
}

/// Builds the `prompt`/`promptStreaming` options object:
/// `{ responseConstraint, omitResponseConstraintInput, signal }`.
JSObject? buildPromptOptions({
  Object? responseConstraint,
  bool? omitResponseConstraintInput,
  JSObject? signal,
}) {
  final map = <String, Object?>{
    'responseConstraint': ?responseConstraint,
    'omitResponseConstraintInput': ?omitResponseConstraintInput,
    'signal': ?signal,
  };
  if (map.isEmpty) return null;
  return map.jsify()! as JSObject;
}
