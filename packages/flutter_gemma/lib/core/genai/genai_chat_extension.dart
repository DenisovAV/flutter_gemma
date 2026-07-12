import 'dart:async';

import 'package:genai_primitives/genai_primitives.dart';
import 'package:http/http.dart' as http;

import '../chat.dart';
import '../model_response.dart';
import '../utils/gemma_log.dart';
import 'genai_input_converter.dart';
import 'genai_output_converter.dart';

/// Guard: a model-role ChatMessage is output, not a sendMessage input.
void rejectModelRole(ChatMessage message) {
  if (message.role == ChatMessageRole.model) {
    throw ArgumentError(
      'sendMessage takes user input; a model turn is output. '
      'Use generateContent(List<ChatMessage>) to stage prior model turns.',
    );
  }
}

/// genai_primitives entry points on [InferenceChat]. See #181.
extension GenAiChat on InferenceChat {
  /// Send one turn; returns the model turn as a role:model [ChatMessage]
  /// (text + tool calls + thinking as parts).
  Future<ChatMessage> sendMessage(
    ChatMessage message, {
    http.Client? httpClient,
  }) {
    rejectModelRole(message);
    return genaiLock.protect(() async {
      await _stage([message], httpClient: httpClient);
      return _foldToChatMessage();
    });
  }

  /// Streaming variant — partial role:model ChatMessages, one per delta.
  Stream<ChatMessage> sendMessageStream(
    ChatMessage message, {
    http.Client? httpClient,
  }) {
    rejectModelRole(message);
    return _lockedStream(() async {
      await _stage([message], httpClient: httpClient);
    });
  }

  /// STATEFUL batch: stage the whole list into THIS chat, then generate once.
  Future<ChatMessage> generateContent(
    List<ChatMessage> prompt, {
    http.Client? httpClient,
  }) {
    return genaiLock.protect(() async {
      await _stage(prompt, httpClient: httpClient);
      return _foldToChatMessage();
    });
  }

  Stream<ChatMessage> generateContentStream(
    List<ChatMessage> prompt, {
    http.Client? httpClient,
  }) {
    return _lockedStream(() async {
      await _stage(prompt, httpClient: httpClient);
    });
  }

  // --- internals ---

  Future<void> _stage(
    List<ChatMessage> prompt, {
    http.Client? httpClient,
  }) async {
    final messages = await messagesFromChatMessages(
      prompt,
      httpClient: httpClient,
    );
    assertMessagesFitChat(
      messages,
      supportImage: supportImage,
      supportAudio: supportAudio,
      supportsFunctionCalls: supportsFunctionCalls,
    );
    for (final m in messages) {
      await addQueryChunk(m);
    }
  }

  /// Drive the async generate path, folding all events into one ChatMessage.
  Future<ChatMessage> _foldToChatMessage() async {
    final text = StringBuffer();
    final thinking = StringBuffer();
    final calls = <FunctionCallResponse>[];
    await for (final r in generateChatResponseAsync()) {
      switch (r) {
        case TextResponse(:final token):
          text.write(token);
        case ThinkingResponse(:final content):
          thinking.write(content);
        case FunctionCallResponse():
          calls.add(r);
        case ParallelFunctionCallResponse(calls: final parallelCalls):
          calls.addAll(parallelCalls);
      }
    }
    return chatMessageFromParts(
      text: text.toString(),
      thinking: thinking.toString(),
      calls: calls,
    );
  }

  /// Wrap the generate stream, mapping each event to a ChatMessage and holding
  /// the chat mutex until a terminal event (done/error/cancel).
  ///
  /// The lock is owned by `onListen` (the flow that acquired it). `onCancel`
  /// only *signals* cancellation and tears down when generation is actually
  /// running; while we are still queued on `acquire()` or inside `stage()`,
  /// `onListen` releases when it observes the flag. `release()` is guarded on
  /// `lockHeld` so it can never free a lock this invocation doesn't hold — the
  /// `package:mutex` mutex is ownership-blind, so an unguarded release from
  /// `onCancel` could otherwise free another turn's critical section.
  Stream<ChatMessage> _lockedStream(Future<void> Function() stage) {
    late final StreamController<ChatMessage> controller;
    StreamSubscription<ModelResponse>? sub;
    var released = false;
    var cancelled = false;
    var lockHeld = false; // true once THIS invocation's acquire() has resolved
    var generating = false; // true once the generate subscription is attached

    void release() {
      if (!released && lockHeld) {
        released = true;
        genaiLock.release();
      }
    }

    Future<void> stopSafely() async {
      try {
        await stopGeneration();
      } catch (e, s) {
        gemmaLog(
          'WARNING: genai stopGeneration during teardown failed: $e\n$s',
        );
      }
    }

    controller = StreamController<ChatMessage>(
      onListen: () async {
        await genaiLock.acquire();
        lockHeld = true;
        // Cancelled while queued on acquire(): we now own the lock — release it
        // and bail without staging or generating.
        if (cancelled) {
          release();
          await controller.close();
          return;
        }
        try {
          await stage();
          // Cancelled during stage(): we still hold the lock (onCancel does not
          // release while onListen owns it) and stage() has finished mutating
          // shared state, so releasing here can't let a second turn interleave.
          // No generation started, so nothing to stop.
          if (cancelled) {
            release();
            await controller.close();
            return;
          }
          generating = true;
          sub = generateChatResponseAsync().listen(
            (r) {
              // A throw in the mapping would escape to the Zone and never
              // release the lock — funnel it into the same cleanup.
              try {
                controller.add(chatMessageFromChunk(r));
              } catch (e, s) {
                controller.addError(e, s);
                sub?.cancel();
                stopSafely().whenComplete(() {
                  release();
                  controller.close();
                });
              }
            },
            onError: (Object e, StackTrace s) async {
              controller.addError(e, s);
              await sub?.cancel();
              await stopSafely();
              release();
              await controller.close();
            },
            onDone: () {
              release();
              controller.close();
            },
          );
        } catch (e, s) {
          controller.addError(e, s);
          release();
          await controller.close();
        }
      },
      onCancel: () async {
        cancelled = true;
        // Only tear down here once generation is running. While queued on
        // acquire() or inside stage(), onListen owns the lock and releases it
        // when it sees `cancelled`; releasing here would free a lock we don't
        // hold yet, or free it mid-stage and let a second turn interleave.
        if (generating) {
          await sub?.cancel();
          await stopSafely();
          release();
        }
      },
    );
    return controller.stream;
  }
}
