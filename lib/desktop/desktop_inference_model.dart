part of 'flutter_gemma_desktop.dart';

/// Desktop implementation of InferenceModel using gRPC
class DesktopInferenceModel extends InferenceModel {
  DesktopInferenceModel({
    required this.grpcClient,
    required this.maxTokens,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
    this.supportAudio = false,
    required this.onClose,
  });

  final LiteRtLmClient grpcClient;
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
  }) async {
    if (_isClosed) {
      throw StateError('Model is closed. Create a new instance to use it again');
    }

    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }

    final completer = _createCompleter = Completer<InferenceModelSession>();

    try {
      // Create conversation on server with sampler config
      await grpcClient.createConversation(
        temperature: temperature,
        topK: topK,
        topP: topP,
      );

      final session = _session = DesktopInferenceModelSession(
        grpcClient: grpcClient,
        modelType: modelType,
        fileType: fileType,
        supportImage: enableVisionModality ?? supportImage,
        supportAudio: enableAudioModality ?? supportAudio,
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
      try {
        await grpcClient.shutdown();
      } finally {
        try {
          await grpcClient.disconnect();
        } finally {
          onClose();
        }
      }
    }
  }
}

/// Desktop implementation of InferenceModelSession
class DesktopInferenceModelSession extends InferenceModelSession {
  DesktopInferenceModelSession({
    required this.grpcClient,
    required this.modelType,
    required this.fileType,
    required this.supportImage,
    required this.supportAudio,
    required this.onClose,
  });

  final LiteRtLmClient grpcClient;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final bool supportAudio;
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
    debugPrint('[DesktopSession] addQueryChunk: hasAudio=${message.hasAudio}, audioBytes=${message.audioBytes?.length}, supportAudio=$supportAudio');

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

    // Capture and clear pending media BEFORE making the call
    // This prevents stale media from being reused if the call fails
    final audio = _pendingAudio;
    final image = _pendingImage;
    _pendingAudio = null;
    _pendingImage = null;

    final buffer = StringBuffer();

    if (audio != null) {
      await for (final token in grpcClient.chatWithAudio(text, audio)) {
        buffer.write(token);
      }
    } else if (image != null) {
      await for (final token in grpcClient.chatWithImage(text, image)) {
        buffer.write(token);
      }
    } else {
      await for (final token in grpcClient.chat(text)) {
        buffer.write(token);
      }
    }

    return buffer.toString();
  }

  @override
  Stream<String> getResponseAsync() async* {
    _assertNotClosed();

    final text = _queryBuffer.toString();
    _queryBuffer.clear();

    // Capture and clear pending media BEFORE making the call
    // This prevents stale media from being reused if the call fails
    final audio = _pendingAudio;
    final image = _pendingImage;
    _pendingAudio = null;
    _pendingImage = null;

    debugPrint('[DesktopSession] getResponseAsync: audio=${audio?.length}, image=${image?.length}');

    if (audio != null) {
      debugPrint('[DesktopSession] Calling chatWithAudio: audio=${audio.length} bytes');
      yield* grpcClient.chatWithAudio(text, audio);
    } else if (image != null) {
      debugPrint('[DesktopSession] Calling chatWithImage: image=${image.length} bytes');
      yield* grpcClient.chatWithImage(text, image);
    } else {
      debugPrint('[DesktopSession] Calling chat (no image/audio)');
      yield* grpcClient.chat(text);
    }
  }

  @override
  Future<int> sizeInTokens(String text) async {
    // Approximate token count (LiteRT-LM doesn't expose tokenizer directly)
    // Using ~4 chars per token as rough estimate
    return (text.length / 4).ceil();
  }

  @override
  Future<void> stopGeneration() async {
    // gRPC streaming doesn't support mid-stream cancellation easily
    // For MVP, this is a no-op
    debugPrint('[DesktopSession] stopGeneration not fully implemented');
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    await grpcClient.closeConversation();
    onClose();
  }
}
