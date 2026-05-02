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

/// FFI implementation of InferenceModel using dart:ffi → LiteRT-LM C API.
/// Shared between desktop and mobile (iOS) for .litertlm models.
class FfiInferenceModel extends InferenceModel {
  FfiInferenceModel({
    required this.ffiClient,
    required this.maxTokens,
    required this.modelType,
    this.fileType = ModelFileType.litertlm,
    this.supportImage = false,
    this.supportAudio = false,
    required this.onClose,
  });

  final LiteRtLmFfiClient ffiClient;
  final ModelType modelType;
  @override
  final ModelFileType fileType;
  @override
  final int maxTokens;
  final bool supportImage;
  final bool supportAudio;
  final VoidCallback onClose;

  FfiInferenceModelSession? _session;
  Completer<InferenceModelSession>? _createCompleter;
  bool _isClosed = false;

  @override
  InferenceModelSession? get session => _session;

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
      ffiClient.createConversation(
        systemMessage: systemInstruction,
        toolsJson: toolsJson,
        temperature: temperature,
        topK: topK,
        topP: topP,
        seed: randomSeed,
      );
      debugPrint(
          '[FfiInferenceModel/perf] createConversation (FFI): ${sessionSw.elapsedMilliseconds - beforeConv}ms');

      final session = _session = FfiInferenceModelSession(
        ffiClient: ffiClient,
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
    } finally {
      ffiClient.shutdown();
      onClose();
    }
  }
}

/// FFI implementation of InferenceModelSession.
/// Buffers query chunks until [getResponse] is called.
class FfiInferenceModelSession extends InferenceModelSession
    with RawSdkResponseSession {
  FfiInferenceModelSession({
    required this.ffiClient,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required this.supportAudio,
    this.enableThinking = false,
    required this.onClose,
  });

  final LiteRtLmFfiClient ffiClient;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;
  final bool enableThinking;
  final VoidCallback onClose;

  final StringBuffer _queryBuffer = StringBuffer();
  Uint8List? _pendingImage;
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

    if (message.hasImage && message.imageBytes != null && supportImage) {
      _pendingImage = message.imageBytes;
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
    final image = _pendingImage;
    _pendingAudio = null;
    _pendingImage = null;

    final genSw = Stopwatch()..start();
    int? firstChunkMs;
    var chunkCount = 0;

    // For Gemma 4, walk raw SDK JSON so chat.dart can read `tool_calls` via
    // [LiteRtLmFfiClient.extractToolCalls]. Other models keep the existing
    // text-only fast path (raw JSON cache stays null).
    if (modelType == ModelType.gemma4) {
      final rawBuffer = StringBuffer();
      final textBuffer = StringBuffer();
      await for (final rawChunk in ffiClient.chatRaw(
        text,
        imageBytes: image,
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
    await for (final chunk in ffiClient.chat(
      text,
      imageBytes: image,
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
    debugPrint(
        '[FfiInferenceModelSession/perf] generation total: ${total}ms '
        '(prefill ${firstChunkMs}ms + decode ${decodeMs}ms over $chunks chunks, '
        '~$decodeRate chunks/sec)');
  }

  @override
  Stream<String> getResponseAsync() async* {
    _assertNotClosed();
    final text = _queryBuffer.toString();
    _queryBuffer.clear();
    final audio = _pendingAudio;
    final image = _pendingImage;
    _pendingAudio = null;
    _pendingImage = null;

    final genSw = Stopwatch()..start();
    int? firstChunkMs;
    var chunkCount = 0;

    if (modelType == ModelType.gemma4) {
      final rawBuffer = StringBuffer();
      await for (final rawChunk in ffiClient.chatRaw(
        text,
        imageBytes: image,
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
    await for (final chunk in ffiClient.chat(
      text,
      imageBytes: image,
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
  Future<int> sizeInTokens(String text) async {
    return (text.length / 4).ceil();
  }

  @override
  Future<void> stopGeneration() async {
    ffiClient.cancelGeneration();
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    _queryBuffer.clear();
    _pendingImage = null;
    _pendingAudio = null;
    ffiClient.closeConversation();
    onClose();
  }
}
