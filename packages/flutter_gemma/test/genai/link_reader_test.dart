import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_gemma/core/genai/link_reader.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
