import 'dart:async';

import 'package:genai_primitives/genai_primitives.dart';
import 'package:http/http.dart' as http;

import '../chat.dart';
import '../model_response.dart';
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
  Stream<ChatMessage> _lockedStream(Future<void> Function() stage) {
    late StreamController<ChatMessage> controller;
    StreamSubscription<ModelResponse>? sub;
    var released = false;
    void release() {
      if (!released) {
        released = true;
        genaiLock.release();
      }
    }

    controller = StreamController<ChatMessage>(
      onListen: () async {
        await genaiLock.acquire();
        try {
          await stage();
          sub = generateChatResponseAsync().listen(
            (r) => controller.add(chatMessageFromChunk(r)),
            onError: (Object e, StackTrace s) {
              controller.addError(e, s);
              release();
              controller.close();
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
        await sub?.cancel();
        try {
          await stopGeneration();
        } finally {
          release();
        }
      },
    );
    return controller.stream;
  }
}
