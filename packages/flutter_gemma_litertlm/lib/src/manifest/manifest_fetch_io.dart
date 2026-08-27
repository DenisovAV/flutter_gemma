import 'dart:convert';
import 'dart:io';

import 'manifest_fetch_types.dart';

/// Default manifest GET on `dart:io` platforms.
///
/// A plain [HttpClient] — deliberately not the plugin's model-download stack
/// (background_downloader is sized for multi-GB files, not a few KB of JSON).
/// [HttpClient] follows redirects for GET by default, which matters here:
/// Hugging Face answers `/resolve/` paths with a 307 to its CDN.
Future<String> defaultManifestFetch(
  Uri url,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw ManifestFetchException(
        url,
        'GET failed with HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return body;
  } on ManifestFetchException {
    rethrow;
  } on Exception catch (e) {
    throw ManifestFetchException(url, 'GET failed: $e');
  } finally {
    client.close();
  }
}
