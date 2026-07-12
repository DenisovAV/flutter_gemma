import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'link_reader_stub.dart' if (dart.library.io) 'link_reader_io.dart';

/// Resolves a genai_primitives LinkPart URI to bytes.
/// - data:      decoded in-memory (no I/O)
/// - file://    dart:io on native; throws on web
/// - http(s)::  injected client, else default http.Client (wasm-safe BrowserClient on web)
Future<Uint8List> readLinkBytes(
  Uri uri, {
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 30),
}) async {
  switch (uri.scheme) {
    case 'data':
      final data = uri.data;
      if (data == null) {
        throw ArgumentError('Malformed data: URI: $uri');
      }
      return data.contentAsBytes();
    case 'http':
    case 'https':
      final client = httpClient ?? http.Client();
      try {
        // Bound the fetch: readLinkBytes is awaited while the chat mutex is
        // held, so a hung server would otherwise wedge the whole genai surface.
        final resp = await client.get(uri).timeout(timeout);
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw http.ClientException('HTTP ${resp.statusCode} for $uri', uri);
        }
        // A 2xx with an empty body (204/205, or a truncated proxy response)
        // would otherwise flow on as blank image/audio — a silent media drop.
        if (resp.bodyBytes.isEmpty) {
          throw http.ClientException(
            'Empty body (${resp.statusCode}) for $uri',
            uri,
          );
        }
        return resp.bodyBytes;
      } finally {
        if (httpClient == null) client.close();
      }
    case 'file':
      return readFileUri(uri);
    default:
      if (uri.scheme.isEmpty) return readFileUri(uri); // bare path
      throw UnsupportedError(
        'Unsupported LinkPart scheme "${uri.scheme}": $uri',
      );
  }
}
