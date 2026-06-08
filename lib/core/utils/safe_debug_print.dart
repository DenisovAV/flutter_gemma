import 'package:flutter/foundation.dart';

/// Drop-in [debugPrint] replacement that neutralizes the Unicode
/// replacement character (U+FFFD, `�`) before printing.
///
/// When a U+FFFD byte sequence reaches the app's stdout, `flutter run`'s
/// tool-side reader treats it as a malformed-output signal and calls
/// `throwToolExit`, killing the dev session (see
/// flutter_tools/lib/src/convert.dart). Model output can legitimately
/// contain U+FFFD — e.g. when the model is asked about the replacement
/// character itself, or emits a byte-fallback token — so logging raw model
/// tokens crashes `flutter run` even though the app itself is fine.
///
/// This wrapper rewrites `�` to the literal text `U+FFFD` so the log stays
/// visible (and the fact that a replacement char was present is still
/// shown) without tripping the tool. Use it only where model-produced text
/// is logged; ordinary plugin log lines never contain U+FFFD. Issue #306.
void safeDebugPrint(String? message, {int? wrapWidth}) {
  if (message == null) {
    debugPrint(null, wrapWidth: wrapWidth);
    return;
  }
  debugPrint(sanitizeForLog(message), wrapWidth: wrapWidth);
}

/// Replaces every U+FFFD (`�`) in [text] with the literal `U+FFFD` so the
/// string is safe to send to stdout under `flutter run`. Exposed for call
/// sites that build a log string by hand (e.g. truncating helpers) rather
/// than calling [safeDebugPrint] directly.
String sanitizeForLog(String text) => text.replaceAll('�', 'U+FFFD');
