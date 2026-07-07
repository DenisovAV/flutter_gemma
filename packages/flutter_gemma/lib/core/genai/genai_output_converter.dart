import 'package:genai_primitives/genai_primitives.dart';

import '../model_response.dart';

/// One streamed [ModelResponse] variant → one single-part model [ChatMessage].
ChatMessage chatMessageFromChunk(ModelResponse chunk) {
  final parts = <StandardPart>[];
  switch (chunk) {
    case TextResponse(:final token):
      parts.add(TextPart(token));
    case ThinkingResponse(:final content):
      parts.add(ThinkingPart(content));
    case FunctionCallResponse(:final name, :final args):
      parts.add(ToolPart.call(callId: name, toolName: name, arguments: args));
    case ParallelFunctionCallResponse(:final calls):
      for (final c in calls) {
        parts.add(
          ToolPart.call(callId: c.name, toolName: c.name, arguments: c.args),
        );
      }
  }
  return ChatMessage(role: ChatMessageRole.model, parts: parts);
}

/// Coalesce a whole model turn into one [ChatMessage].
/// Order: ThinkingPart → (ToolPart.call… OR TextPart). Tool calls suppress text.
ChatMessage chatMessageFromParts({
  String? text,
  List<FunctionCallResponse> calls = const [],
  String? thinking,
  Map<String, Object?> metadata = const {},
}) {
  final parts = <StandardPart>[];
  if (thinking != null && thinking.isNotEmpty) {
    parts.add(ThinkingPart(thinking));
  }
  if (calls.isNotEmpty) {
    for (final c in calls) {
      parts.add(
        ToolPart.call(callId: c.name, toolName: c.name, arguments: c.args),
      );
    }
  } else if (text != null && text.isNotEmpty) {
    parts.add(TextPart(text));
  }
  return ChatMessage(
    role: ChatMessageRole.model,
    parts: parts,
    metadata: metadata,
  );
}
