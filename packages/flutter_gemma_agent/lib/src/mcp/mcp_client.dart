import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mcp_server_config.dart';

/// Thrown when an MCP request fails at the transport or JSON-RPC layer.
class McpException implements Exception {
  McpException(this.message);

  final String message;

  @override
  String toString() => 'McpException: $message';
}

/// The text content of a `tools/call` result, plus whether the server flagged it
/// an error. Mirrors Gallery's `TextContent` extraction (`isError` + joined
/// `text` items).
class McpToolResult {
  const McpToolResult({required this.text, required this.isError});

  /// The joined text of every `text` content item in the result.
  final String text;

  /// Whether the server returned `isError: true` (the model should recover).
  final bool isError;

  @override
  String toString() => 'McpToolResult(isError: $isError, ${text.length} chars)';
}

/// A minimal MCP (Model Context Protocol) client over **Streamable HTTP** —
/// JSON-RPC 2.0 POSTed to the server's single endpoint.
///
/// This is the cross-platform equivalent of the Gallery Kotlin SDK's
/// `StreamableHttpClientTransport` + `Client`: [connect] performs the
/// `initialize` handshake (capturing the `Mcp-Session-Id`), sends the
/// `notifications/initialized` notification, and runs `tools/list`; [callTool]
/// runs `tools/call` and extracts the text content.
///
/// Responses may come back as either `application/json` or an SSE
/// (`text/event-stream`) frame — both are handled. The injectable [httpClient]
/// keeps it unit-testable with a fake client.
class McpClient {
  McpClient({
    required this.config,
    http.Client? httpClient,
    this.clientName = 'flutter_gemma_agent',
    this.clientVersion = '0.1.0',
    this.protocolVersion = '2025-06-18',
  }) : _ownsClient = httpClient == null,
       _http = httpClient ?? http.Client(),
       // Seed from any cached tools on the config so a client constructed for
       // offline UI (or in tests) is immediately routable before connect().
       _tools = List.of(config.tools);

  /// The server this client talks to (its [McpServerConfig.url] + auth).
  final McpServerConfig config;

  /// The `clientInfo.name` reported in the initialize handshake.
  final String clientName;

  /// The `clientInfo.version` reported in the initialize handshake.
  final String clientVersion;

  /// The MCP `protocolVersion` advertised in the initialize handshake.
  final String protocolVersion;

  final http.Client _http;
  final bool _ownsClient;

  /// The session id the server returned in the `Mcp-Session-Id` header of the
  /// initialize response, echoed back on every subsequent request. Null until
  /// [connect] runs (some servers do not use sessions).
  String? _sessionId;

  /// The tools known to this client — seeded from any cached [config.tools] and
  /// refreshed by [connect] / [listTools].
  List<McpTool> _tools;

  /// Monotonic JSON-RPC request id.
  int _nextId = 1;

  /// The tools known on the server (seeded from cached [McpServerConfig.tools],
  /// refreshed by [connect] / [listTools]).
  List<McpTool> get tools => List.unmodifiable(_tools);

  /// The negotiated session id, if any.
  String? get sessionId => _sessionId;

  /// Perform the initialize handshake and load the server's tools, returning a
  /// [config] copy whose [McpServerConfig.tools] / name / version are filled in.
  ///
  /// Preserves the enabled / alwaysAllow flags of any tools already on [config]
  /// (so a reconnect keeps the user's preferences), exactly like Gallery's
  /// `initializeClientAndLoadTools`.
  Future<McpServerConfig> connect() async {
    final savedEnabled = {for (final t in config.tools) t.name: t.enabled};
    final savedAlwaysAllow = {
      for (final t in config.tools) t.name: t.alwaysAllow,
    };

    // 1. initialize — capture the session id + server identity.
    final initResult = await _request('initialize', {
      'protocolVersion': protocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': clientName, 'version': clientVersion},
    }, captureSession: true);

    final serverInfo = initResult['serverInfo'];
    final serverName = serverInfo is Map ? '${serverInfo['name'] ?? ''}' : '';
    final serverVersion = serverInfo is Map
        ? '${serverInfo['version'] ?? ''}'
        : '';

    // 2. notifications/initialized — required by the spec before normal use.
    await _notify('notifications/initialized');

    // 3. tools/list — discover the tools.
    _tools = await _fetchTools(
      savedEnabled: savedEnabled,
      savedAlwaysAllow: savedAlwaysAllow,
    );

    return config.copyWith(
      name: serverName.isNotEmpty ? serverName : null,
      version: serverVersion.isNotEmpty ? serverVersion : null,
      tools: _tools,
    );
  }

  /// Re-run `tools/list` (without re-initializing), refreshing [tools].
  Future<List<McpTool>> listTools() async {
    final savedEnabled = {for (final t in _tools) t.name: t.enabled};
    final savedAlwaysAllow = {for (final t in _tools) t.name: t.alwaysAllow};
    _tools = await _fetchTools(
      savedEnabled: savedEnabled,
      savedAlwaysAllow: savedAlwaysAllow,
    );
    return tools;
  }

  /// Call the MCP tool [toolName] with [arguments] (`tools/call`), returning its
  /// extracted text content. Throws [McpException] on a transport failure;
  /// returns a result with `isError: true` when the server flags the tool error.
  Future<McpToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _request('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    return _extractToolResult(result);
  }

  Future<List<McpTool>> _fetchTools({
    required Map<String, bool> savedEnabled,
    required Map<String, bool> savedAlwaysAllow,
  }) async {
    final result = await _request('tools/list', const {});
    final rawTools = result['tools'];
    if (rawTools is! List) return const [];
    return [
      for (final raw in rawTools)
        if (raw is Map)
          McpTool(
            name: '${raw['name'] ?? ''}',
            description: '${raw['description'] ?? ''}',
            inputSchema: raw['inputSchema'] is Map
                ? Map<String, dynamic>.from(raw['inputSchema'] as Map)
                : const {},
            enabled: savedEnabled['${raw['name'] ?? ''}'] ?? true,
            alwaysAllow: savedAlwaysAllow['${raw['name'] ?? ''}'] ?? false,
          ),
    ];
  }

  /// Join every `text` item in a `tools/call` result's `content` array (Gallery's
  /// `filterIsInstance<TextContent>().joinToString("\n")`).
  McpToolResult _extractToolResult(Map<String, dynamic> result) {
    final isError = result['isError'] == true;
    final content = result['content'];
    final buffer = <String>[];
    if (content is List) {
      for (final item in content) {
        if (item is Map && item['type'] == 'text') {
          buffer.add('${item['text'] ?? ''}');
        }
      }
    }
    return McpToolResult(text: buffer.join('\n'), isError: isError);
  }

  /// Send a JSON-RPC request and return its `result` object. When
  /// [captureSession] is true, store the `Mcp-Session-Id` response header.
  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params, {
    bool captureSession = false,
  }) async {
    final id = _nextId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse(config.url),
        headers: _headers(),
        body: body,
      );
    } catch (e) {
      throw McpException('MCP "$method" request failed: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpException(
        'MCP "$method" returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    if (captureSession) {
      final sid = response.headers['mcp-session-id'];
      if (sid != null && sid.isNotEmpty) _sessionId = sid;
    }

    final message = _parseRpcBody(response, method);
    final error = message['error'];
    if (error is Map) {
      throw McpException('MCP "$method" error: ${error['message'] ?? error}');
    }
    final result = message['result'];
    if (result is! Map) {
      throw McpException('MCP "$method" returned no result object.');
    }
    return Map<String, dynamic>.from(result);
  }

  /// Send a fire-and-forget JSON-RPC notification (no `id`, no result expected).
  Future<void> _notify(String method) async {
    final body = jsonEncode({'jsonrpc': '2.0', 'method': method});
    try {
      await _http.post(Uri.parse(config.url), headers: _headers(), body: body);
    } catch (_) {
      // Notifications are best-effort; a failure here is non-fatal.
    }
  }

  /// Parse a JSON-RPC response body that may be plain `application/json` or an
  /// SSE (`text/event-stream`) frame whose `data:` lines carry the JSON message.
  Map<String, dynamic> _parseRpcBody(http.Response response, String method) {
    final contentType = response.headers['content-type'] ?? '';
    final raw = contentType.contains('text/event-stream')
        ? _extractSseJson(response.body)
        : response.body;
    if (raw.trim().isEmpty) {
      throw McpException('MCP "$method" returned an empty body.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw McpException('MCP "$method" returned a non-object JSON-RPC body.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Pull the JSON payload out of an SSE stream: the concatenation of the `data:`
  /// lines of the LAST event (the one carrying the JSON-RPC response).
  String _extractSseJson(String body) {
    final dataLines = <String>[];
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      } else if (line.isEmpty && dataLines.isNotEmpty) {
        // Event boundary: keep the latest complete event's data.
      }
    }
    return dataLines.join('\n');
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Mcp-Session-Id': ?_sessionId,
      ...config.authHeaders,
    };
  }

  /// Close the underlying HTTP client (only if this client created it).
  void close() {
    if (_ownsClient) _http.close();
  }
}
