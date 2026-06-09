import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';

void main() {
  group('sanitizeForLog', () {
    test('replaces a lone U+FFFD with literal text', () {
      expect(sanitizeForLog('a�b'), 'aU+FFFDb');
    });

    test('replaces every U+FFFD occurrence', () {
      expect(sanitizeForLog('��'), 'U+FFFDU+FFFD');
    });

    test('leaves ordinary text untouched', () {
      const s = 'The UTF-8 replacement character is...';
      expect(sanitizeForLog(s), s);
    });

    test('leaves valid emoji / multi-byte text untouched', () {
      const s = 'привет 🚀 你好';
      expect(sanitizeForLog(s), s);
    });

    test('handles empty string', () {
      expect(sanitizeForLog(''), '');
    });

    test('replaces a lone HIGH surrogate at end of string', () {
      final lone = String.fromCharCode(0xD83D);
      expect(sanitizeForLog('ab$lone'), 'abU+FFFD');
    });

    test('replaces a lone LOW surrogate', () {
      final lone = String.fromCharCode(0xDE80);
      expect(sanitizeForLog('${lone}x'), 'U+FFFDx');
    });

    test('keeps a valid surrogate pair', () {
      const rocket = '🚀';
      expect(sanitizeForLog('go $rocket now'), 'go 🚀 now');
    });

    test('matches the exact bytes from the #306 repro', () {
      expect(sanitizeForLog('�** ('), 'U+FFFD** (');
    });
  });
}
