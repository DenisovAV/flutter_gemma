import 'dart:convert';
import 'dart:typed_data';

import 'package:genai_primitives/genai_primitives.dart';
import 'package:http/http.dart' as http;

import '../message.dart';
import 'link_reader.dart';

/// Converts a genai_primitives [ChatMessage] into flutter_gemma [Message]s.
///
/// One ChatMessage may yield >1 Message (tool results become sibling messages).
/// The text/media parts collapse into a single [Message] emitted FIRST, then
/// one sibling [Message] per tool result in part order. A [ThinkingPart] is
/// stripped (thoughts aren't fed back as history).
/// Async because LinkPart resolution may need I/O. Throws — never silently drops.
Future<List<Message>> messagesFromChatMessage(
  ChatMessage message, {
  http.Client? httpClient,
}) async {
  if (message.role == ChatMessageRole.system) {
    throw ArgumentError(
      'System messages are not input — set them via createChat(systemInstruction:).',
    );
  }
  final parts = message.parts;
  if (parts.isEmpty) {
    throw ArgumentError('ChatMessage has no parts.');
  }
  final isUser = message.role == ChatMessageRole.user;

  final images = <Uint8List>[];
  Uint8List? audio;
  final messages = <Message>[];

  for (final part in parts) {
    switch (part) {
      case DataPart(:final bytes, :final mimeType):
        audio = _routeMedia(bytes, mimeType, images, audio);
      case LinkPart(:final url, :final mimeType):
        final bytes = await readLinkBytes(url, httpClient: httpClient);
        audio = _routeMedia(bytes, mimeType, images, audio);
      case ToolPart(kind: ToolPartKind.result, :final toolName, :final result):
        final resp = result is Map<String, dynamic>
            ? result
            : {'result': result};
        messages.add(Message.toolResponse(toolName: toolName, response: resp));
      case ToolPart(kind: ToolPartKind.call, :final toolName, :final arguments):
        if (isUser) {
          throw UnsupportedError(
            'A tool call is model output, not user input.',
          );
        }
        messages.add(
          Message.toolCall(
            text: jsonEncode({'name': toolName, 'parameters': arguments ?? {}}),
          ),
        );
      case TextPart():
      case ThinkingPart():
      // TextPart text is read from `message.text` after the loop. A ThinkingPart
      // is stripped from history: Gemma re-feeds the answer, not the reasoning
      // (see the thinking docs' thought-stripping), and a model turn returned by
      // the output converter carries its ThinkingPart, so dropping it here lets
      // that turn round-trip back in as history. Both are no-ops in this loop.
    }
  }

  final text = message.text;
  if (text.isNotEmpty || images.isNotEmpty || audio != null) {
    messages.insert(
      0,
      Message(
        text: text,
        isUser: isUser,
        images: images,
        imageBytes: images.isNotEmpty ? images.first : null,
        audioBytes: audio,
      ),
    );
  }
  return messages;
}

/// Converts a list of [ChatMessage]s to flutter_gemma [Message]s in order,
/// concatenating each message's expansion (see [messagesFromChatMessage]).
Future<List<Message>> messagesFromChatMessages(
  List<ChatMessage> messages, {
  http.Client? httpClient,
}) async {
  final out = <Message>[];
  for (final m in messages) {
    out.addAll(await messagesFromChatMessage(m, httpClient: httpClient));
  }
  return out;
}

/// Adds an image part to [images], or returns audio bytes as the message audio.
/// Returns the audio value the caller should keep: [current] for an image,
/// the new bytes for an audio part. Throws on a second audio or a non-media mime.
Uint8List? _routeMedia(
  Uint8List bytes,
  String? mimeType,
  List<Uint8List> images,
  Uint8List? current,
) {
  final mime = mimeType ?? '';
  if (mime.startsWith('image/')) {
    images.add(bytes);
    return current;
  }
  if (mime.startsWith('audio/')) {
    if (current != null) {
      throw UnsupportedError('Only one audio part per message is supported.');
    }
    return bytes;
  }
  throw UnsupportedError('Unsupported DataPart mime "$mime".');
}

/// Throws if any message needs a capability the chat wasn't built with,
/// so the engine never silently drops image/audio/tool content.
void assertMessagesFitChat(
  List<Message> messages, {
  required bool supportImage,
  required bool supportAudio,
  required bool supportsFunctionCalls,
}) {
  for (final m in messages) {
    if (m.hasImage && !supportImage) {
      throw UnsupportedError(
        'This chat was created without image support; recreate it with a vision model.',
      );
    }
    if (m.hasAudio && !supportAudio) {
      throw UnsupportedError(
        'This chat was created without audio support; recreate it with an audio model.',
      );
    }
    if ((m.type == MessageType.toolResponse ||
            m.type == MessageType.toolCall) &&
        !supportsFunctionCalls) {
      throw UnsupportedError(
        'This chat was created without function-call support (tools were not passed to createChat).',
      );
    }
  }
}
