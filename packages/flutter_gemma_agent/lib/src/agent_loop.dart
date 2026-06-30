import 'package:flutter_gemma/flutter_gemma.dart'
    show
        FunctionCallResponse,
        InferenceChat,
        Message,
        ModelResponse,
        ParallelFunctionCallResponse,
        TextResponse,
        ThinkingResponse;

import 'agent_event.dart';
import 'agent_tools.dart';
import 'skill.dart';
import 'skill_executor.dart';
import 'skill_registry.dart';
import 'skill_result.dart';
import 'secret_store.dart';

/// Orchestrates the agent turn over flutter_gemma's existing function-calling.
///
/// Given an [InferenceChat] created with the [agentTools] (and the skill
/// discovery list injected into its system prompt) plus the [registry] of
/// selected skills and the registered [executors], [run] drives the loop:
///
/// 1. `generateChatResponse()`.
/// 2. If the response is a [FunctionCallResponse] **or**
///    [ParallelFunctionCallResponse], dispatch every call:
///    - `loadSkill` → return the skill's full SKILL.md instructions (lazy
///      second-stage discovery) from the [registry];
///    - `runSkill` / `runIntent` / `runMcp` → pick the first [SkillExecutor]
///      whose `canExecute` is true (highest [SkillExecutor.priority] wins) and
///      execute it.
///    Each call's result is fed back to the chat via [InferenceChat.addQueryChunk]
///    with a tool-response [Message], then the loop continues.
/// 3. Stop on a plain [TextResponse] (emit [DoneEvent]) or when [maxIterations]
///    is reached (emit [MaxIterationsEvent]).
///
/// [run] is a `Stream<AgentEvent>` so the UI can show progress + inline
/// image / webview / widget results as the turn unfolds.
class AgentLoop {
  AgentLoop({
    required this.registry,
    required this.executors,
    SecretStore? secretStore,
    this.maxIterations = 10,
  }) : secretStore = secretStore ?? SecretStore(),
       _executors = _sortedByPriority(executors);

  /// The selected-skills catalog (discovery + `loadSkill` lookup).
  final SkillRegistry registry;

  /// Registered executors, as supplied. Probed in [_executors] order.
  final List<SkillExecutor> executors;

  /// Runtime secrets for `require-secret` skills, injected into the executor —
  /// never into the prompt.
  final SecretStore secretStore;

  /// Hard guard against a runaway tool loop. The loop makes at most this many
  /// model generations before bailing with a [MaxIterationsEvent].
  final int maxIterations;

  /// [executors] sorted into probe order (descending priority, then registration
  /// order) — the same ordering rule as the engine/embedding registries.
  final List<SkillExecutor> _executors;

  static List<SkillExecutor> _sortedByPriority(List<SkillExecutor> executors) {
    final indexed = executors.indexed.toList()
      ..sort((a, b) {
        final byPriority = b.$2.priority.compareTo(a.$2.priority);
        if (byPriority != 0) return byPriority;
        return a.$1.compareTo(b.$1); // stable: earlier-registered wins ties
      });
    return [for (final e in indexed) e.$2];
  }

  /// Drive one agent turn for [userMessage] against [chat], emitting progress
  /// [AgentEvent]s. The [chat] must already have been created with [agentTools]
  /// and the skill discovery injected into its system prompt.
  Stream<AgentEvent> run(InferenceChat chat, String userMessage) async* {
    await chat.addQueryChunk(Message(text: userMessage, isUser: true));

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final ModelResponse response = await chat.generateChatResponse();

      final calls = _extractCalls(response);
      if (calls.isEmpty) {
        // Plain text (or thinking) — the model is done with this turn.
        final text = switch (response) {
          TextResponse(:final token) => token,
          ThinkingResponse(:final content) => content,
          _ => '',
        };
        if (text.isNotEmpty) yield TextChunkEvent(text);
        yield DoneEvent(text);
        return;
      }

      // Dispatch every call (single or parallel), feeding each result back.
      for (final call in calls) {
        yield* _dispatch(chat, call);
      }
    }

    yield MaxIterationsEvent(maxIterations);
  }

  /// Normalize a [ModelResponse] into the list of function calls to dispatch.
  /// Returns an empty list for a plain text / thinking response.
  List<FunctionCallResponse> _extractCalls(ModelResponse response) {
    return switch (response) {
      FunctionCallResponse() => [response],
      ParallelFunctionCallResponse(:final calls) => calls,
      _ => const [],
    };
  }

  /// Execute one [call] and feed its result back to [chat], emitting the
  /// matching progress events.
  Stream<AgentEvent> _dispatch(
    InferenceChat chat,
    FunctionCallResponse call,
  ) async* {
    switch (call.name) {
      case AgentToolNames.loadSkill:
        yield* _loadSkill(chat, call);
      case AgentToolNames.runSkill:
      case AgentToolNames.runIntent:
      case AgentToolNames.runMcp:
        yield* _runExecutor(chat, call);
      default:
        // Unknown tool — feed an error back so the model can correct itself.
        final message = 'Unknown tool "${call.name}".';
        yield AgentErrorEvent(message, toolName: call.name);
        await _feedBack(chat, call.name, {
          'error': message,
          'status': 'failed',
        });
    }
  }

  /// `loadSkill(skillName)` — return the full SKILL.md instructions (lazy
  /// second-stage discovery). Feeds the instructions back as the tool response.
  Stream<AgentEvent> _loadSkill(
    InferenceChat chat,
    FunctionCallResponse call,
  ) async* {
    final skillName = _stringArg(call.args, 'skillName').trim();
    final skill = registry.get(skillName);

    yield SkillLoadEvent(skillName, found: skill != null);

    if (skill == null) {
      // Mirror the unknown-tool path: surface a real error event and a
      // `status: failed` marker, rather than feeding "Skill not found" into the
      // same `skill_instructions` field real instructions occupy (which the
      // model would read as content and could act on as if a skill loaded).
      final message = 'Skill "$skillName" not found.';
      yield AgentErrorEvent(message, toolName: call.name);
      await _feedBack(chat, call.name, {
        'skill_name': skillName,
        'error': message,
        'status': 'failed',
      });
      return;
    }

    await _feedBack(chat, call.name, {
      'skill_name': skillName,
      'skill_instructions': _skillContent(skill),
    });
  }

  /// `runSkill` / `runIntent` / `runMcp` — pick an executor by probe-chain and
  /// run it, feeding the structured result back to the model.
  Stream<AgentEvent> _runExecutor(
    InferenceChat chat,
    FunctionCallResponse call,
  ) async* {
    // Resolve the targeted skill (skill-based calls carry a `skillName`; intent
    // and MCP calls don't, so this may be null).
    final skillName = _stringArg(call.args, 'skillName').trim();
    final skill = skillName.isEmpty ? null : registry.get(skillName);

    yield ToolCallEvent(toolName: call.name, args: call.args, skill: skill);

    // Map the tool call to the (data) payload + skill the executor expects.
    final probe = skill ?? _syntheticSkillFor(call);
    final executor = _pickExecutor(probe);
    if (executor == null) {
      const status = 'failed';
      final message = 'No executor available for "${call.name}".';
      yield AgentErrorEvent(message, toolName: call.name);
      await _feedBack(chat, call.name, {'error': message, 'status': status});
      return;
    }

    final dataJson = _dataFor(call);
    final secret = skill != null ? secretStore.get(skill.name) : null;

    SkillResult result;
    try {
      result = await executor.execute(probe, dataJson, secret: secret);
    } catch (e) {
      result = ErrorResult(e.toString());
    }

    yield ToolResultEvent(toolName: call.name, result: result);
    if (result is ErrorResult) {
      yield AgentErrorEvent(result.message, toolName: call.name);
    }

    await _feedBack(chat, call.name, _resultToResponse(result));
  }

  /// First executor (in probe order) that can run [skill]; null if none can.
  SkillExecutor? _pickExecutor(Skill skill) {
    for (final executor in _executors) {
      if (executor.canExecuteSkill(skill)) return executor;
    }
    return null;
  }

  /// Build a stand-in [Skill] for an intent / MCP call that does not target a
  /// registered skill, so executors can still probe by [SkillType]. The
  /// synthetic skill's name carries the concrete action — the `intent` arg for
  /// `runIntent`, the `toolName` arg for `runMcp` — so the executor can resolve
  /// which whitelisted action to run from [Skill.name].
  Skill _syntheticSkillFor(FunctionCallResponse call) {
    final (type, nameArg) = switch (call.name) {
      AgentToolNames.runIntent => (SkillType.intent, 'intent'),
      AgentToolNames.runMcp => (SkillType.mcp, 'toolName'),
      _ => (SkillType.js, 'toolName'),
    };
    final resolved = _stringArg(call.args, nameArg).trim();
    return Skill(
      name: resolved.isNotEmpty ? resolved : call.name,
      description: '',
      instructions: '',
      type: type,
    );
  }

  /// The `data` payload to hand the executor. For `runSkill` it's the JS `data`
  /// arg; for `runIntent` it's the `parameters` JSON; for `runMcp` it's `input`.
  String _dataFor(FunctionCallResponse call) {
    return switch (call.name) {
      AgentToolNames.runIntent => _stringArg(call.args, 'parameters'),
      AgentToolNames.runMcp => _stringArg(call.args, 'input'),
      _ => _stringArg(call.args, 'data'),
    };
  }

  /// Convert a [SkillResult] into the `{result | image | webview | error}`-shaped
  /// map fed back to the model (mirrors Gallery's tool-response shapes).
  Map<String, dynamic> _resultToResponse(SkillResult result) {
    return switch (result) {
      TextResult(:final text) => {'result': text, 'status': 'succeeded'},
      ImageResult() => {
        'result': 'An image was produced and shown to the user.',
        'status': 'succeeded',
      },
      WidgetResult() => {
        'result': 'A widget was produced and shown to the user.',
        'status': 'succeeded',
      },
      WebviewResult(:final url) => {
        'result': 'A web view was opened for the user.',
        'webview': url,
        'status': 'succeeded',
      },
      ErrorResult(:final message) => {'error': message, 'status': 'failed'},
    };
  }

  /// Feed a tool response back into the chat as a tool-response [Message].
  Future<void> _feedBack(
    InferenceChat chat,
    String toolName,
    Map<String, dynamic> response,
  ) {
    return chat.addQueryChunk(
      Message.toolResponse(toolName: toolName, response: response),
    );
  }

  /// The Gallery `SKILL_INSTRUCTIONS_TEMPLATE` content `loadSkill` returns.
  String _skillContent(Skill skill) =>
      '---\nname: ${skill.name}\ndescription: ${skill.description}\n---\n\n'
      '${skill.instructions}';

  /// Read a string tool argument, tolerating a missing key or non-string value.
  String _stringArg(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return '';
    return value is String ? value : value.toString();
  }
}
