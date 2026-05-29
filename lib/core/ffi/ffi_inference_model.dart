import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../flutter_gemma_interface.dart';
import '../message.dart';
import '../model.dart';
import '../tool.dart';
import '../chat.dart';
import '../extensions.dart';
import '../parsing/sdk_response_parser.dart';
import 'litert_lm_client.dart';
import '../../pigeon.g.dart';

/// FFI implementation of InferenceModel using dart:ffi → LiteRT-LM C API.
/// Shared between desktop and mobile (iOS) for .litertlm models.
class FfiInferenceModel extends InferenceModel {
  FfiInferenceModel({
    required this.ffiClient,
    required this.maxTokens,
    required this.modelType,
    required this.activeBackend,
    this.fileType = ModelFileType.litertlm,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxConcurrentSessions,
    required this.onClose,
  });

  final LiteRtLmFfiClient ffiClient;
  final ModelType modelType;
  @override
  final ModelFileType fileType;
  @override
  final int maxTokens;
  @override
  final PreferredBackend? activeBackend;
  final bool supportImage;
  final bool supportAudio;

  /// Cap on concurrent [openSession] sessions; null = unlimited.
  final int? maxConcurrentSessions;
  final VoidCallback onClose;

  FfiInferenceModelSession? _session;
  Completer<InferenceModelSession>? _createCompleter;
  bool _isClosed = false;

  /// Sessions opened via [openSession] — detached from the legacy [_session]
  /// singleton. Each owns its own conversation handle.
  final Set<FfiInferenceModelSession> _openSessions = {};

  @override
  InferenceModelSession? get session => _session;

  @override
  List<InferenceModelSession> get sessions => List.unmodifiable([
        if (_session != null) _session!,
        ..._openSessions,
      ]);

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
        'LoRA weights are not supported on the .litertlm FFI path '
        '(loraPath=$loraPath). Track upstream LiteRT-LM C API support; '
        'remove loraPath or use a MediaPipe .task model on Android/iOS.',
      );
    }

    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }

    final completer = _createCompleter = Completer<InferenceModelSession>();
    final sessionSw = Stopwatch()..start();

    try {
      // For Gemma 4, push tools into the SDK conversation config so it can
      // render native `<|tool>declaration:...<tool|>` tokens via minja. Other
      // model types still use Dart-side prompt injection in chat.dart.
      final toolsJson = (modelType == ModelType.gemma4 && tools.isNotEmpty)
          ? SdkResponseParser.serializeToolsForSdk(tools)
          : null;

      final beforeConv = sessionSw.elapsedMilliseconds;
      // Legacy singleton lane: close the previous conversation (if any) and
      // open a fresh one. Mirrors the pre-multi-session overwrite contract.
      final handle = ffiClient.createConversationHandle(
        systemMessage: systemInstruction,
        toolsJson: toolsJson,
        temperature: temperature,
        topK: topK,
        topP: topP,
        seed: randomSeed,
      );
      await _session?.close();
      debugPrint(
          '[FfiInferenceModel/perf] createConversation (FFI): ${sessionSw.elapsedMilliseconds - beforeConv}ms');

      final session = _session = FfiInferenceModelSession(
        handle: handle,
        modelType: modelType,
        fileType: fileType,
        supportImage: enableVisionModality ?? supportImage,
        supportAudio: enableAudioModality ?? supportAudio,
        enableThinking: enableThinking,
        onClose: () {
          _session = null;
          _createCompleter = null;
        },
      );

      completer.complete(session);
      debugPrint(
          '[FfiInferenceModel/perf] createSession total: ${sessionSw.elapsedMilliseconds}ms');
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
        'LoRA weights are not supported on the .litertlm FFI path '
        '(loraPath=$loraPath). Remove loraPath or use a MediaPipe .task '
        'model on Android/iOS.',
      );
    }
    final cap = maxConcurrentSessions;
    if (cap != null && _openSessions.length >= cap) {
      throw StateError(
        'Max concurrent sessions ($cap) reached. Close an existing session '
        'before opening a new one.',
      );
    }

    final toolsJson = (modelType == ModelType.gemma4 && tools.isNotEmpty)
        ? SdkResponseParser.serializeToolsForSdk(tools)
        : null;

    // The LiteRT-LM engine allows only ONE live conversation at a time
    // (upstream #966), so concurrent sessions can't each hold a real native
    // conversation. Each session instead gets a virtual handle that keeps its
    // history in Dart and replays it into the single shared conversation on
    // demand (serialized by the client mutex). Logically concurrent contexts,
    // serialized inference. openSession() itself makes no native call, so it
    // never fails on the one-conversation limit.
    final handle = _VirtualConversationHandle(
      client: ffiClient,
      systemMessage: systemInstruction,
      toolsJson: toolsJson,
      temperature: temperature,
      topK: topK,
      topP: topP,
      seed: randomSeed,
    );

    late final FfiInferenceModelSession session;
    session = FfiInferenceModelSession(
      handle: handle,
      modelType: modelType,
      fileType: fileType,
      supportImage: enableVisionModality ?? supportImage,
      supportAudio: enableAudioModality ?? supportAudio,
      enableThinking: enableThinking,
      onClose: () => _openSessions.remove(session),
    );
    _openSessions.add(session);
    return session;
  }

  @override
  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false,
    ModelType? modelType,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxFunctionBufferLength,
    String? systemInstruction,
  }) async {
    if (_isClosed) {
      throw StateError(
          'Model is closed. Create a new instance to use it again');
    }
    chat = InferenceChat(
      sessionCreator: () => createSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? this.supportImage,
        enableAudioModality: supportAudio ?? this.supportAudio,
        systemInstruction: systemInstruction,
        enableThinking: isThinking,
        tools: tools,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? this.supportImage,
      supportAudio: supportAudio ?? this.supportAudio,
      supportsFunctionCalls: supportsFunctionCalls ?? false,
      maxFunctionBufferLength:
          maxFunctionBufferLength ?? defaultMaxFunctionBufferLength,
      tools: tools,
      modelType: modelType ?? this.modelType,
      isThinking: isThinking,
      fileType: fileType,
      toolChoice: toolChoice,
      systemInstruction: systemInstruction,
    );
    await chat!.initSession();
    return chat!;
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    try {
      await _session?.close();
      // Copy because close() mutates _openSessions via the onClose callback.
      for (final s in _openSessions.toList()) {
        await s.close();
      }
      _openSessions.clear();
    } finally {
      ffiClient.shutdown();
      onClose();
    }
  }
}

/// FFI implementation of InferenceModelSession.
/// Buffers query chunks until [getResponse] is called.
///
/// Routes all per-conversation native calls through [handle] — its own
/// [ConversationHandle] — so multiple sessions on one model are fully
/// isolated. [extractTextFromResponse] is a static helper on
/// [LiteRtLmFfiClient] and needs no instance.
class FfiInferenceModelSession extends InferenceModelSession
    with RawSdkResponseSession {
  FfiInferenceModelSession({
    required this.handle,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required this.supportAudio,
    this.enableThinking = false,
    required this.onClose,
  });

  final ConversationHandle handle;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;
  final bool enableThinking;
  final VoidCallback onClose;

  final StringBuffer _queryBuffer = StringBuffer();
  final List<Uint8List> _pendingImages = [];
  Uint8List? _pendingAudio;
  bool _isClosed = false;

  /// Last full raw JSON response from SDK. For Gemma 4 this is the structured
  /// OpenAI Chat Completions object (with `tool_calls` if any). chat.dart reads
  /// it via [lastRawResponse] before fallback to text extraction.
  String? _lastRawResponse;

  /// Most recent raw SDK JSON. Returns the response of the last [getResponse]
  /// or [getResponseAsync]. For Gemma 4 use [LiteRtLmFfiClient.extractToolCalls]
  /// on this string to surface tool calls.
  @override
  String? get lastRawResponse => _lastRawResponse;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Session is closed');
    }
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
    final text = _queryBuffer.toString();
    _queryBuffer.clear();
    final audio = _pendingAudio;
    final images =
        _pendingImages.isNotEmpty ? List<Uint8List>.from(_pendingImages) : null;
    _pendingAudio = null;
    _pendingImages.clear();

    final genSw = Stopwatch()..start();
    int? firstChunkMs;
    var chunkCount = 0;

    // For Gemma 4, walk raw SDK JSON so chat.dart can read `tool_calls` via
    // [LiteRtLmFfiClient.extractToolCalls]. Other models keep the existing
    // text-only fast path (raw JSON cache stays null).
    if (modelType == ModelType.gemma4) {
      final rawBuffer = StringBuffer();
      final textBuffer = StringBuffer();
      await for (final rawChunk in handle.chatRaw(
        text,
        imageBytes: images,
        audioBytes: audio,
        enableThinking: enableThinking,
      )) {
        if (firstChunkMs == null) {
          firstChunkMs = genSw.elapsedMilliseconds;
          debugPrint(
              '[FfiInferenceModelSession/perf] time-to-first-chunk (prefill): ${firstChunkMs}ms');
        }
        chunkCount++;
        rawBuffer.write(rawChunk);
        textBuffer.write(LiteRtLmFfiClient.extractTextFromResponse(rawChunk));
      }
      _lastRawResponse = rawBuffer.toString();
      _logGenerationStats(genSw, firstChunkMs, chunkCount);
      return textBuffer.toString();
    }

    _lastRawResponse = null;
    final buffer = StringBuffer();
    await for (final chunk in handle.chat(
      text,
      imageBytes: images,
      audioBytes: audio,
      enableThinking: enableThinking,
    )) {
      if (firstChunkMs == null) {
        firstChunkMs = genSw.elapsedMilliseconds;
        debugPrint(
            '[FfiInferenceModelSession/perf] time-to-first-chunk (prefill): ${firstChunkMs}ms');
      }
      chunkCount++;
      buffer.write(chunk);
    }
    _logGenerationStats(genSw, firstChunkMs, chunkCount);
    return buffer.toString();
  }

  void _logGenerationStats(Stopwatch sw, int? firstChunkMs, int chunks) {
    final total = sw.elapsedMilliseconds;
    if (firstChunkMs == null || chunks == 0) {
      debugPrint(
          '[FfiInferenceModelSession/perf] generation total: ${total}ms (no chunks emitted)');
      return;
    }
    final decodeMs = total - firstChunkMs;
    final decodeRate = chunks > 1 && decodeMs > 0
        ? ((chunks - 1) * 1000.0 / decodeMs).toStringAsFixed(1)
        : 'n/a';
    debugPrint('[FfiInferenceModelSession/perf] generation total: ${total}ms '
        '(prefill ${firstChunkMs}ms + decode ${decodeMs}ms over $chunks chunks, '
        '~$decodeRate chunks/sec)');
  }

  @override
  Stream<String> getResponseAsync() async* {
    _assertNotClosed();
    final text = _queryBuffer.toString();
    _queryBuffer.clear();
    final audio = _pendingAudio;
    final images =
        _pendingImages.isNotEmpty ? List<Uint8List>.from(_pendingImages) : null;
    _pendingAudio = null;
    _pendingImages.clear();

    final genSw = Stopwatch()..start();
    int? firstChunkMs;
    var chunkCount = 0;

    if (modelType == ModelType.gemma4) {
      final rawBuffer = StringBuffer();
      await for (final rawChunk in handle.chatRaw(
        text,
        imageBytes: images,
        audioBytes: audio,
        enableThinking: enableThinking,
      )) {
        if (firstChunkMs == null) {
          firstChunkMs = genSw.elapsedMilliseconds;
          debugPrint(
              '[FfiInferenceModelSession/perf] (async) time-to-first-chunk (prefill): ${firstChunkMs}ms');
        }
        chunkCount++;
        rawBuffer.write(rawChunk);
        yield LiteRtLmFfiClient.extractTextFromResponse(rawChunk);
      }
      _lastRawResponse = rawBuffer.toString();
      _logGenerationStats(genSw, firstChunkMs, chunkCount);
      return;
    }

    _lastRawResponse = null;
    await for (final chunk in handle.chat(
      text,
      imageBytes: images,
      audioBytes: audio,
      enableThinking: enableThinking,
    )) {
      if (firstChunkMs == null) {
        firstChunkMs = genSw.elapsedMilliseconds;
        debugPrint(
            '[FfiInferenceModelSession/perf] (async) time-to-first-chunk (prefill): ${firstChunkMs}ms');
      }
      chunkCount++;
      yield chunk;
    }
    _logGenerationStats(genSw, firstChunkMs, chunkCount);
  }

  @override
  SessionMetrics getSessionMetrics() {
    return handle.getSessionMetrics();
  }

  @override
  Future<int> sizeInTokens(String text) async {
    return (text.length / 4).ceil();
  }

  @override
  Future<void> stopGeneration() async {
    handle.cancelGeneration();
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    _queryBuffer.clear();
    _pendingImages.clear();
    _pendingAudio = null;
    handle.close();
    onClose();
  }
}

/// A [ConversationHandle] backed by the virtual-session multiplexer.
///
/// The LiteRT-LM engine allows only ONE live conversation at a time
/// (upstream #966), so concurrent [openSession] sessions can't each hold a
/// real native conversation. Instead each virtual handle keeps its full turn
/// history in Dart and, on every generate, asks the client to (re)materialize
/// the single shared conversation seeded with THIS session's history via a
/// `messages_json` preface. The client serializes turns with a mutex, so the
/// sessions are logically concurrent (independent contexts) but inference is
/// serialized (one generation at a time) — verified by the
/// session_switch / messages_preface smoke tests.
///
/// Same-session follow-up turns reuse the live conversation (no rebuild);
/// only switching to a different session pays the teardown+replay cost.
class _VirtualConversationHandle implements ConversationHandle {
  _VirtualConversationHandle({
    required this.client,
    required this.systemMessage,
    required this.toolsJson,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.seed,
  });

  final LiteRtLmFfiClient client;
  final String? systemMessage;
  final String? toolsJson;
  final double temperature;
  final int topK;
  final double? topP;
  final int seed;

  /// Unique identity for this virtual session — the client uses it to tell
  /// whether the live conversation already holds this session's history.
  final Object token = Object();

  /// Completed turns (user + assistant), replayed as a `messages_json`
  /// preface to rebuild this session's context when it next becomes active.
  final List<({String role, String text})> _history = [];

  bool _closed = false;

  /// Drive one turn through the multiplexer, then record the user message and
  /// the generated assistant reply so the NEXT turn replays them as preface.
  /// [extractText] maps each raw chunk to the text appended to the recorded
  /// assistant turn (text path strips JSON; raw path keeps the chunk for the
  /// caller but we still record only the extracted text in history).
  Stream<String> _run(
    String text, {
    required bool raw,
    bool enableThinking = false,
  }) async* {
    if (_closed) throw StateError('Conversation handle is closed');
    final messageJson = LiteRtLmFfiClient.buildMessageJson(text);
    final extraContext = enableThinking ? '{"enable_thinking": true}' : null;
    // Snapshot history BEFORE this turn — the live message is sent separately.
    final historySnapshot = List<({String role, String text})>.from(_history);
    final assistantText = StringBuffer();
    await for (final rawChunk in client.startVirtualTurn(
      conversationToken: token,
      messageJson: messageJson,
      history: historySnapshot,
      systemMessage: systemMessage,
      toolsJson: toolsJson,
      temperature: temperature,
      topK: topK,
      topP: topP,
      seed: seed,
      extraContext: extraContext,
    )) {
      final chunkText = LiteRtLmFfiClient.extractTextFromResponse(rawChunk);
      assistantText.write(chunkText);
      yield raw ? rawChunk : chunkText;
    }
    // Record both turns so the next switch back replays the full context.
    _history.add((role: 'user', text: text));
    _history.add((role: 'assistant', text: assistantText.toString()));
  }

  @override
  Stream<String> chat(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) =>
      _run(text, raw: false, enableThinking: enableThinking);

  @override
  Stream<String> chatRaw(
    String text, {
    List<Uint8List>? imageBytes,
    Uint8List? audioBytes,
    bool enableThinking = false,
  }) =>
      _run(text, raw: true, enableThinking: enableThinking);

  @override
  void cancelGeneration() => client.cancelVirtualTurn();

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _history.clear();
    client.releaseVirtualConversation(token);
  }
}
