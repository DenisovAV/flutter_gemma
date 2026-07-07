import 'dart:convert';
import 'dart:typed_data';

import 'package:genai_primitives/genai_primitives.dart';
import 'package:http/http.dart' as http;

import '../message.dart';
import 'link_reader.dart';

/// Converts a genai_primitives [ChatMessage] into flutter_gemma [Message]s.
///
/// One ChatMessage may yield >1 Message (tool results become sibling messages).
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

  final textBuffer = StringBuffer();
  final images = <Uint8List>[];
  Uint8List? audio;
  final messages = <Message>[];

  for (final part in parts) {
    switch (part) {
      case TextPart(:final text):
        textBuffer.write(text);
      case DataPart(:final bytes, :final mimeType):
        _routeMedia(bytes, mimeType, images, () => audio, (v) => audio = v);
      case LinkPart(:final url, :final mimeType):
        final bytes = await readLinkBytes(url, httpClient: httpClient);
        _routeMedia(bytes, mimeType, images, () => audio, (v) => audio = v);
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
      case ThinkingPart():
        throw UnsupportedError(
          'ThinkingPart is model output (streamed), not input.',
        );
    }
  }

  final hasText = textBuffer.isNotEmpty;
  if (hasText || images.isNotEmpty || audio != null) {
    messages.insert(
      0,
      Message(
        text: textBuffer.toString(),
        isUser: isUser,
        images: images,
        imageBytes: images.isNotEmpty ? images.first : null,
        audioBytes: audio,
      ),
    );
  }
  return messages;
}

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

void _routeMedia(
  Uint8List bytes,
  String? mimeType,
  List<Uint8List> images,
  Uint8List? Function() getAudio,
  void Function(Uint8List) setAudio,
) {
  final mime = mimeType ?? '';
  if (mime.startsWith('image/')) {
    images.add(bytes);
  } else if (mime.startsWith('audio/')) {
    if (getAudio() != null) {
      throw UnsupportedError('Only one audio part per message is supported.');
    }
    setAudio(bytes);
  } else {
    throw UnsupportedError('Unsupported DataPart mime "$mime".');
  }
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
