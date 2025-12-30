part of 'flutter_gemma_desktop.dart';

/// Desktop implementation of InferenceModel using gRPC
class DesktopInferenceModel extends InferenceModel {
  DesktopInferenceModel({
    required this.grpcClient,
    required this.maxTokens,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
    required this.onClose,
  });

  final LiteRtLmClient grpcClient;
  final ModelType modelType;
  @override
  final ModelFileType fileType;
  @override
  final int maxTokens;
  final bool supportImage;
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
  }) async {
    if (_isClosed) {
      throw StateError('Model is closed. Create a new instance to use it again');
    }

    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }

    final completer = _createCompleter = Completer<InferenceModelSession>();

    try {
      // Create conversation on server
      await grpcClient.createConversation();

      final session = _session = DesktopInferenceModelSession(
        grpcClient: grpcClient,
        modelType: modelType,
        fileType: fileType,
        supportImage: enableVisionModality ?? supportImage,
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
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? this.supportImage,
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
    required this.onClose,
  });

  final LiteRtLmClient grpcClient;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final VoidCallback onClose;

  final StringBuffer _queryBuffer = StringBuffer();
  Uint8List? _pendingImage;
  bool _isClosed = false;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Session is closed');
    }
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();

    final prompt = message.transformToChatPrompt(type: modelType, fileType: fileType);
    _queryBuffer.write(prompt);

    if (message.hasImage && message.imageBytes != null && supportImage) {
      _pendingImage = message.imageBytes;
    }
  }

  @override
  Future<String> getResponse() async {
    _assertNotClosed();

    final text = _queryBuffer.toString();
    _queryBuffer.clear();

    final buffer = StringBuffer();

    if (_pendingImage != null) {
      await for (final token in grpcClient.chatWithImage(text, _pendingImage!)) {
        buffer.write(token);
      }
      _pendingImage = null;
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

    if (_pendingImage != null) {
      yield* grpcClient.chatWithImage(text, _pendingImage!);
      _pendingImage = null;
    } else {
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
