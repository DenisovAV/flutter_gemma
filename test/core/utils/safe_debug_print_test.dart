import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/utils/safe_debug_print.dart';

/// Regression coverage for issue #306 — a U+FFFD (`�`) in model output
/// reaching stdout makes `flutter run`'s tool-side reader throwToolExit and
/// kill the dev session. [safeDebugPrint] / [sanitizeForLog] must rewrite it
/// to the literal `U+FFFD` so the log is safe while staying visible.
/// https://github.com/DenisovAV/flutter_gemma/issues/306
void main() {
  group('sanitizeForLog', () {
    test('replaces a lone U+FFFD with the literal text', () {
      expect(sanitizeForLog('a�b'), 'aU+FFFDb');
    });

    test('replaces every occurrence', () {
      expect(sanitizeForLog('��'), 'U+FFFDU+FFFD');
    });

    test('leaves ordinary text untouched', () {
      const s = 'The UTF-8 replacement character is...';
      expect(sanitizeForLog(s), s);
    });

    test('leaves valid multi-byte / emoji text untouched', () {
      const s = 'привет 🚀 你好';
      expect(sanitizeForLog(s), s);
    });

    test('handles an empty string', () {
      expect(sanitizeForLog(''), '');
    });

    test('matches the exact bytes from the #306 repro', () {
      // The model answered with U+FFFD when asked about the replacement
      // character (source bytes 0xEF 0xBF 0xBD in the issue log).
      expect(sanitizeForLog('�** ('), 'U+FFFD** (');
    });
  });

  group('safeDebugPrint', () {
    late List<String?> printed;
    DebugPrintCallback? original;

    setUp(() {
      printed = <String?>[];
      original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
    });

    tearDown(() {
      debugPrint = original!;
    });

    test('sanitizes U+FFFD before forwarding to debugPrint', () {
      safeDebugPrint('token: �');
      expect(printed, ['token: U+FFFD']);
    });

    test('forwards ordinary text unchanged', () {
      safeDebugPrint('plain log line');
      expect(printed, ['plain log line']);
    });

    test('forwards null through to debugPrint', () {
      safeDebugPrint(null);
      expect(printed, [null]);
    });
  });
}
