// Part of flutter_gemma_web.dart so we can share [WebModelSourceResolver],
// [WebModelManager], and the engine-routing call-site without circular
// imports. All required imports (dart:js_interop, dart:js_interop_unsafe,
// extensions, message, model, tool, interface, litert_lm_web) live in the
// parent library file.
part of 'flutter_gemma_web.dart';

/// Web `.litertlm` inference via the upstream `@litert-lm/core` early-preview
/// JS API (LiteRT-LM v0.12.0+ on web through WebGPU/WASM).
///
/// Mirrors [FfiInferenceModel] (mobile/desktop) for the same C API but maps
/// it onto the JS surface: `Engine.create` → `engine.createConversation` →
/// `conversation.sendMessageStreaming(text)` returning a JS AsyncIterator.
///
/// **Limitations (matches upstream early-preview status):**
/// - Text-in/text-out only — vision/audio/thinking are warn-and-ignore.
/// - LoRA throws [UnsupportedError] (parity with FFI path).
/// - `stopGeneration()` closes the local stream but cannot abort the JS-side
///   generator — chunks after cancel are silently discarded.
/// - For models >2 GB use `WebStorageMode.streaming` so the resolver returns
///   an [OpfsStreamModelSource] — passing a Blob URL to `Engine.create`
///   trips Chrome's `ERR_BLOB_OUT_OF_MEMORY` limit. The
///   [WebModelSourceResolver] handles the routing transparently — same path
///   MediaPipe `WebInferenceModel` uses today.
class LiteRtLmWebInferenceModel extends InferenceModel {
  LiteRtLmWebInferenceModel({
    required this.sourceResolver,
    required this.maxTokens,
    required this.modelType,
    this.fileType = ModelFileType.litertlm,
    required this.onClose,
  });

  /// Shared with [WebInferenceModel] — resolves the active model into either
  /// a [BlobUrlModelSource] (cacheApi/none) or [OpfsStreamModelSource]
  /// (streaming). Engine-specific glue lives in [_ensureEngine] below.
  final WebModelSourceResolver sourceResolver;
  final ModelType modelType;
  @override
  final ModelFileType fileType;
  @override
  final int maxTokens;
  final VoidCallback onClose;

  LiteRtLmEngine? _engine;
  LiteRtLmWebSession? _session;
  Completer<InferenceModelSession>? _createCompleter;
  bool _isClosed = false;

  @override
  InferenceModelSession? get session => _session;

  Future<void> _ensureEngine() async {
    if (_engine != null) return;
    final resolved = await sourceResolver.resolveActiveInferenceModel();

    // The host page wires up `window.litertLmReady` (a Promise resolving to
    // the Engine constructor) in its index.html `<script type="module">`
    // block. Module scripts are deferred, so Dart can reach here before the
    // ESM finishes loading and `window.Engine` would be undefined. Awaiting
    // the readiness promise guarantees the @litert-lm/core module is loaded
    // before any static interop call on `LiteRtLmEngine`.
    final ready = globalContext.getProperty<JSObject?>('litertLmReady'.toJS);
    if (ready == null) {
      throw StateError(
        'window.litertLmReady is not set. The host page must include the '
        '@litert-lm/core ESM loader from example/web/index.html — see '
        'README "Web .litertlm setup".',
      );
    }
    await (ready as JSPromise).toDart;

    final JSAny modelArg;
    final String diagDescription;
    switch (resolved.model) {
      case BlobUrlModelSource(:final url):
        modelArg = url.toJS;
        diagDescription = url;
      case OpfsStreamModelSource(:final filename):
        modelArg = await (resolved.model as OpfsStreamModelSource).openStream();
        diagDescription = '<OPFS ReadableStream: $filename>';
    }

    if (kDebugMode) {
      debugPrint(
          '[LiteRtLmWebInferenceModel] Engine.create({model: $diagDescription})');
    }
    final sw = Stopwatch()..start();
    final engineFuture = LiteRtLmEngine.create(
      LiteRtLmEngineOptions(model: modelArg),
    );
    _engine = await engineFuture.toDart;
    if (kDebugMode) {
      debugPrint(
          '[LiteRtLmWebInferenceModel/perf] Engine.create: ${sw.elapsedMilliseconds}ms');
    }
  }

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
  }) async {
    if (_isClosed) {
      throw StateError(
          'Model is closed. Create a new instance to use it again');
    }
    if (loraPath != null) {
      throw UnsupportedError(
        'LoRA weights are not supported on the .litertlm web path '
        '(loraPath=$loraPath). Track upstream @litert-lm/core; remove '
        'loraPath or use a MediaPipe .task web model.',
      );
    }
    if (kDebugMode) {
      if (enableThinking) {
        debugPrint(
            '[LiteRtLmWebInferenceModel] Warning: enableThinking is not supported on '
            'the .litertlm web path (early preview). Ignored.');
      }
      if (enableVisionModality == true) {
        debugPrint(
            '[LiteRtLmWebInferenceModel] Warning: vision modality is not supported on '
            'the .litertlm web path (early preview). Ignored.');
      }
      if (enableAudioModality == true) {
        debugPrint(
            '[LiteRtLmWebInferenceModel] Warning: audio modality is not supported on '
            'the .litertlm web path (early preview). Ignored.');
      }
      if (tools.isNotEmpty) {
        debugPrint(
            '[LiteRtLmWebInferenceModel] Warning: native tool calling is not exposed '
            'by the @litert-lm/core early-preview API. Tools ignored — falling back to '
            'Dart-side prompt injection in chat.dart.');
      }
    }

    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _createCompleter = Completer<InferenceModelSession>();
    final sessionSw = Stopwatch()..start();

    try {
      await _ensureEngine();

      // Build preface JS object: {messages: [{role: 'system', content: '...'}]}
      // only when a system instruction was provided. Otherwise pass null so
      // the JS engine uses its default empty preface.
      JSObject? prefaceJs;
      if (systemInstruction != null && systemInstruction.isNotEmpty) {
        final prefaceMap = <String, Object>{
          'messages': <Map<String, Object>>[
            <String, Object>{
              'role': 'system',
              'content': systemInstruction,
            },
          ],
        };
        prefaceJs = prefaceMap.jsify() as JSObject;
      }

      final beforeConv = sessionSw.elapsedMilliseconds;
      final convoFuture = _engine!.createConversation(
        LiteRtLmConversationOptions(preface: prefaceJs),
      );
      final conversation = await convoFuture.toDart;
      if (kDebugMode) {
        debugPrint(
            '[LiteRtLmWebInferenceModel/perf] createConversation: ${sessionSw.elapsedMilliseconds - beforeConv}ms');
      }

      final session = _session = LiteRtLmWebSession(
        conversation: conversation,
        modelType: modelType,
        fileType: fileType,
        onClose: () {
          _session = null;
          _createCompleter = null;
        },
      );

      completer.complete(session);
      if (kDebugMode) {
        debugPrint(
            '[LiteRtLmWebInferenceModel/perf] createSession total: ${sessionSw.elapsedMilliseconds}ms');
      }
      return session;
    } catch (e, st) {
      completer.completeError(e, st);
      _createCompleter = null;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    try {
      await _session?.close();
    } finally {
      try {
        _engine?.delete();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[LiteRtLmWebInferenceModel] engine.delete() failed: $e');
        }
      }
      _engine = null;
      onClose();
    }
  }
}

/// Session-side accumulator + async iterator pump for `@litert-lm/core`.
///
/// Buffers query chunks the same way [FfiInferenceModelSession] does so that
/// `chat.dart` can keep its prompt-construction logic identical across
/// platforms. When [getResponse] or [getResponseAsync] is called, the
/// accumulated buffer is sent to `sendMessageStreaming` and the JS
/// AsyncIterator is driven manually via [LiteRtLmAsyncIter.next].
class LiteRtLmWebSession extends InferenceModelSession {
  LiteRtLmWebSession({
    required this.conversation,
    required this.modelType,
    required this.fileType,
    required this.onClose,
  });

  final LiteRtLmConversation conversation;
  final ModelType modelType;
  final ModelFileType fileType;
  final VoidCallback onClose;

  final StringBuffer _queryBuffer = StringBuffer();
  bool _isClosed = false;
  bool _isCancelled = false;

  void _assertNotClosed() {
    if (_isClosed) throw StateError('Session is closed');
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();
    final prompt =
        message.transformToChatPrompt(type: modelType, fileType: fileType);
    _queryBuffer.write(prompt);
    // Image / audio bytes are silently ignored — the upstream JS API is
    // text-only in early preview. The warning was already surfaced from
    // createSession() when supportImage/supportAudio was requested.
    if (message.hasImage || message.hasAudio) {
      if (kDebugMode) {
        debugPrint(
            '[LiteRtLmWebSession] Dropping non-text Message part — web .litertlm '
            'is text-only in upstream early preview.');
      }
    }
  }

  @override
  Future<String> getResponse() async {
    _assertNotClosed();
    final buf = StringBuffer();
    await for (final chunk in getResponseAsync()) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  @override
  Stream<String> getResponseAsync() {
    _assertNotClosed();
    final text = _queryBuffer.toString();
    _queryBuffer.clear();
    _isCancelled = false;

    final controller = StreamController<String>();
    final genSw = Stopwatch()..start();
    int? firstChunkMs;
    var chunkCount = 0;

    // `sendMessageStreaming` returns an AsyncIterable (object with
    // `Symbol.asyncIterator`), not an AsyncIterator (object with `.next`).
    // `for await (chunk of ...)` in JS does this normalization implicitly;
    // from Dart we have to call `[Symbol.asyncIterator]()` ourselves to get
    // the iterator before calling `.next()`. If the returned object already
    // exposes `.next` directly, the fallback returns it unchanged.
    final raw = conversation.sendMessageStreaming(text.toJS);
    final asyncIterSym = globalContext
        .getProperty<JSObject>('Symbol'.toJS)
        .getProperty<JSAny>('asyncIterator'.toJS);
    final factory = raw.getProperty<JSFunction?>(asyncIterSym);
    final iter = factory != null
        ? raw.callMethod<JSObject>(asyncIterSym)
        : raw; // assume it's already an iterator

    void pump() {
      if (controller.isClosed || _isCancelled) {
        if (!controller.isClosed) controller.close();
        return;
      }
      iter.next().toDart.then((JSObject step) {
        if (controller.isClosed || _isCancelled) {
          if (!controller.isClosed) controller.close();
          return;
        }
        final done = (step.getProperty<JSBoolean>('done'.toJS)).toDart;
        if (done) {
          if (kDebugMode) {
            final total = genSw.elapsedMilliseconds;
            debugPrint('[LiteRtLmWebSession/perf] generation total: ${total}ms '
                '(prefill ${firstChunkMs ?? 0}ms, $chunkCount chunks)');
          }
          controller.close();
          return;
        }
        if (firstChunkMs == null) {
          firstChunkMs = genSw.elapsedMilliseconds;
          if (kDebugMode) {
            debugPrint(
                '[LiteRtLmWebSession/perf] time-to-first-chunk: ${firstChunkMs}ms');
          }
        }
        chunkCount++;
        final value = step.getProperty<JSObject?>('value'.toJS);
        if (value != null) {
          final text = _extractText(value);
          if (text.isNotEmpty) controller.add(text);
        }
        pump();
      }, onError: (Object error, StackTrace st) {
        if (!controller.isClosed) {
          controller.addError(error, st);
          controller.close();
        }
      });
    }

    pump();
    controller.onCancel = () {
      _isCancelled = true;
    };
    return controller.stream;
  }

  /// Extract concatenated text from a chunk. The upstream `@litert-lm/core`
  /// early-preview shape is still in flux — try the documented
  /// `{content: [{type: 'text', text: '...'}]}` first, then fall back to a
  /// flat `{text: '...'}` or `{delta: {text: '...'}}` that the SDK has been
  /// observed to use. The first non-empty match wins; non-text payloads are
  /// silently skipped.
  String _extractText(JSObject chunk) {
    // Documented form: { content: [ {type: 'text', text: ...} ] }
    final content = chunk.getProperty<JSArray<JSObject>?>('content'.toJS);
    if (content != null) {
      final out = StringBuffer();
      final len = content.length;
      for (var i = 0; i < len; i++) {
        final item = content[i];
        final type = item.getProperty<JSString?>('type'.toJS)?.toDart;
        if (type == 'text') {
          final text = item.getProperty<JSString?>('text'.toJS)?.toDart;
          if (text != null) out.write(text);
        }
      }
      if (out.isNotEmpty) return out.toString();
    }
    // Fallback A: flat { text: '...' }
    final flat = chunk.getProperty<JSString?>('text'.toJS)?.toDart;
    if (flat != null && flat.isNotEmpty) return flat;
    // Fallback B: OpenAI-style { delta: { text: '...' } }
    final delta = chunk.getProperty<JSObject?>('delta'.toJS);
    if (delta != null) {
      final deltaText = delta.getProperty<JSString?>('text'.toJS)?.toDart;
      if (deltaText != null) return deltaText;
    }
    return '';
  }

  /// Approximate token count — matches `FfiInferenceModelSession.sizeInTokens`.
  /// The `@litert-lm/core` early-preview API does not expose a tokenizer.
  @override
  Future<int> sizeInTokens(String text) async => (text.length / 4).ceil();

  /// Stops the in-flight generation both locally (closes the Dart stream)
  /// and upstream (calls `conversation.cancel()` per the @litert-lm/core JS
  /// API). The cancel call is wrapped in try/catch because the early-preview
  /// API may throw if no generation is in flight.
  @override
  Future<void> stopGeneration() async {
    _isCancelled = true;
    try {
      conversation.cancel();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LiteRtLmWebSession] conversation.cancel() threw: $e');
      }
    }
  }

  /// LiteRT-LM web does not surface benchmark info; return empty metrics.
  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {
    _isClosed = true;
    _isCancelled = true;
    _queryBuffer.clear();
    onClose();
  }
}
