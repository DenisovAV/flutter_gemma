import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart';

/// A fake Model whose behavior is controlled by callbacks.
///
/// [onCall] records each invocation. [text] is returned for blocking calls.
/// [chunks] are streamed via context.sendChunk before resolving.
/// If [throwBeforeToken] is true, the model throws immediately (no chunk).
/// If [throwAfterToken] is true, it sends the first chunk then throws.
Model fakeModel({
  required String name,
  String text = 'ok',
  List<String> chunks = const [],
  bool throwBeforeToken = false,
  bool throwAfterToken = false,
  void Function()? onCall,
}) {
  return Model(
    name: name,
    fn: (request, context) async {
      onCall?.call();
      if (throwBeforeToken) {
        throw StateError('fail-before-token:$name');
      }
      if (context.streamingRequested) {
        for (final c in chunks) {
          context.sendChunk(
            ModelResponseChunk(
              role: Role.model,
              content: [TextPart(text: c)],
            ),
          );
          if (throwAfterToken) {
            throw StateError('fail-after-token:$name');
          }
        }
      }
      return ModelResponse(
        finishReason: FinishReason.stop,
        message: Message(role: Role.model, content: [TextPart(text: text)]),
      );
    },
  );
}
