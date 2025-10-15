part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  MobileInferenceModel({
    required this.maxTokens,
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.preferredBackend,
    this.supportedLoraRanks,
    this.supportImage = false, // Enabling image support
    this.maxNumImages,
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
        enableVisionModality: supportImage ?? false,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? false,
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
  final int maxTokens;
  final VoidCallback onClose;
  final PreferredBackend? preferredBackend;
  final List<int>? supportedLoraRanks;
  final bool supportImage;
  final int? maxNumImages;

  bool _isClosed = false;
  MobileInferenceModelSession? _session;
  Completer<InferenceModelSession>? _createCompleter;

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
      );

      final session = _session = MobileInferenceModelSession(
        modelType: modelType,
        fileType: fileType,
        supportImage: supportImage,
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
  Future<void> close() async {
    _isClosed = true;
    await _session?.close();
    onClose();
    await _platformService.closeModel();
  }
}
