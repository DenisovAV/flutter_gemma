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
}
