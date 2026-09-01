import 'dart:async';

import 'package:genkit/genkit.dart';

import 'attempts.dart';

/// Runs [branches] in [order], escalating to the next branch when a successful
/// response is rejected by [accept] (or when a branch fails transiently). The
/// last branch's successful response is returned regardless of [accept]. Use it
/// for "try the cheap on-device model; escalate to cloud if the answer isn't
/// good enough" — [accept] is any predicate the caller wants (length, a regex,
/// a JSON-parses check). Transient/permanent error handling matches
/// `hybridModel` (both share one internal runner).
///
/// `accept` may be async (an LLM-as-judge); a sync predicate still works.
///
/// **NON-STREAMING in v1.** A quality verdict needs the full response, and a
/// streamed response cannot be un-sent. For a streaming request this runs the
/// attempts non-streamed and emits the accepted response as a SINGLE chunk —
/// a streaming UI will see no intermediate tokens and sits idle for one or two
/// full sequential model runs. (Streaming the accepted branch after a buffered
/// verdict is a non-breaking follow-up.)
Model cascadeModel({
  required Map<String, Model> branches,
  required List<String> order,
  required FutureOr<bool> Function(ModelResponse) accept,
  String name = 'cascade',
}) {
  if (branches.isEmpty) {
    throw ArgumentError.value(branches, 'branches', 'must not be empty');
  }
  if (order.isEmpty) {
    throw ArgumentError.value(order, 'order', 'must not be empty');
  }
  for (final k in order) {
    if (!branches.containsKey(k)) {
      throw ArgumentError.value(
        order,
        'order',
        'unknown branch key "$k"; have ${branches.keys.join(', ')}',
      );
    }
  }
  final frozen = Map<String, Model>.unmodifiable(branches);
  return Model(
    name: name,
    fn: (request, context) async {
      // Always run non-streamed (the verdict needs the full response).
      final blocking = (
        streamingRequested: false,
        sendChunk: (ModelResponseChunk _) {},
        context: context.context,
        inputStream: context.inputStream,
        init: null,
      );
      final resp = await runInOrder(
        order,
        frozen,
        request,
        blocking,
        accept: accept,
      );
      // Streaming caller: emit the accepted response as one final chunk.
      if (context.streamingRequested) {
        context.sendChunk(
          ModelResponseChunk(
            role: Role.model,
            content: resp.message?.content ?? const [],
          ),
        );
      }
      return resp;
    },
  );
}
