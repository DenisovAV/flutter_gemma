import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_gemma/core/genai/link_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('resolves a data: URI to bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final uri = Uri.parse(
      'data:application/octet-stream;base64,${base64Encode(bytes)}',
    );
    expect(await readLinkBytes(uri), bytes);
  });

  test('throws on an unknown scheme', () async {
    expect(
      () => readLinkBytes(Uri.parse('ftp://x/y')),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('accepts a 2xx HTTP status other than 200', () async {
    final bytes = Uint8List.fromList([9, 8, 7]);
    final client = MockClient((_) async => http.Response.bytes(bytes, 206));
    expect(
      await readLinkBytes(
        Uri.parse('https://example.com/media.bin'),
        httpClient: client,
      ),
      bytes,
    );
  });

  test('throws on a non-2xx HTTP status', () async {
    final client = MockClient((_) async => http.Response('nope', 404));
    expect(
      () => readLinkBytes(
        Uri.parse('https://example.com/missing.bin'),
        httpClient: client,
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  test(
    'throws on an empty 2xx body (blank media, not silently accepted)',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes(Uint8List(0), 200),
      );
      expect(
        () => readLinkBytes(
          Uri.parse('https://example.com/empty.png'),
          httpClient: client,
        ),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('times out a hung server instead of holding forever', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return http.Response.bytes(Uint8List.fromList([1]), 200);
    });
    expect(
      () => readLinkBytes(
        Uri.parse('https://example.com/slow.png'),
        httpClient: client,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
