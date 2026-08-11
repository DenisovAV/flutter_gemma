import 'package:flutter_gemma_agent/flutter_gemma_agent.dart'
    show AgentEvent, AgentSession, DoneEvent, MaxIterationsEvent;
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart'
    show VoiceResponder;

const _kFallback = "Sorry, I couldn't finish that.";

/// Map an agent event stream to spoken text: speak only the final answer
/// ([DoneEvent]); substitute [fallback] for a [MaxIterationsEvent]; ignore
/// tool/skill progress events (a UI would show those separately).
///
/// Exposed (not private) so `agent_voice_responder_test.dart` can drive it
/// directly with a fake [AgentEvent] stream, without building a real
/// [AgentSession]. Not annotated `@visibleForTesting` to avoid adding a
/// `meta` dependency to the example package for this alone.
Stream<String> agentEventsToSpeech(
  Stream<AgentEvent> events, {
  String fallback = _kFallback,
}) async* {
  await for (final e in events) {
    if (e is DoneEvent) {
      if (e.text.isNotEmpty) yield e.text;
    } else if (e is MaxIterationsEvent) {
      yield fallback;
    }
  }
}

/// A [VoiceResponder] backed by the full agent (skills / MCP / tools). Drop it
/// into `VoiceSession.custom(responder: ...)`. Lives in the app, not in
/// flutter_gemma_speech, so speech never depends on flutter_gemma_agent.
VoiceResponder agentVoiceResponder(
  AgentSession agent, {
  String maxIterationsFallback = _kFallback,
}) {
  var cancelled = false;
  return VoiceResponder(
    respond: (userText) {
      cancelled = false;
      // isCancelled (flutter_gemma_agent 0.2.0, Task 3a) makes barge-in halt
      // the agent loop before the next tool, not just mute the speech.
      return agentEventsToSpeech(
        agent.ask(userText, isCancelled: () => cancelled),
        fallback: maxIterationsFallback,
      );
    },
    stop: () async {
      cancelled = true;
      await agent.chat.stopGeneration();
    },
  );
}
