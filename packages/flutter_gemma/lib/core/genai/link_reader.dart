import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'link_reader_stub.dart' if (dart.library.io) 'link_reader_io.dart';

/// Resolves a genai_primitives LinkPart URI to bytes.
/// - data:      decoded in-memory (no I/O)
/// - file://    dart:io on native; throws on web
/// - http(s)::  injected client, else default http.Client (wasm-safe BrowserClient on web)
Future<Uint8List> readLinkBytes(Uri uri, {http.Client? httpClient}) async {
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
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          throw http.ClientException('HTTP ${resp.statusCode} for $uri', uri);
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
