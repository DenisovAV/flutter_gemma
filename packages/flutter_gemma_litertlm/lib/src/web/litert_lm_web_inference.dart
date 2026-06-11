// Standalone library: the web `.litertlm` inference model + session. Lives in
// flutter_gemma_litertlm (extracted from core's flutter_gemma_web.dart). Imports
// the shared web infra (web_model_source, web_image_format) and core parsing
// directly so it no longer needs to be a `part of flutter_gemma_web.dart`.
import 'dart:async';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';

import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/parsing/sdk_response_parser.dart';
import 'package:flutter_gemma/core/parsing/sdk_text_extractor.dart';
import 'package:flutter_gemma/web/web_model_source.dart';
import 'package:flutter_gemma/web/web_image_format.dart';

import 'litert_lm_web.dart';

/// Web `.litertlm` inference via the upstream `@litert-lm/core` early-preview
/// JS API (LiteRT-LM v0.12.0+ on web through WebGPU/WASM).
///
/// Mirrors [FfiInferenceModel] (mobile/desktop) for the same C API but maps
/// it onto the JS surface: `Engine.create` → `engine.createConversation` →
/// `conversation.sendMessageStreaming(text)` returning a JS AsyncIterator.
///
/// **Limitations (matches upstream early-preview status):**
/// - Text-in/text-out only — vision/audio are warn-and-ignore (the TS
///   EngineSettings doesn't expose Audio/VisionExecutor yet).
/// - Thinking Mode IS supported for Gemma 4 (wires `extra_context:
///   {thinking: true}` + `filterChannelContentFromKvCache`, same as native).
/// - LoRA throws [UnsupportedError] (parity with FFI path).
/// - `stopGeneration()` closes the local stream and calls the upstream
///   `conversation.cancel()` to abort the JS-side generation (wrapped in
///   try/catch — the early-preview API may throw if nothing is in flight).
/// - For models >2 GB use `WebStorageMode.streaming` so the resolver returns
///   an [OpfsStreamModelSource] — passing a Blob URL to `Engine.create`
///   trips Chrome's `ERR_BLOB_OUT_OF_MEMORY` limit. The
///   [WebModelSourceResolver] handles the routing transparently — same path
///   MediaPipe `WebInferenceModel` uses today.
class LiteRtLmWebInferenceModel extends InferenceModel with CloseNotifier {
  LiteRtLmWebInferenceModel({
    required this.sourceResolver,
    required this.maxTokens,
    required this.modelType,
    this.fileType = ModelFileType.litertlm,
    this.maxConcurrentSessions,
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
  @override
  PreferredBackend? get activeBackend => null;

  /// Cap on concurrent [openSession] sessions; null = unlimited.
  final int? maxConcurrentSessions;
  final VoidCallback onClose;

  LiteRtLmEngine? _engine;
  LiteRtLmWebSession? _session;
  Completer<InferenceModelSession>? _createCompleter;
  bool _isClosed = false;

  /// Guards [_ensureEngine] against concurrent calls. Without it, two
  /// overlapping openSession/createSession calls both see `_engine == null`
  /// and both call `Engine.create`, leaking the first engine (JS/WASM + GPU
  /// resources) for the page lifetime.
  Completer<void>? _engineCompleter;

  /// Serializes generation across all sessions on this model — concurrent
  /// contexts, serialized inference, matching the FFI/MediaPipe paths. The
  /// `@litert-lm/core` engine is shared WebGPU/WASM state; parallel
  /// generations would contend for the accelerator. Passed to each session.
  final Mutex generationMutex = Mutex();

  /// Sessions opened via [openSession] — detached from the legacy [_session]
  /// singleton. Each owns its own `@litert-lm/core` Conversation JS object.
  final Set<LiteRtLmWebSession> _openSessions = {};

  @override
  InferenceModelSession? get session => _session;

  @override
  List<InferenceModelSession> get sessions => List.unmodifiable([
        if (_session != null) _session!,
        ..._openSessions,
      ]);

  Future<void> _ensureEngine() async {
    if (_engine != null) return;
    // Concurrent-call guard: a second caller awaits the first creation instead
    // of starting its own (which would leak an engine).
    if (_engineCompleter != null) {
      await _engineCompleter!.future;
      return;
    }
    final completer = _engineCompleter = Completer<void>();
    try {
      await _createEngine();
      completer.complete();
    } catch (e, st) {
      _engineCompleter = null; // allow retry
      completer.completeError(e, st);
      rethrow;
    }
  }

  Future<void> _createEngine() async {
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
      gemmaLog(
          '[LiteRtLmWebInferenceModel] Engine.create({model: $diagDescription})');
    }
    final sw = Stopwatch()..start();
    final engineFuture = LiteRtLmEngine.create(
      LiteRtLmEngineOptions(model: modelArg),
    );
    _engine = await engineFuture.toDart;
    if (kDebugMode) {
      gemmaLog(
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

    // Vision/audio modality on web @litert-lm/core@0.12.1 requires a
    // dedicated Vision/AudioExecutor to be loaded at Engine.create() time.
    // The WASM runtime asserts "Vision executor should not be null, please
    // TryLoadingVisionExecutor() first.", but the TypeScript-level
    // `EngineSettings` interface (wasm_binding_types.d.ts) only exposes
    // `getMutableMainExecutorSettings()` — there's no setter for
    // VisionExecutorSettings or AudioExecutorSettings in the early preview.
    // Engine logs confirm this with `max_num_images: 0` baked in at create.
    //
    // Until upstream adds the Vision/Audio executor setters to the JS API,
    // setting `visionModalityEnabled`/`audioModalityEnabled: true` in
    // SessionConfig throws "Audio options should not be null" / "Vision
    // options should not be null" — so we force-disable them and warn.
    if (enableVisionModality == true || enableAudioModality == true) {
      if (kDebugMode) {
        gemmaLog('[LiteRtLmWebInferenceModel] Warning: vision/audio modality '
            'is requested but @litert-lm/core@0.12.1 does not expose the '
            'Vision/AudioExecutor config in its TypeScript API — image/audio '
            'inputs are dropped on web until upstream extends EngineSettings. '
            'Track: https://github.com/google-ai-edge/LiteRT-LM');
      }
    }
    const visionEnabled = false;
    const audioEnabled = false;

    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _createCompleter = Completer<InferenceModelSession>();
    final sessionSw = Stopwatch()..start();

    try {
      final conversation = await _buildConversation(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        systemInstruction: systemInstruction,
        enableThinking: enableThinking,
        tools: tools,
        sw: sessionSw,
      );

      final session = _session = LiteRtLmWebSession(
        conversation: conversation,
        modelType: modelType,
        fileType: fileType,
        supportImage: visionEnabled,
        supportAudio: audioEnabled,
        generationMutex: generationMutex,
        onClose: () {
          _session = null;
          _createCompleter = null;
        },
      );

      completer.complete(session);
      if (kDebugMode) {
        gemmaLog(
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
  Future<InferenceModelSession> openSession({
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
        'LoRA weights are not supported on the .litertlm web path. '
        'Remove loraPath or use a MediaPipe .task web model.',
      );
    }
    final cap = maxConcurrentSessions;
    if (cap != null && _openSessions.length >= cap) {
      throw StateError(
        'Max concurrent sessions ($cap) reached. Close an existing session '
        'before opening a new one.',
      );
    }
    // Vision/audio still blocked upstream (@litert-lm/core@0.12.1) — see the
    // detailed comment in createSession. Force-disable here too.
    if ((enableVisionModality == true || enableAudioModality == true) &&
        kDebugMode) {
      gemmaLog('[LiteRtLmWebInferenceModel] Warning: vision/audio modality '
          'is dropped on the web .litertlm path until upstream extends '
          'EngineSettings.');
    }

    await _ensureEngine();
    final conversation = await _buildConversation(
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      topP: topP,
      systemInstruction: systemInstruction,
      enableThinking: enableThinking,
      tools: tools,
      sw: Stopwatch()..start(),
    );

    late final LiteRtLmWebSession session;
    session = LiteRtLmWebSession(
      conversation: conversation,
      modelType: modelType,
      fileType: fileType,
      supportImage: false,
      supportAudio: false,
      generationMutex: generationMutex,
      onClose: () => _openSessions.remove(session),
    );
    _openSessions.add(session);
    return session;
  }

  /// Builds an `@litert-lm/core` Conversation from sampler + preface config.
  /// Shared by [createSession] (legacy singleton) and [openSession]
  /// (detached) so the JS interop and tool/thinking wiring stay in one place.
  Future<LiteRtLmConversation> _buildConversation({
    required double temperature,
    required int randomSeed,
    required int topK,
    double? topP,
    String? systemInstruction,
    required bool enableThinking,
    required List<Tool> tools,
    required Stopwatch sw,
  }) async {
    await _ensureEngine();

    // Build SessionConfig matching upstream TS: { samplerParams? }
    // Vision/audio modality intentionally not set — they require
    // AudioExecutor/VisionExecutor at Engine.create() which the TS
    // EngineSettings doesn't expose yet.
    final sessionConfigMap = <String, Object>{
      'samplerParams': <String, Object>{
        'temperature': temperature,
        'k': topK,
        if (topP != null) 'p': topP,
        'seed': randomSeed,
      },
    };
    final sessionConfigJs = sessionConfigMap.jsify() as JSObject?;

    // Build Preface matching upstream TS:
    //   { messages?: Message[], tools?: Tool[], extra_context?: {...} }
    final prefaceMessages = <Map<String, Object>>[];
    if (systemInstruction != null && systemInstruction.isNotEmpty) {
      prefaceMessages.add(<String, Object>{
        'role': 'system',
        'content': systemInstruction,
      });
    }
    // Tools — only push for Gemma 4, identical to native FFI gating in
    // `FfiInferenceModel.createSession`. Reuses
    // [SdkResponseParser.serializeToolsForSdk] so the JSON shape is
    // byte-identical between web and native.
    final toolsForPreface = (modelType == ModelType.gemma4 && tools.isNotEmpty)
        ? (jsonDecode(SdkResponseParser.serializeToolsForSdk(tools))
            as List<dynamic>)
        : const <dynamic>[];
    final prefaceMap = <String, Object>{
      if (prefaceMessages.isNotEmpty) 'messages': prefaceMessages,
      if (toolsForPreface.isNotEmpty) 'tools': toolsForPreface,
      if (enableThinking) 'extra_context': <String, Object>{'thinking': true},
    };
    final prefaceJs =
        prefaceMap.isNotEmpty ? prefaceMap.jsify() as JSObject : null;

    final beforeConv = sw.elapsedMilliseconds;
    final convoFuture = _engine!.createConversation(
      LiteRtLmConversationOptions(
        sessionConfig: sessionConfigJs,
        preface: prefaceJs,
        filterChannelContentFromKvCache: enableThinking ? true : null,
        enableConstrainedDecoding: toolsForPreface.isNotEmpty ? true : null,
      ),
    );
    final conversation = await convoFuture.toDart;
    if (kDebugMode) {
      gemmaLog(
          '[LiteRtLmWebInferenceModel/perf] createConversation: ${sw.elapsedMilliseconds - beforeConv}ms');
    }
    return conversation;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      await _session?.close();
      for (final s in _openSessions.toList()) {
        await s.close();
      }
      _openSessions.clear();
    } finally {
      try {
        _engine?.delete();
      } catch (e) {
        if (kDebugMode) {
          gemmaLog('[LiteRtLmWebInferenceModel] engine.delete() failed: $e');
        }
      }
      _engine = null;
      onClose();
      fireCloseListeners();
    }
  }
}

/// Session-side accumulator + async iterator pump for `@litert-lm/core`.
///
/// Mirrors [FfiInferenceModelSession] (lib/core/ffi/ffi_inference_model.dart)
/// 1:1 — same buffering of query chunks, same Gemma 4 raw-JSON-accumulating
/// branch, same `with RawSdkResponseSession` mixin so [InferenceChat] reads
/// `lastRawResponse` and extracts `tool_calls` via the shared
/// [SdkResponseParser]. The only platform-specific bit is that here the JS
/// AsyncIterator is driven manually via [LiteRtLmAsyncIter.next] rather than
/// a Dart `Stream` from native FFI.
class LiteRtLmWebSession extends InferenceModelSession
    with RawSdkResponseSession {
  LiteRtLmWebSession({
    required this.conversation,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required this.supportAudio,
    required this.generationMutex,
    required this.onClose,
  });

  final LiteRtLmConversation conversation;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;

  /// Shared across all sessions of the owning model — serializes generation
  /// (concurrent contexts, serialized inference). Acquired for the whole
  /// duration of a getResponse(Async) call.
  final Mutex generationMutex;
  final VoidCallback onClose;

  final StringBuffer _queryBuffer = StringBuffer();
  final List<Uint8List> _pendingImages = [];
  Uint8List? _pendingAudio;
  bool _isClosed = false;
  bool _isCancelled = false;

  /// Last full raw JSON response from SDK — Gemma 4 path only.
  /// chat.dart reads it via [lastRawResponse] and runs
  /// [SdkResponseParser.extractToolCalls] on it before falling back to text
  /// extraction. Mirrors [FfiInferenceModelSession._lastRawResponse].
  String? _lastRawResponse;

  @override
  String? get lastRawResponse => _lastRawResponse;

  /// JS `JSON.stringify` handle, looked up once per session.
  late final JSObject _jsJson =
      globalContext.getProperty<JSObject>('JSON'.toJS);

  String _stringifyChunk(JSObject value) =>
      _jsJson.callMethod<JSString>('stringify'.toJS, value).toDart;

  void _assertNotClosed() {
    if (_isClosed) throw StateError('Session is closed');
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();
    final prompt =
        message.transformToChatPrompt(type: modelType, fileType: fileType);
    _queryBuffer.write(prompt);
    if (message.hasImage && supportImage) {
      if (message.imageBytes != null) {
        _pendingImages.add(message.imageBytes!);
      }
      for (final image in message.images) {
        if (!_pendingImages.contains(image)) {
          _pendingImages.add(image);
        }
      }
    }
    if (message.hasAudio && message.audioBytes != null && supportAudio) {
      _pendingAudio = message.audioBytes;
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
    final images =
        _pendingImages.isNotEmpty ? List<Uint8List>.from(_pendingImages) : null;
    final audio = _pendingAudio;
    _pendingImages.clear();
    _pendingAudio = null;
    _isCancelled = false;

    final controller = StreamController<String>();
    final genSw = Stopwatch()..start();
    int? firstChunkMs;
    var chunkCount = 0;

    // Serialize generation across all sessions of this model. Acquired before
    // the pump starts (in onListen) and released exactly once in every
    // terminal path (done / error / consumer cancel) so an abandoned stream
    // can't hold the lock forever.
    var mutexHeld = false;
    var released = false;
    void releaseMutex() {
      if (released) return;
      released = true;
      if (mutexHeld) generationMutex.release();
    }

    // Build the request payload:
    //  * pure text → pass a plain string (legacy fast path).
    //  * any image/audio → build a Message object with a `content` array of
    //    MessageContentItem (one text + N image/audio items), shaped per the
    //    upstream TS declarations.
    final JSAny messageArg;
    if ((images == null || images.isEmpty) && audio == null) {
      messageArg = text.toJS;
    } else {
      final contentItems = <Map<String, Object>>[
        if (text.isNotEmpty) <String, Object>{'type': 'text', 'text': text},
        if (images != null)
          for (final img in images)
            <String, Object>{
              'type': 'image',
              // Data URL is the broadest-compatible shape; upstream `path` can
              // also be a Blob URL or a file URL once we wire those.
              'image_url': <String, Object>{
                // Reuse the shared magic-number detector promoted to the public
                // detectImageMimeType util (PNG / JPEG / WebP).
                'url':
                    'data:${detectImageMimeType(img)};base64,${base64Encode(img)}',
              },
            },
        if (audio != null)
          <String, Object>{
            'type': 'audio',
            // Audio payload (PCM 16kHz mono) per the native FFI contract.
            'input_audio': <String, Object>{
              'data': base64Encode(audio),
              'format': 'wav',
            },
          },
      ];
      messageArg = <String, Object>{
        'role': 'user',
        'content': contentItems,
      }.jsify() as JSAny;
    }
    // Gemma 4 path mirrors FfiInferenceModelSession.getResponseAsync — every
    // raw chunk is stringified and appended to rawBuffer so chat.dart can
    // run SdkResponseParser.extractToolCalls on the assembled JSON. Other
    // model types skip accumulation and `_lastRawResponse` stays null.
    final accumulateRaw = modelType == ModelType.gemma4;
    final rawBuffer = accumulateRaw ? StringBuffer() : null;
    if (accumulateRaw) {
      _lastRawResponse = null;
    }

    void startPump() {
      final raw = conversation.sendMessageStreaming(messageArg);
      final asyncIterSym = globalContext
          .getProperty<JSObject>('Symbol'.toJS)
          .getProperty<JSAny>('asyncIterator'.toJS);
      final factory = raw.getProperty<JSFunction?>(asyncIterSym);
      final iter = factory != null
          ? raw.callMethod<JSObject>(asyncIterSym)
          : raw; // assume it's already an iterator

      void pump() {
        if (controller.isClosed || _isCancelled) {
          releaseMutex();
          if (!controller.isClosed) controller.close();
          return;
        }
        iter.next().toDart.then((JSObject step) {
          if (controller.isClosed || _isCancelled) {
            releaseMutex();
            if (!controller.isClosed) controller.close();
            return;
          }
          final done = (step.getProperty<JSBoolean>('done'.toJS)).toDart;
          if (done) {
            if (accumulateRaw) {
              _lastRawResponse = rawBuffer!.toString();
            }
            if (kDebugMode) {
              final total = genSw.elapsedMilliseconds;
              gemmaLog('[LiteRtLmWebSession/perf] generation total: ${total}ms '
                  '(prefill ${firstChunkMs ?? 0}ms, $chunkCount chunks)');
            }
            releaseMutex();
            controller.close();
            return;
          }
          if (firstChunkMs == null) {
            firstChunkMs = genSw.elapsedMilliseconds;
            if (kDebugMode) {
              gemmaLog(
                  '[LiteRtLmWebSession/perf] time-to-first-chunk: ${firstChunkMs}ms');
            }
          }
          chunkCount++;
          final value = step.getProperty<JSObject?>('value'.toJS);
          if (value != null) {
            // Stringify the JS chunk into the same JSON shape liblitert_lm
            // streams via the native FFI callback. Both engines then dump it
            // into the shared SdkTextExtractor — single source of truth for
            // text-vs-thinking extraction, identical to ffi_inference_model.dart.
            final jsonStr = _stringifyChunk(value);
            if (accumulateRaw) {
              rawBuffer!.write(jsonStr);
            }
            final text = SdkTextExtractor.extractTextFromResponse(jsonStr);
            if (text.isNotEmpty) controller.add(text);
          }
          pump();
        }, onError: (Object error, StackTrace st) {
          releaseMutex();
          if (!controller.isClosed) {
            controller.addError(error, st);
            controller.close();
          }
        });
      }

      pump();
    }

    // Acquire the model-wide generation mutex before kicking off generation,
    // so concurrent sessions take turns (serialized inference). Released in
    // every terminal path (done / error / cancel) via releaseMutex().
    controller.onListen = () async {
      try {
        await generationMutex.acquire();
        mutexHeld = true;
        if (_isCancelled || controller.isClosed) {
          releaseMutex();
          if (!controller.isClosed) await controller.close();
          return;
        }
        startPump();
      } catch (e, st) {
        releaseMutex();
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    };
    controller.onCancel = () {
      _isCancelled = true;
      releaseMutex();
    };
    return controller.stream;
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
        gemmaLog('[LiteRtLmWebSession] conversation.cancel() threw: $e');
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
    // Abort any in-flight JS generation BEFORE the model tears the engine
    // down. Without this, the model's close() → engine.delete() can free the
    // WASM/WebGPU state while a pending iter.next() Promise is still resolving
    // against this conversation (use-after-free). stopGeneration() does the
    // same; close() must too.
    try {
      conversation.cancel();
    } catch (e) {
      if (kDebugMode) {
        gemmaLog('[LiteRtLmWebSession] cancel during close threw: $e');
      }
    }
    _queryBuffer.clear();
    onClose();
  }
}
