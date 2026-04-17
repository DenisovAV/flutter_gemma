part of 'flutter_gemma_desktop.dart';

/// Desktop implementation of InferenceModel using dart:ffi → LiteRT-LM C API
class DesktopInferenceModel extends InferenceModel {
  DesktopInferenceModel({
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

  DesktopInferenceModelSession? _session;
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
  }) async {
    if (_isClosed) {
      throw StateError('Model is closed. Create a new instance to use it again');
    }

    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }

    final completer = _createCompleter = Completer<InferenceModelSession>();

    try {
      // Create conversation on the native engine
      ffiClient.createConversation(
        systemMessage: systemInstruction,
        temperature: temperature,
        topK: topK,
        topP: topP,
        seed: randomSeed,
      );

      final session = _session = DesktopInferenceModelSession(
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
    String? systemInstruction,
  }) async {
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
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? this.supportImage,
      supportAudio: supportAudio ?? this.supportAudio,
      supportsFunctionCalls: supportsFunctionCalls ?? false,
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

/// Desktop implementation of InferenceModelSession using dart:ffi.
///
/// Buffers query chunks until [getResponse] is called, then sends
/// the complete message to LiteRT-LM via the C API.
class DesktopInferenceModelSession extends InferenceModelSession {
  DesktopInferenceModelSession({
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

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Session is closed');
    }
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();

    // For .litertlm on desktop, LiteRT-LM handles templates — use raw text
    final prompt = message.transformToChatPrompt(type: modelType, fileType: fileType);
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

    final buffer = StringBuffer();
    await for (final token in ffiClient.chat(
      text,
      imageBytes: image,
      audioBytes: audio,
      enableThinking: enableThinking,
    )) {
      buffer.write(token);
    }

    return buffer.toString();
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

    yield* ffiClient.chat(
      text,
      imageBytes: image,
      audioBytes: audio,
      enableThinking: enableThinking,
    );
  }

  @override
  Future<int> sizeInTokens(String text) async {
    // Approximate token count (LiteRT-LM C API doesn't expose tokenizer)
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
