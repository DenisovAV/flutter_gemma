part of 'flutter_gemma_mobile.dart';

class MobileInferenceModel extends InferenceModel {
  final VoidCallback onClose;
  bool _isClosed = false;

  MobileInferenceModel({required this.onClose});

  void _assertNotClosed() {
    if (_isClosed) {
      throw Exception('Model is closed. Create a new instance to use it again');
    }
  }

  @override
  Future<String> getResponse({required String prompt}) async {
    _assertNotClosed();
    final response = await methodChannel.invokeMethod<String>(
      'getGemmaResponse',
      {'prompt': prompt},
    );
    if (response == null) {
      throw Exception('Response is null. This should not happen');
    }
    return response;
  }

  @override
  Stream<String> getResponseAsync({required String prompt}) {
    final StreamController<String> controller = StreamController<String>();

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

    methodChannel.invokeMethod('getGemmaResponseAsync', {'prompt': prompt}).catchError((error) {
      if (error is PlatformException) {
        controller.addError(Exception('Platform error: ${error.message}'));
      } else {
        controller.addError(Exception('Unknown invoke error: $error'));
      }
    });

    return controller.stream;
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    onClose();
    await methodChannel.invokeMethod('close');
  }
}
