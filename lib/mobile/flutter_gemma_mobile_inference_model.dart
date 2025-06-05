part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  MobileInferenceModel({
    required this.maxTokens,
    required this.onClose,
    required this.modelManager,
    required this.modelType,
    this.preferredBackend,
    this.supportedLoraRanks,
  });

  final ModelType modelType;
  @override
  final int maxTokens;
  final VoidCallback onClose;
  final MobileModelManager modelManager;
  final PreferredBackend? preferredBackend;
  final List<int>? supportedLoraRanks;
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
      );

      final session = _session = MobileInferenceModelSession(
        modelType: modelType,
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
  bool _isClosed = false;
  bool _isCancelled = false;

  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;

  MobileInferenceModelSession({
    required this.onClose,
    required this.modelType,
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
    _isCancelled = false;
    final completer = _responseCompleter = Completer<void>();
    try {
      final controller = _asyncResponseController = StreamController<String>();
      eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (_isCancelled) return;
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
          if (!_isCancelled) {
            controller.addError(error, st);
          }
        },
        onDone: controller.close,
      );

      if (message != null) {
        await addQueryChunk(message);
      }
      unawaited(_platformService.generateResponseAsync());

      yield* controller.stream;
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _asyncResponseController = null;
    }
  }

  @override
  Future<void> cancelGenerateResponseAsync() async {
    _assertNotClosed();
    _isCancelled = true;
    await _platformService.cancelGenerateResponseAsync();
    _asyncResponseController?.close();
    _responseCompleter?.complete();
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    onClose();
    _asyncResponseController?.close();
    await _platformService.closeSession();
  }
}
