part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  MobileInferenceModel({required this.onClose});

  final VoidCallback onClose;
  bool _isClosed = false;
  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;

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
      final response = await methodChannel.invokeMethod<String>(
        'getGemmaResponse',
        {'prompt': finalPrompt},
      );
      if (response == null) {
        throw Exception('Response is null. This should not happen');
      }
      return response;
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

      methodChannel.invokeMethod('getGemmaResponseAsync', {'prompt': finalPrompt}).catchError((error) {
        if (error is PlatformException) {
          controller.addError(Exception('Platform error: ${error.message}'));
        } else {
          controller.addError(Exception('Unknown invoke error: $error'));
        }
      });

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
    await methodChannel.invokeMethod('close');
  }
}
