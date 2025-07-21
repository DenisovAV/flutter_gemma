part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  MobileInferenceModel({
    required this.maxTokens,
    required this.onClose,
    required this.modelManager,
    required this.modelType,
    this.preferredBackend,
    this.supportedLoraRanks,
    this.supportImage = false, // Enabling image support
    this.maxNumImages,
  });

  final ModelType modelType;
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
      modelType: modelType, // Pass the actual model type!
    );
    await chat!.initSession();
    return chat!;
  }

  @override
  final int maxTokens;
  final VoidCallback onClose;
  final MobileModelManager modelManager;
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
      throw Exception('Model is closed. Create a new instance to use it again');
    }
    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _createCompleter = Completer<InferenceModelSession>();
    try {
      final (isLoraInstalled, File? loraFile) = await (
        modelManager.isLoraInstalled,
        modelManager._loraFile,
      ).wait;

      final resolvedLoraPath =
          (isLoraInstalled && loraFile != null) ? loraFile.path : loraPath;

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
        supportImage: supportImage,
        onClose: () {
          _session = null;
          _createCompleter = null;
        },
      );
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

