import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/src/routing_context.dart';
import 'package:genkit_hybrid/src/strategies/capability.dart';
import 'package:genkit_hybrid/src/strategies/with_fallback.dart';
import 'package:test/test.dart';

RoutingContext _ctx(ModelRequest? req) => RoutingContext(
  request: req,
  branchKeys: const {'text', 'vision'},
  isStreaming: false,
);

ModelRequest _imageByContentType() => ModelRequest(
  messages: [
    Message(
      role: Role.user,
      content: [
        MediaPart(
          media: Media(contentType: 'image/png', url: 'https://x/y.png'),
        ),
      ],
    ),
  ],
);

ModelRequest _imageByDataUrl() => ModelRequest(
  messages: [
    Message(
      role: Role.user,
      content: [
        MediaPart(
          media: Media(url: 'data:image/jpeg;base64,AAAA'),
        ), // no contentType
      ],
    ),
  ],
);

void main() {
  final strat = CapabilityStrategy(
    supports: {
      'text': {},
      'vision': {ModelCapability.vision},
    },
    order: ['text', 'vision'],
  );

  test('image via contentType -> only the vision branch', () {
    expect(strat.route(_ctx(_imageByContentType())), ['vision']);
  });

  test('image via data: url (contentType null) -> only the vision branch', () {
    expect(strat.route(_ctx(_imageByDataUrl())), ['vision']);
  });

  test('no requirement -> full order', () {
    expect(strat.route(_ctx(ModelRequest(messages: []))), ['text', 'vision']);
  });

  test('null request -> full order', () {
    expect(strat.route(_ctx(null)), ['text', 'vision']);
  });

  test('no capable branch -> [] (no decision)', () {
    final s = CapabilityStrategy(supports: {'text': {}}, order: ['text']);
    expect(s.route(_ctx(_imageByContentType())), <String>[]);
  });

  test('tools required -> only the tool-capable branch', () {
    final s = CapabilityStrategy(
      supports: {
        'a': {},
        'b': {ModelCapability.tools},
      },
      order: ['a', 'b'],
    );
    final req = ModelRequest(
      messages: [],
      tools: [ToolDefinition(name: 'get', description: 'd', inputSchema: {})],
    );
    expect(s.route(_ctx(req)), ['b']);
  });

  test('json required via output.format', () {
    final s = CapabilityStrategy(
      supports: {
        'a': {},
        'j': {ModelCapability.json},
      },
      order: ['a', 'j'],
    );
    final req = ModelRequest(
      messages: [],
      output: OutputConfig(format: 'json'),
    );
    expect(s.route(_ctx(req)), ['j']);
  });

  test('json required via output.schema', () {
    final s = CapabilityStrategy(
      supports: {
        'a': {},
        'j': {ModelCapability.json},
      },
      order: ['a', 'j'],
    );
    final req = ModelRequest(
      messages: [],
      output: OutputConfig(schema: {'type': 'object'}),
    );
    expect(s.route(_ctx(req)), ['j']);
  });

  test('json required via output.contentType', () {
    final s = CapabilityStrategy(
      supports: {
        'a': {},
        'j': {ModelCapability.json},
      },
      order: ['a', 'j'],
    );
    final req = ModelRequest(
      messages: [],
      output: OutputConfig(contentType: 'application/json'),
    );
    expect(s.route(_ctx(req)), ['j']);
  });

  test(
    'WithFallback rescues when nothing is capable (try-anyway is composition)',
    () {
      final s = WithFallback(
        CapabilityStrategy(supports: {'text': {}}, order: ['text']),
        fallbackOrder: ['text'],
      );
      expect(s.route(_ctx(_imageByContentType())), ['text']);
    },
  );

  test('audio via contentType -> only the audio branch', () {
    final s = CapabilityStrategy(
      supports: {
        'text': {},
        'audio': {ModelCapability.audio},
      },
      order: ['text', 'audio'],
    );
    final req = ModelRequest(
      messages: [
        Message(
          role: Role.user,
          content: [
            MediaPart(
              media: Media(contentType: 'audio/wav', url: 'https://x/y.wav'),
            ),
          ],
        ),
      ],
    );
    expect(s.route(_ctx(req)), ['audio']);
  });

  test('audio via data: url (contentType null) -> only the audio branch', () {
    final s = CapabilityStrategy(
      supports: {
        'text': {},
        'audio': {ModelCapability.audio},
      },
      order: ['text', 'audio'],
    );
    final req = ModelRequest(
      messages: [
        Message(
          role: Role.user,
          content: [MediaPart(media: Media(url: 'data:audio/wav;base64,AA'))],
        ),
      ],
    );
    expect(s.route(_ctx(req)), ['audio']);
  });

  test('bare-URL image (no contentType) is detected via file extension', () {
    final req = ModelRequest(
      messages: [
        Message(
          role: Role.user,
          content: [MediaPart(media: Media(url: 'https://cdn/x/cat.jpg'))],
        ),
      ],
    );
    expect(strat.route(_ctx(req)), ['vision']);
  });

  test(
    'multi-capability request requires ALL capabilities (containsAll, not any-match)',
    () {
      final s = CapabilityStrategy(
        supports: {
          'a': {ModelCapability.vision},
          'b': {ModelCapability.vision, ModelCapability.tools},
        },
        order: ['a', 'b'],
      );
      final req = ModelRequest(
        messages: [
          Message(
            role: Role.user,
            content: [
              MediaPart(
                media: Media(contentType: 'image/png', url: 'https://x/y.png'),
              ),
            ],
          ),
        ],
        tools: [ToolDefinition(name: 'get', description: 'd', inputSchema: {})],
      );
      expect(s.route(_ctx(req)), ['b']);
    },
  );

  test(
    'an explicit order naming a key absent from supports throws ArgumentError',
    () {
      expect(
        () => CapabilityStrategy(supports: {'a': {}}, order: ['a', 'missing']),
        throwsArgumentError,
      );
    },
  );

  test('default order (omitted) is supports insertion order', () {
    final s = CapabilityStrategy(
      supports: {
        'a': {},
        'b': {ModelCapability.vision},
      },
    );
    expect(s.route(_ctx(ModelRequest(messages: []))), ['a', 'b']);
  });
}
