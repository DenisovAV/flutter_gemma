import 'dart:convert';

import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A scripted MCP server: returns a canned JSON-RPC reply per `method`, records
/// every request, and lets a test assert on the headers/body it received.
class _FakeMcpServer {
  _FakeMcpServer({this.sessionId = 'sess-123', this.toolsAsSse = false});

  final String sessionId;
  final bool toolsAsSse;
  final requests = <_RecordedRequest>[];

  http.Client get client => MockClient((request) async {
    final decoded = jsonDecode(request.body) as Map<String, dynamic>;
    final method = decoded['method'] as String;
    requests.add(
      _RecordedRequest(method: method, headers: request.headers, body: decoded),
    );

    switch (method) {
      case 'initialize':
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': {
              'protocolVersion': '2025-06-18',
              'serverInfo': {'name': 'fake-mcp', 'version': '9.9'},
            },
          }),
          200,
          headers: {
            'content-type': 'application/json',
            'mcp-session-id': sessionId,
          },
        );
      case 'notifications/initialized':
        return http.Response('', 202);
      case 'tools/list':
        final payload = jsonEncode({
          'jsonrpc': '2.0',
          'id': decoded['id'],
          'result': {
            'tools': [
              {
                'name': 'get_weather',
                'description': 'Weather for a city.',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
              },
            ],
          },
        });
        if (toolsAsSse) {
          return http.Response(
            'event: message\ndata: $payload\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response(
          payload,
          200,
          headers: {'content-type': 'application/json'},
        );
      case 'tools/call':
        final args = decoded['params']['arguments'] as Map;
        final city = args['city'] ?? 'unknown';
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': {
              'content': [
                {'type': 'text', 'text': 'Sunny in $city'},
              ],
              'isError': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      default:
        return http.Response('not found', 404);
    }
  });
}

class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.headers,
    required this.body,
  });
  final String method;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
}

void main() {
  const config = McpServerConfig(url: 'https://example.com/mcp');

  group('McpClient.connect', () {
    test('runs initialize → notifications/initialized → tools/list', () async {
      final server = _FakeMcpServer();
      final client = McpClient(config: config, httpClient: server.client);

      final connected = await client.connect();

      expect(server.requests.map((r) => r.method), [
        'initialize',
        'notifications/initialized',
        'tools/list',
      ]);
      expect(connected.name, 'fake-mcp');
      expect(connected.version, '9.9');
      expect(connected.tools.single.name, 'get_weather');
      expect(client.tools.single.description, 'Weather for a city.');
    });

    test('captures Mcp-Session-Id and echoes it on later requests', () async {
      final server = _FakeMcpServer(sessionId: 'abc-789');
      final client = McpClient(config: config, httpClient: server.client);

      await client.connect();

      expect(client.sessionId, 'abc-789');
      final toolsListReq = server.requests.firstWhere(
        (r) => r.method == 'tools/list',
      );
      expect(toolsListReq.headers['mcp-session-id'], 'abc-789');
    });

    test('sends the spec-required Accept header', () async {
      final server = _FakeMcpServer();
      final client = McpClient(config: config, httpClient: server.client);

      await client.connect();

      final accept = server.requests.first.headers['accept'] ?? '';
      expect(accept, contains('application/json'));
      expect(accept, contains('text/event-stream'));
    });

    test('parses a tools/list delivered as an SSE frame', () async {
      final server = _FakeMcpServer(toolsAsSse: true);
      final client = McpClient(config: config, httpClient: server.client);

      final connected = await client.connect();

      expect(connected.tools.single.name, 'get_weather');
    });

    test('preserves enabled/alwaysAllow across a reconnect', () async {
      final server = _FakeMcpServer();
      final seeded = config.copyWith(
        tools: const [McpTool(name: 'get_weather', alwaysAllow: true)],
      );
      final client = McpClient(config: seeded, httpClient: server.client);

      final connected = await client.connect();

      expect(connected.tools.single.alwaysAllow, isTrue);
    });
  });

  group('McpClient.callTool', () {
    test('extracts joined text content from the result', () async {
      final server = _FakeMcpServer();
      final client = McpClient(config: config, httpClient: server.client);
      await client.connect();

      final result = await client.callTool('get_weather', {'city': 'Seattle'});

      expect(result.isError, isFalse);
      expect(result.text, 'Sunny in Seattle');
    });

    test('surfaces a JSON-RPC error as an McpException', () async {
      final errClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'error': {'code': -32000, 'message': 'boom'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = McpClient(config: config, httpClient: errClient);

      expect(
        () => client.callTool('get_weather', const {}),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    test('non-2xx HTTP is an McpException', () async {
      final errClient = MockClient(
        (request) async => http.Response('nope', 500),
      );
      final client = McpClient(config: config, httpClient: errClient);

      expect(
        () => client.callTool('get_weather', const {}),
        throwsA(isA<McpException>()),
      );
    });

    test('a tool flagged isError returns isError:true (not a throw)', () async {
      final errToolClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': {
              'content': [
                {'type': 'text', 'text': 'city is required'},
              ],
              'isError': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = McpClient(config: config, httpClient: errToolClient);

      final result = await client.callTool('get_weather', const {});
      expect(result.isError, isTrue);
      expect(result.text, 'city is required');
    });
  });
}
