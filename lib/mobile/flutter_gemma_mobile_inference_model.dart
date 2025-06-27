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

class MobileInferenceModelSession extends InferenceModelSession {
  final ModelType modelType;
  final VoidCallback onClose;
  final bool supportImage;
  bool _isClosed = false;

  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;

  MobileInferenceModelSession({
    required this.onClose,
    required this.modelType,
    this.supportImage = false,
  });

  void _assertNotClosed() {
    if (_isClosed) {
      throw Exception('Model is closed. Create a new instance to use it again');
    }
  }

  Future<void> _awaitLastResponse() async {
    if (_responseCompleter case Completer<void> completer) {
      await completer.future;
    }
  }

  @override
  Future<int> sizeInTokens(String text) => _platformService.sizeInTokens(text);

  @override
  Future<void> addQueryChunk(Message message) async {
    final finalPrompt = message.transformToChatPrompt(type: modelType);
    await _platformService.addQueryChunk(finalPrompt);
    if (message.hasImage && message.imageBytes != null && supportImage) {
      await _addImage(message.imageBytes!);
    }
  }

  Future<void> _addImage(Uint8List imageBytes) async {
    _assertNotClosed();
    if (!supportImage) {
      throw Exception('This model does not support images');
    }
    await _platformService.addImage(imageBytes);
  }

  @override
  Future<String> getResponse({Message? message}) async {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      if (message != null) {
        await addQueryChunk(message);
      }
      return await _platformService.generateResponse();
    } finally {
      completer.complete();
    }
  }

  @override
  Stream<String> getResponseAsync({Message? message}) async* {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      final controller = _asyncResponseController = StreamController<String>();
      eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map &&
              event.containsKey('code') &&
              event['code'] == "ERROR") {
            controller.addError(
                Exception(event['message'] ?? 'Unknown async error occurred'));
          } else if (event is Map && event.containsKey('partialResult')) {
            final partial = event['partialResult'] as String;
            controller.add(partial);
          } else {
            controller.addError(Exception('Unknown event type: $event'));
          }
        },
        onError: (error, st) {
          controller.addError(error, st);
        },
        onDone: controller.close,
      );

      if (message != null) {
        await addQueryChunk(message);
      }
      unawaited(_platformService.generateResponseAsync());

      yield* controller.stream;
    } finally {
      completer.complete();
      _asyncResponseController = null;
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    onClose();
    _asyncResponseController?.close();
    await _platformService.closeSession();
  }
}
