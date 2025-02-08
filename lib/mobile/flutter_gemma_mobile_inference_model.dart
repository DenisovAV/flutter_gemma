part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  MobileInferenceModel({required this.onClose, required this.modelManager});

  final VoidCallback onClose;
  final MobileModelManager modelManager;
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
  }) async {
    if (_isClosed) {
      throw Exception('Model is closed. Create a new instance to use it again');
    }
    if (_createCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _createCompleter = Completer<InferenceModelSession>();
    try {
      final (isLoraInstalled, loraFile) = await (
        modelManager.isLoraInstalled,
        modelManager._loraFile,
      ).wait;
      await _platformService.createSession(
        randomSeed: randomSeed,
        temperature: temperature,
        topK: topK,
        loraPath: isLoraInstalled ? loraFile.path : null,
      );
      final session = _session = MobileInferenceModelSession(
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
  final VoidCallback onClose;
  bool _isClosed = false;

  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;

  MobileInferenceModelSession({required this.onClose});

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
  Future<String> getResponse({required String prompt, bool isChat = true}) async {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      final finalPrompt = isChat ? prompt.transformToChatPrompt() : prompt;
      return await _platformService.generateResponse(finalPrompt);
    } finally {
      completer.complete();
    }
  }

  @override
  Stream<String> getResponseAsync({required String prompt, bool isChat = true}) async* {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      final finalPrompt = isChat ? prompt.transformToChatPrompt() : prompt;
      final controller = _asyncResponseController = StreamController<String>();
      eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map && event.containsKey('code') && event['code'] == "ERROR") {
            controller.addError(Exception(event['message'] ?? 'Unknown async error occurred'));
          } else if (event is String) {
            controller.add(event);
          } else {
            controller.addError(Exception('Unknown event type: $event'));
          }
        },
        onError: (error, st) {
          controller.addError(error, st);
        },
        onDone: controller.close,
      );

      unawaited(_platformService.generateResponseAsync(finalPrompt));

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
