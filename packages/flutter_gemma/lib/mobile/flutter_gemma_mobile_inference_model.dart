part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  MobileInferenceModel({
    required this.maxTokens,
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.preferredBackend,
    this.activeBackend,
    this.supportedLoraRanks,
    this.supportImage = false, // Enabling image support
    this.supportAudio = false, // Enabling audio support (Gemma 3n E4B)
    this.maxNumImages,
    this.maxConcurrentSessions,
  });

  final ModelType modelType;
  @override
  final ModelFileType fileType;
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
    chat = InferenceChat(
      sessionCreator: () => createSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? false,
        enableAudioModality: supportAudio ?? this.supportAudio,
        systemInstruction: systemInstruction,
        enableThinking: isThinking,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? false,
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
  final int maxTokens;
  @override
  final PreferredBackend? activeBackend;
  final VoidCallback onClose;
  final PreferredBackend? preferredBackend;
  final List<int>? supportedLoraRanks;
  final bool supportImage;
  final bool supportAudio;
  final int? maxNumImages;

  /// Cap on concurrent [openSession] sessions; null = unlimited. Wired for
  /// when the MediaPipe ProxyApi multi-session path lands; today
  /// [openSession] on the MediaPipe `.task` path throws UnsupportedError.
  final int? maxConcurrentSessions;

  bool _isClosed = false;
  MobileInferenceModelSession? _session;
  Completer<InferenceModelSession>? _createCompleter;

  /// Concurrent sessions opened via [openSession] — detached from the legacy
  /// [_session] singleton. Each owns one native `LlmInferenceSession`.
  final Set<MultiSessionMobileInferenceModelSession> _openSessions = {};

  /// Monotonic session-id generator. Starts at 1; the legacy singleton path
  /// carries no `sessionId` so there is no collision with these ids.
  int _nextSessionId = 1;

  /// Serializes generation across all open sessions — concurrent contexts,
  /// serialized inference (same model as the .litertlm FFI path). Avoids
  /// mobile OOM from parallel generations and keeps the shared event channel
  /// unambiguous.
  final Mutex _generationMutex = Mutex();

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
    List<Tool> tools =
        const [], // MediaPipe path: tools handled via chat.dart prompt
  }) async {
    if (_isClosed) {
      throw StateError(
          'Model is closed. Create a new instance to use it again');
    }
    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _createCompleter = Completer<InferenceModelSession>();
    try {
      // LoRA support is fully integrated via Modern API (InferenceInstallationBuilder)
      final resolvedLoraPath = loraPath;

      await _platformService.createSession(
        randomSeed: randomSeed,
        temperature: temperature,
        topK: topK,
        topP: topP,
        loraPath: resolvedLoraPath,
        // Enable vision modality if the model supports it
        enableVisionModality: enableVisionModality ?? supportImage,
        // Enable audio modality if the model supports it (Gemma 3n E4B)
        enableAudioModality: enableAudioModality ?? supportAudio,
        systemInstruction: systemInstruction,
        enableThinking: enableThinking,
      );

      final session = _session = MobileInferenceModelSession(
        modelType: modelType,
        fileType: fileType,
        supportImage: enableVisionModality ?? supportImage,
        supportAudio: enableAudioModality ?? supportAudio,
        systemInstruction: systemInstruction,
        onClose: () {
          _session = null;
          _createCompleter = null;
        },
      );
      completer.complete(session);
      return session;
    } catch (e, st) {
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
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
    final cap = maxConcurrentSessions;
    if (cap != null && _openSessions.length >= cap) {
      throw StateError(
        'Max concurrent sessions ($cap) reached. Close an existing session '
        'before opening a new one.',
      );
    }

    final id = _nextSessionId++;
    // MediaPipe holds N real LlmInferenceSession per engine — each call creates
    // an independent native session with its own KV cache. No singleton
    // overwrite; generation is serialized via [_generationMutex] on the
    // session objects, not here.
    await _platformService.createSessionForId(
      sessionId: id,
      randomSeed: randomSeed,
      temperature: temperature,
      topK: topK,
      topP: topP,
      loraPath: loraPath,
      enableVisionModality: enableVisionModality ?? supportImage,
      enableAudioModality: enableAudioModality ?? supportAudio,
      systemInstruction: systemInstruction,
      enableThinking: enableThinking,
    );

    late final MultiSessionMobileInferenceModelSession session;
    session = MultiSessionMobileInferenceModelSession(
      sessionId: id,
      modelType: modelType,
      fileType: fileType,
      supportImage: enableVisionModality ?? supportImage,
      supportAudio: enableAudioModality ?? supportAudio,
      systemInstruction: systemInstruction,
      generationMutex: _generationMutex,
      onClose: () => _openSessions.remove(session),
    );
    _openSessions.add(session);
    return session;
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    await _session?.close();
    // Copy because close() mutates _openSessions via the onClose callback.
    for (final s in _openSessions.toList()) {
      await s.close();
    }
    _openSessions.clear();
    onClose();
    await _platformService.closeModel();
  }
}
