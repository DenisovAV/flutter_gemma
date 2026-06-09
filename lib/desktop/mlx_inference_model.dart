import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/chat.dart';
import '../core/message.dart';
import '../core/model.dart';
import '../core/tool.dart';
import '../flutter_gemma_interface.dart';
import 'mlx_native_dispatch.dart';

class MlxInferenceModel extends InferenceModel {
  MlxInferenceModel({
    required this.dispatcher,
    required this.modelPath,
    required this.maxTokens,
    required this.modelType,
    required this.fileType,
    this.supportImage = false,
    this.supportAudio = false,
    required this.onClose,
  });

  final MlxDispatching dispatcher;
  final String modelPath;
  @override
  final int maxTokens;
  final ModelType modelType;
  @override
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;
  final VoidCallback onClose;

  MlxInferenceModelSession? _session;
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
        'LoRA weights are not yet supported on the MLX desktop runtime '
        '(loraPath=$loraPath). Use a merged MLX model directory instead.',
      );
    }

    await _session?.close();
    final session = _session = MlxInferenceModelSession(
      dispatcher: dispatcher,
      modelPath: modelPath,
      maxTokens: maxTokens,
      modelType: modelType,
      fileType: fileType,
      supportImage: enableVisionModality ?? supportImage,
      supportAudio: enableAudioModality ?? supportAudio,
      temperature: temperature,
      topP: topP,
      systemInstruction: systemInstruction,
      enableThinking: enableThinking,
      tools: tools,
      onClose: () => _session = null,
    );
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
    } finally {
      _session = null;
      onClose();
    }
  }
}

class MlxInferenceModelSession extends InferenceModelSession
    with RawSdkResponseSession {
  MlxInferenceModelSession({
    required this.dispatcher,
    required this.modelPath,
    required this.maxTokens,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required this.supportAudio,
    required this.temperature,
    required this.topP,
    required this.systemInstruction,
    required this.enableThinking,
    required this.tools,
    required this.onClose,
  });

  final MlxDispatching dispatcher;
  final String modelPath;
  final int maxTokens;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;
  final double temperature;
  final double? topP;
  final String? systemInstruction;
  final bool enableThinking;
  final List<Tool> tools;
  final VoidCallback onClose;

  final List<Message> _history = <Message>[];
  bool _isClosed = false;
  SessionMetrics _metrics = SessionMetrics();
  String? _lastRawResponse;

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
    if (message.hasImage) {
      throw UnsupportedError(
        'The built-in MLX desktop runtime currently supports text-only prompts. '
        'Pass image paths through a custom desktop runtime extension instead.',
      );
    }
    if (message.hasAudio) {
      throw UnsupportedError(
        'The built-in MLX desktop runtime currently supports text-only prompts. '
        'Transcribe audio before sending it to the session.',
      );
    }
    _history.add(message);
  }

  @override
  Future<String> getResponse() async {
    _assertNotClosed();
    if (_history.isEmpty) {
      throw StateError('No query chunks added before getResponse()');
    }

    final payload = <String, Object?>{
      'modelPath': modelPath,
      'runtimeAdapter': supportImage ? 'mlx_vlm' : 'mlx_lm',
      'messages': _toWireMessages(),
      'maxTokens': maxTokens,
      'temperature': temperature,
      if (topP != null) 'topP': topP,
      'enableThinking': enableThinking,
    };

    final response = dispatcher.invoke('lm.generate', payload);
    _lastRawResponse = jsonEncode(response);

    if (response['ok'] != true) {
      throw StateError('${response['error'] ?? 'MLX generation failed'}');
    }

    final text = (response['text'] as String?) ?? '';
    _metrics = _metricsFromResponse(response, text: text);
    _history.add(Message.text(text: text, isUser: false));
    return text;
  }

  @override
  Stream<String> getResponseAsync() async* {
    yield await getResponse();
  }

  @override
  Future<int> sizeInTokens(String text) async => _estimateTokens(text);

  @override
  Future<void> stopGeneration() async {}

  @override
  SessionMetrics getSessionMetrics() => _metrics;

  @override
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    onClose();
  }

  List<Map<String, String>> _toWireMessages() {
    final messages = <Map<String, String>>[];
    final instruction = systemInstruction?.trim();
    if (instruction != null && instruction.isNotEmpty) {
      messages.add(<String, String>{
        'role': 'system',
        'content': instruction,
      });
    }
    for (final message in _history) {
      messages.add(<String, String>{
        'role': _roleForMessage(message),
        'content': message.text,
      });
    }
    return messages;
  }

  String _roleForMessage(Message message) {
    if (message.type == MessageType.toolResponse) {
      return 'tool';
    }
    if (message.isUser) {
      return 'user';
    }
    return 'assistant';
  }

  SessionMetrics _metricsFromResponse(
    Map<String, Object?> response, {
    required String text,
  }) {
    final inputText = _history.map((message) => message.text).join('\n');
    final inputTokens = _estimateTokens(inputText);
    final outputTokens = _estimateTokens(text);
    final generateMs = _asDouble(response['swiftGenerateMs']);
    final ttftMs = _asDouble(response['swiftFirstTokenMs']);
    final loadMs = _asDouble(response['swiftLoadMs']);
    final tokensPerSecond = (generateMs != null && generateMs > 0)
        ? outputTokens * 1000 / generateMs
        : null;
    return SessionMetrics(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      totalTokens: inputTokens + outputTokens,
      timeToFirstTokenMs: ttftMs,
      tokensPerSecond: tokensPerSecond,
      initTimeMs: loadMs,
    );
  }

  double? _asDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    return null;
  }

  int _estimateTokens(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 0;
    }
    return ((trimmed.runes.length / 4).ceil().clamp(1, 1 << 30)) as int;
  }
}
