import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart'
    show
        FunctionCallResponse,
        InferenceChat,
        Message,
        MessageType,
        ModelResponse,
        ParallelFunctionCallResponse,
        TextResponse;
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scriptable fake [InferenceChat]: returns the next queued [ModelResponse]
/// per [generateChatResponse] call and records every [addQueryChunk] message
/// (so a test can assert what was fed back to the model). Subclasses the real
/// [InferenceChat] (mirrors the genkit `FakeInferenceChat` pattern) so no real
/// session is created.
class _FakeAgentChat extends InferenceChat {
  _FakeAgentChat(this._responses)
    : super(sessionCreator: null, maxTokens: 1024);

  final List<ModelResponse> _responses;
  int _index = 0;

  /// Every message fed back into the chat (user message + tool responses).
  final List<Message> received = [];

  int generateCallCount = 0;

  @override
  Future<void> initSession() async {}

  @override
  Future<void> addQueryChunk(
    Message message, [
    bool noTool = false,
    bool prefix = false,
  ]) async {
    received.add(message);
  }

  @override
  Future<ModelResponse> generateChatResponse() async {
    generateCallCount++;
    if (_index >= _responses.length) {
      // Default terminal: a plain text answer, so an over-eager loop still ends.
      return const TextResponse('done');
    }
    return _responses[_index++];
  }

  @override
  Future<void> close() async {}

  /// The tool-response messages fed back (excludes the initial user message).
  List<Message> get toolResponses =>
      received.where((m) => m.type == MessageType.toolResponse).toList();
}

/// A fake executor that handles a single [SkillType] and returns a preset
/// [SkillResult], recording every call.
class _FakeExecutor extends SkillExecutor {
  _FakeExecutor(
    this._type, {
    SkillResult? result,
    this.priority = 0,
    this.name = 'fake',
  }) : _result = result ?? const TextResult('ok');

  final SkillType _type;
  final SkillResult _result;

  @override
  final String name;

  @override
  final int priority;

  final List<({Skill skill, String dataJson, String? secret})> calls = [];

  @override
  bool canExecuteSkill(Skill skill) => skill.type == _type;

  @override
  Future<SkillResult> execute(
    Skill skill,
    String dataJson, {
    String? secret,
  }) async {
    calls.add((skill: skill, dataJson: dataJson, secret: secret));
    return _result;
  }
}

Skill _jsSkill({String name = 'calculate-hash'}) => Skill(
  name: name,
  description: 'Calculate the hash of a given text.',
  instructions: 'Call the `run_js` tool with script name index.html.',
  type: SkillType.js,
);

FunctionCallResponse _loadSkill(String name) =>
    FunctionCallResponse(name: 'loadSkill', args: {'skillName': name});

FunctionCallResponse _runSkill(String name, {String data = '{}'}) =>
    FunctionCallResponse(
      name: 'runSkill',
      args: {'skillName': name, 'scriptName': 'index.html', 'data': data},
    );

void main() {
  group('AgentLoop — happy path', () {
    test(
      'dispatches loadSkill then runSkill, feeds both back, ends on text',
      () async {
        final registry = SkillRegistry()..add(_jsSkill(), selected: true);
        final executor = _FakeExecutor(
          SkillType.js,
          result: const TextResult('hash=abc123'),
        );
        final chat = _FakeAgentChat([
          _loadSkill('calculate-hash'),
          _runSkill('calculate-hash', data: '{"text":"hi"}'),
          const TextResponse('The hash is abc123.'),
        ]);

        final loop = AgentLoop(registry: registry, executors: [executor]);
        final events = await loop.run(chat, 'hash of hi').toList();

        // Event sequence: SkillLoad -> ToolCall -> ToolResult -> Text -> Done.
        expect(events[0], isA<SkillLoadEvent>());
        expect((events[0] as SkillLoadEvent).found, isTrue);
        expect(events[1], isA<ToolCallEvent>());
        expect((events[1] as ToolCallEvent).toolName, 'runSkill');
        // The event's args are an unmodifiable view of the loop's parsed args.
        expect(
          () => (events[1] as ToolCallEvent).args['x'] = 1,
          throwsUnsupportedError,
        );
        expect(events[2], isA<ToolResultEvent>());
        expect(events.whereType<DoneEvent>().single.text, contains('abc123'));

        // The executor ran once with the model-supplied data + targeted skill.
        expect(executor.calls, hasLength(1));
        expect(executor.calls.single.dataJson, '{"text":"hi"}');
        expect(executor.calls.single.skill.name, 'calculate-hash');

        // Three generations: loadSkill, runSkill, final text.
        expect(chat.generateCallCount, 3);

        // Both tool calls got a tool-response fed back.
        final fed = chat.toolResponses;
        expect(fed, hasLength(2));
        expect(fed[0].toolName, 'loadSkill');
        expect(fed[0].text, contains('run_js')); // full instructions returned
        expect(fed[1].toolName, 'runSkill');
        expect(fed[1].text, contains('hash=abc123'));
      },
    );

    test('first message fed to chat is the user message', () async {
      final registry = SkillRegistry();
      final chat = _FakeAgentChat([const TextResponse('hi there')]);
      final loop = AgentLoop(registry: registry, executors: const []);

      await loop.run(chat, 'hello').toList();

      expect(chat.received.first.isUser, isTrue);
      expect(chat.received.first.text, 'hello');
    });
  });

  group('AgentLoop — termination', () {
    test('terminates on a plain text response (no tools)', () async {
      final registry = SkillRegistry();
      final chat = _FakeAgentChat([const TextResponse('just chatting')]);
      final loop = AgentLoop(registry: registry, executors: const []);

      final events = await loop.run(chat, 'hey').toList();

      expect(events.last, isA<DoneEvent>());
      expect((events.last as DoneEvent).text, 'just chatting');
      expect(chat.generateCallCount, 1);
    });

    test('respects maxIterations on a runaway tool loop', () async {
      final registry = SkillRegistry()..add(_jsSkill(), selected: true);
      final executor = _FakeExecutor(SkillType.js);
      // The model keeps calling runSkill forever — never a text answer.
      final chat = _FakeAgentChat(
        List.generate(50, (_) => _runSkill('calculate-hash')),
      );

      final loop = AgentLoop(
        registry: registry,
        executors: [executor],
        maxIterations: 4,
      );
      final events = await loop.run(chat, 'spin').toList();

      expect(events.last, isA<MaxIterationsEvent>());
      expect((events.last as MaxIterationsEvent).iterations, 4);
      // Exactly maxIterations generations, no more.
      expect(chat.generateCallCount, 4);
    });
  });

  group('AgentLoop — parallel calls', () {
    test(
      'handles a ParallelFunctionCallResponse: dispatches every call',
      () async {
        final registry = SkillRegistry()
          ..add(_jsSkill(name: 'a'), selected: true)
          ..add(_jsSkill(name: 'b'), selected: true);
        final executor = _FakeExecutor(
          SkillType.js,
          result: const TextResult('done'),
        );
        final chat = _FakeAgentChat([
          ParallelFunctionCallResponse(
            calls: [
              _runSkill('a', data: '{"i":1}'),
              _runSkill('b', data: '{"i":2}'),
            ],
          ),
          const TextResponse('both done'),
        ]);

        final loop = AgentLoop(registry: registry, executors: [executor]);
        final events = await loop.run(chat, 'do both').toList();

        // Both parallel calls ran, each with its own data.
        expect(executor.calls, hasLength(2));
        expect(executor.calls[0].dataJson, '{"i":1}');
        expect(executor.calls[1].dataJson, '{"i":2}');

        // Two tool responses fed back, then the loop ends on text.
        expect(chat.toolResponses, hasLength(2));
        expect(events.whereType<ToolResultEvent>(), hasLength(2));
        expect(events.last, isA<DoneEvent>());
      },
    );
  });

  group('AgentLoop — loadSkill lookup', () {
    test(
      'unknown skill name emits an error event and feeds a failed status',
      () async {
        final registry = SkillRegistry(); // empty
        final chat = _FakeAgentChat([
          _loadSkill('nope'),
          const TextResponse('I could not find that skill.'),
        ]);

        final loop = AgentLoop(registry: registry, executors: const []);
        final events = await loop.run(chat, 'load nope').toList();

        final load = events.whereType<SkillLoadEvent>().single;
        expect(load.found, isFalse);
        // The miss must surface as a real error event, not be fed into the
        // skill_instructions field as if it were content.
        final error = events.whereType<AgentErrorEvent>().single;
        expect(error.message, contains('not found'));
        final fed = chat.toolResponses.single;
        expect(fed.toolName, 'loadSkill');
        expect(fed.text, contains('failed'));
        expect(fed.text, contains('not found'));
        // Must NOT be fed as if it were real instructions.
        expect(fed.text, isNot(contains('skill_instructions')));
        expect(events.last, isA<DoneEvent>());
      },
    );
  });

  group('AgentLoop — executor selection', () {
    test(
      'no executor for the call feeds an error back and continues',
      () async {
        final registry = SkillRegistry()..add(_jsSkill(), selected: true);
        // Only an intent executor registered — cannot handle a JS skill.
        final intentExecutor = _FakeExecutor(SkillType.intent);
        final chat = _FakeAgentChat([
          _runSkill('calculate-hash'),
          const TextResponse('sorry, cannot run that'),
        ]);

        final loop = AgentLoop(registry: registry, executors: [intentExecutor]);
        final events = await loop.run(chat, 'run it').toList();

        expect(intentExecutor.calls, isEmpty);
        expect(events.whereType<AgentErrorEvent>(), isNotEmpty);
        final fed = chat.toolResponses.single;
        expect(fed.text, contains('No executor available'));
        expect(events.last, isA<DoneEvent>());
      },
    );

    test('higher-priority executor wins the probe-chain', () async {
      final registry = SkillRegistry()..add(_jsSkill(), selected: true);
      final low = _FakeExecutor(
        SkillType.js,
        result: const TextResult('low'),
        name: 'low',
      );
      final high = _FakeExecutor(
        SkillType.js,
        result: const TextResult('high'),
        priority: 10,
        name: 'high',
      );
      final chat = _FakeAgentChat([
        _runSkill('calculate-hash'),
        const TextResponse('ok'),
      ]);

      // Registered low-first; high must still win on priority.
      final loop = AgentLoop(registry: registry, executors: [low, high]);
      await loop.run(chat, 'go').toList();

      expect(high.calls, hasLength(1));
      expect(low.calls, isEmpty);
      expect(chat.toolResponses.single.text, contains('high'));
    });
  });

  group('AgentLoop — direct skill-name call guard', () {
    // Small models (esp. on the web decoder) sometimes call a skill by name as
    // if it were a tool — e.g. `calculate-hash{text:...}` — instead of the
    // two-stage `loadSkill` then `run_js`. That skips the skill's instructions
    // (which say WHICH executor to use), so we must NOT run it directly. Mirror
    // Gallery's `guardMissingEntityWithSkillFallback`: when the unknown tool is
    // a known skill, feed back a hint that steers the model to loadSkill.
    test(
      'calling a known skill directly hints the model to load it as a skill',
      () async {
        final registry = SkillRegistry()..add(_jsSkill(), selected: true);
        final chat = _FakeAgentChat([
          const FunctionCallResponse(
            name: 'calculate-hash',
            args: {'text': 'hello'},
          ),
          const TextResponse('ok'),
        ]);

        final loop = AgentLoop(registry: registry, executors: const []);
        final events = await loop.run(chat, 'hash hello').toList();

        // Must NOT execute directly (contract stays two-stage).
        final error = events.whereType<AgentErrorEvent>().single;
        expect(error.toolName, 'calculate-hash');
        final fed = chat.toolResponses.single;
        expect(fed.text, contains('failed'));
        // The hint must name loadSkill so the model can self-correct.
        expect(fed.text, contains('loadSkill'));
        expect(fed.text, contains('calculate-hash'));
        expect(events.last, isA<DoneEvent>());
      },
    );

    test(
      'an unknown tool that is NOT a skill just reports unknown tool',
      () async {
        final registry = SkillRegistry()..add(_jsSkill(), selected: true);
        final chat = _FakeAgentChat([
          const FunctionCallResponse(name: 'totally-made-up', args: {}),
          const TextResponse('ok'),
        ]);

        final loop = AgentLoop(registry: registry, executors: const []);
        final events = await loop.run(chat, 'do x').toList();

        final fed = chat.toolResponses.single;
        expect(fed.text, contains('failed'));
        expect(fed.text, isNot(contains('loadSkill')));
        expect(events.last, isA<DoneEvent>());
      },
    );
  });

  group('AgentLoop — SKILL.md tool-name aliases (web)', () {
    // The bundled SKILL.md files (verbatim from Gallery) tell the model to
    // "Call the `run_js` / `run_intent` tool", but the tool DECLARATIONS are
    // named runSkill / runIntent / runMcp. Native decoders take the name from
    // the structured declaration (runSkill — works); the web decoder follows
    // the SKILL.md text literally and calls `run_js`, which the switch didn't
    // know → "unknown tool run_js". Accept the SKILL.md spelling as an alias.
    test('run_js is dispatched to the JS executor (like runSkill)', () async {
      final registry = SkillRegistry()..add(_jsSkill(), selected: true);
      final executor = _FakeExecutor(
        SkillType.js,
        result: const TextResult('hash=abc123'),
      );
      final chat = _FakeAgentChat([
        _loadSkill('calculate-hash'),
        // The model uses the SKILL.md spelling `run_js`, not `runSkill`.
        const FunctionCallResponse(
          name: 'run_js',
          args: {
            'skillName': 'calculate-hash',
            'scriptName': 'index.html',
            'data': '{"text":"hi"}',
          },
        ),
        const TextResponse('The hash is abc123.'),
      ]);

      final loop = AgentLoop(registry: registry, executors: [executor]);
      final events = await loop.run(chat, 'hash of hi').toList();

      // It must run the JS executor, NOT fall through to "unknown tool".
      expect(executor.calls, hasLength(1));
      expect(executor.calls.single.dataJson, '{"text":"hi"}');
      expect(events.whereType<ToolResultEvent>(), isNotEmpty);
      expect(
        events.whereType<AgentErrorEvent>().where(
          (e) => e.message.contains('Unknown tool'),
        ),
        isEmpty,
      );
      expect(events.whereType<DoneEvent>().single.text, contains('abc123'));
    });

    test('run_intent is dispatched to the intent executor', () async {
      final registry = SkillRegistry()
        ..add(
          Skill(
            name: 'open-map',
            description: 'Open a map.',
            instructions: 'Call the `run_intent` tool.',
            type: SkillType.intent,
          ),
          selected: true,
        );
      final executor = _FakeExecutor(
        SkillType.intent,
        result: const TextResult('opened'),
      );
      final chat = _FakeAgentChat([
        _loadSkill('open-map'),
        const FunctionCallResponse(
          name: 'run_intent',
          args: {'skillName': 'open-map', 'parameters': '{}'},
        ),
        const TextResponse('done'),
      ]);

      final loop = AgentLoop(registry: registry, executors: [executor]);
      final events = await loop.run(chat, 'open map').toList();

      expect(executor.calls, hasLength(1));
      expect(
        events.whereType<AgentErrorEvent>().where(
          (e) => e.message.contains('Unknown tool'),
        ),
        isEmpty,
      );
    });
  });

  group('AgentLoop — run_js without skillName is guided, not guessed', () {
    // The web decoder loads a skill (loadSkill "calculate-hash") then calls
    // run_js WITHOUT repeating skillName in the args. We must NOT guess/execute
    // a synthetic skill named after the tool ("runSkill" → 404). Instead, feed
    // back a clear error naming skillName so the model self-corrects — the same
    // error-feedback strategy as the direct-skill-call guard.
    test(
      'run_js with no skillName feeds back a skillName hint and does not execute',
      () async {
        final registry = SkillRegistry()..add(_jsSkill(), selected: true);
        final executor = _FakeExecutor(
          SkillType.js,
          result: const TextResult('hash=abc123'),
        );
        final chat = _FakeAgentChat([
          _loadSkill('calculate-hash'),
          // run_js with NO skillName / toolName arg — just the data.
          const FunctionCallResponse(
            name: 'run_js',
            args: {'scriptName': 'index.html', 'data': '{"text":"hi"}'},
          ),
          const TextResponse('sorry, I need the skill name'),
        ]);

        final loop = AgentLoop(registry: registry, executors: [executor]);
        final events = await loop.run(chat, 'hash of hi').toList();

        // The executor must NOT run — we didn't guess a skill.
        expect(executor.calls, isEmpty);
        // A real error event hinting skillName.
        final error = events.whereType<AgentErrorEvent>().single;
        expect(error.message, contains('skillName'));
        // Two tool responses fed back: loadSkill (instructions) + the run call
        // (error). The alias already normalized run_js -> runSkill in dispatch.
        final fed = chat.toolResponses.last;
        expect(fed.toolName, 'runSkill');
        expect(fed.text, contains('failed'));
        expect(fed.text, contains('skillName'));
        // Must NOT have tried a synthetic `runSkill` asset path.
        expect(fed.text, isNot(contains('runSkill')));
        expect(events.last, isA<DoneEvent>());
      },
    );
  });

  group('AgentLoop — secrets', () {
    test(
      'require-secret skill gets its secret injected, never in the prompt',
      () async {
        final secretSkill = Skill(
          name: 'weather',
          description: 'Get weather.',
          instructions: 'Call the `run_js` tool.',
          type: SkillType.js,
          metadata: const SkillMetadata(requireSecret: true),
        );
        final registry = SkillRegistry()..add(secretSkill, selected: true);
        final executor = _FakeExecutor(SkillType.js);
        final secrets = SecretStore()..set('weather', 'sk-secret-123');
        final chat = _FakeAgentChat([
          _runSkill('weather'),
          const TextResponse('it is sunny'),
        ]);

        final loop = AgentLoop(
          registry: registry,
          executors: [executor],
          secretStore: secrets,
        );
        await loop.run(chat, 'weather?').toList();

        // Secret reached the executor...
        expect(executor.calls.single.secret, 'sk-secret-123');
        // ...but never appeared in anything sent to the model.
        for (final m in chat.received) {
          expect(m.text, isNot(contains('sk-secret-123')));
        }
      },
    );
  });

  group('AgentLoop — image / webview results', () {
    test(
      'image result surfaces an ImageResult event + non-leaky tool response',
      () async {
        final registry = SkillRegistry()..add(_jsSkill(), selected: true);
        final executor = _FakeExecutor(
          SkillType.js,
          result: ImageResult(Uint8List.fromList([1, 2, 3])),
        );
        final chat = _FakeAgentChat([
          _runSkill('calculate-hash'),
          const TextResponse('here is your image'),
        ]);

        final loop = AgentLoop(registry: registry, executors: [executor]);
        final events = await loop.run(chat, 'make an image').toList();

        final result = events.whereType<ToolResultEvent>().single.result;
        expect(result, isA<ImageResult>());
        // The fed-back text describes the image rather than dumping bytes.
        expect(chat.toolResponses.single.text, contains('image'));
      },
    );
  });

  group('AgentSession facade', () {
    test('ask() drives the loop via the wrapped chat', () async {
      final registry = SkillRegistry()..add(_jsSkill(), selected: true);
      final executor = _FakeExecutor(
        SkillType.js,
        result: const TextResult('42'),
      );
      final chat = _FakeAgentChat([
        _runSkill('calculate-hash'),
        const TextResponse('the answer is 42'),
      ]);

      final session = AgentSession(
        chat: chat,
        registry: registry,
        executors: [executor],
      );
      final events = await session.ask('compute').toList();

      expect(events.last, isA<DoneEvent>());
      expect((events.last as DoneEvent).text, contains('42'));
      expect(executor.calls, hasLength(1));
    });

    test('session.secretStore is the same store the loop reads', () async {
      // The facade must share one SecretStore with its loop; mutating the
      // exposed store must reach execution time.
      final secretSkill = Skill(
        name: 'weather',
        description: 'Get weather.',
        instructions: 'Call the `run_js` tool.',
        type: SkillType.js,
        metadata: const SkillMetadata(requireSecret: true),
      );
      final registry = SkillRegistry()..add(secretSkill, selected: true);
      final executor = _FakeExecutor(SkillType.js);
      final chat = _FakeAgentChat([
        _runSkill('weather'),
        const TextResponse('sunny'),
      ]);

      final session = AgentSession(
        chat: chat,
        registry: registry,
        executors: [executor],
      );
      // Set the secret AFTER construction via the facade's exposed store.
      session.secretStore.set('weather', 'sk-shared-9');

      await session.ask('weather?').toList();

      expect(executor.calls.single.secret, 'sk-shared-9');
    });
  });
}
