import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show InferenceModelSession, SessionMetrics;

import '../pigeon.g.dart';
import 'availability.dart' show builtInAiEventChannel;

/// One-time guard so the `countTokens` → char-heuristic fallback warns once per
/// isolate rather than on every call.
bool _tokenFallbackWarned = false;

@visibleForTesting
void resetTokenFallbackWarning() => _tokenFallbackWarned = false;

/// A generation session on an OS built-in model (Gemini Nano / Apple FM).
///
/// Every call is keyed by [sessionId]; generated tokens arrive on the shared
/// [builtInAiEventChannel] tagged with a `sessionId`, so this session demuxes
/// the stream by filtering to its own id — the same tagged-demux shape as the
/// mediapipe multi-session path.
class BuiltInAiSession extends InferenceModelSession {
  BuiltInAiSession({
    required this.sessionId,
    required this.service,
    required this.modelType,
    required this.onClose,
    this.fileType = ModelFileType.builtIn,
    this.supportImage = false,
    this.systemInstruction,
  });

  final int sessionId;
  final BuiltInAiService service;
  final ModelType modelType;
  final ModelFileType fileType;
  final bool supportImage;
  final String? systemInstruction;
  final VoidCallback onClose;

  bool _isClosed = false;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('Session is closed');
    }
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    _assertNotClosed();
    final prompt = message.transformToChatPrompt(
      type: modelType,
      fileType: fileType,
    );
    // Images go first so the native side has them buffered before the text
    // query is added (matches the mediapipe ordering).
    if (message.hasImage && supportImage) {
      final images = message.images.isNotEmpty
          ? message.images
          : (message.imageBytes != null
                ? <Uint8List>[message.imageBytes!]
                : const <Uint8List>[]);
      for (final image in images) {
        await service.addImage(sessionId: sessionId, imageBytes: image);
      }
    }
    await service.addQueryChunk(sessionId: sessionId, text: prompt);
  }

  @override
  Future<String> getResponse() async {
    _assertNotClosed();
    return service.generateResponse(sessionId);
  }

  @override
  Stream<String> getResponseAsync() {
    _assertNotClosed();

    // StreamController (not async*) so cleanup runs on done, error, AND
    // consumer cancel — an abandoned stream must still cancel the native
    // subscription.
    final controller = StreamController<String>();
    StreamSubscription<Object?>? subscription;
    var finished = false;

    Future<void> cleanup() async {
      if (finished) return;
      finished = true;
      await subscription?.cancel();
    }

    controller.onListen = () {
      subscription = builtInAiEventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is! Map) return;
          // Only consume events tagged for THIS session.
          if (event['sessionId'] != sessionId) return;
          if (controller.isClosed) return;
          // Native emits generation errors as a TAGGED DATA event
          // {code: ERROR, sessionId, message} (not an EventChannel error,
          // which would broadcast to every session and lose the id).
          if (event['code'] == 'ERROR') {
            controller.addError(
              Exception(event['message'] ?? 'Unknown async error occurred'),
            );
            cleanup();
            controller.close();
            return;
          }
          final partial = event['partialResult'] as String? ?? '';
          if (partial.isNotEmpty) controller.add(partial);
          if (event['done'] == true) {
            cleanup();
            controller.close();
          }
        },
        onError: (Object error, StackTrace st) {
          if (!controller.isClosed) controller.addError(error, st);
          cleanup();
          if (!controller.isClosed) controller.close();
        },
      );

      // Kick off generation; a synchronous native failure (before any event)
      // must surface and close the controller rather than hang.
      service.generateResponseAsync(sessionId).catchError((
        Object e,
        StackTrace st,
      ) {
        if (!controller.isClosed) controller.addError(e, st);
        cleanup();
        if (!controller.isClosed) controller.close();
      });
    };

    controller.onCancel = () async {
      await cleanup();
    };

    return controller.stream;
  }

  @override
  Future<int> sizeInTokens(String text) async {
    _assertNotClosed();
    try {
      return await service.countTokens(text);
    } on PlatformException {
      // Host doesn't expose a tokenizer — fall back to a rough char heuristic.
      if (!_tokenFallbackWarned) {
        _tokenFallbackWarned = true;
        gemmaLog(
          '[BuiltInAI] countTokens is unavailable on this host; falling back '
          'to a (text.length / 4) estimate. Token counts are approximate.',
        );
      }
      return (text.length / 4).ceil();
    }
  }

  @override
  Future<void> stopGeneration() async {
    await service.stopGeneration(sessionId);
  }

  @override
  SessionMetrics getSessionMetrics() => SessionMetrics();

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    onClose();
    await service.closeSession(sessionId);
  }
}
