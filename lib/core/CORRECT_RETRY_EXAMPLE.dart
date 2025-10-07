import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/download_exception.dart';

/// ❌ WRONG: This will retry forever on 401!
Future<void> wrongRetryExample(String url) async {
  int attempt = 0;
  const maxRetries = 3;

  while (attempt < maxRetries) {
    try {
      await FlutterGemma.installModel()
        .fromNetwork(url)
        .install();
      return; // Success
    } catch (e) {
      // ❌ BAD: Catches ALL errors including 401!
      attempt++;
      if (attempt >= maxRetries) {
        rethrow;
      }
      await Future.delayed(Duration(seconds: 2));
      // Will keep retrying even on 401! 🐛
    }
  }
}

/// ✅ CORRECT: Stops immediately on 401/403
Future<void> correctRetryExample(String url) async {
  int attempt = 0;
  const maxRetries = 3;

  while (attempt < maxRetries) {
    try {
      await FlutterGemma.installModel()
        .fromNetwork(url)
        .install();
      return; // Success
    } on DownloadException catch (e) {
      // ✅ GOOD: Check if error is retryable
      if (!e.error.isRetryable) {
        // 401, 403, 404 - stop immediately!
        print('❌ ${e.error.toTitle()}: ${e.error.toUserMessage()}');
        rethrow;
      }

      // Only retry transient errors (network, server, rate limit)
      attempt++;
      if (attempt >= maxRetries) {
        print('❌ Failed after $maxRetries attempts');
        rethrow;
      }

      final delay = Duration(seconds: attempt * 2);
      print('⏳ Retry $attempt/$maxRetries after ${e.error.toTitle()}. Waiting ${delay.inSeconds}s...');
      await Future.delayed(delay);
    }
  }
}

/// ✅ EVEN BETTER: Using helper method
Future<void> bestRetryExample(String url) async {
  try {
    await FlutterGemma.installModel()
      .fromNetwork(url)
      .install();
  } on DownloadException catch (e) {
    // Check what type of error
    if (e.error.requiresUserAction) {
      // 401/403/404 - show dialog
      print('⚠️ User action required:');
      print('   ${e.error.toTitle()}');
      print('   ${e.error.toUserMessage()}');
      rethrow;
    } else if (e.error.isRetryable) {
      // Network/server errors - auto retry
      print('🔄 Retrying...');
      await _retryWithBackoff(url, maxRetries: 3);
    } else {
      // Canceled or unknown
      print('❌ ${e.error.toUserMessage()}');
      rethrow;
    }
  }
}

Future<void> _retryWithBackoff(String url, {required int maxRetries}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await FlutterGemma.installModel()
        .fromNetwork(url)
        .install();
      return; // Success
    } on DownloadException catch (e) {
      if (!e.error.isRetryable || attempt >= maxRetries) {
        rethrow;
      }

      final delay = Duration(seconds: attempt * 2);
      print('⏳ Retry $attempt/$maxRetries in ${delay.inSeconds}s');
      await Future.delayed(delay);
    }
  }
}

/// 📊 Summary of error behavior:
///
/// | Error | isRetryable | requiresUserAction | Behavior |
/// |-------|-------------|-------------------|----------|
/// | 401 Unauthorized | ❌ false | ✅ true | Stop immediately, show "Add token" |
/// | 403 Forbidden | ❌ false | ✅ true | Stop immediately, show "Request access" |
/// | 404 Not Found | ❌ false | ✅ true | Stop immediately, show "Fix URL" |
/// | 429 Rate Limited | ✅ true | ❌ false | Auto retry with backoff |
/// | 5xx Server Error | ✅ true | ❌ false | Auto retry (temporary issue) |
/// | Network Error | ✅ true | ❌ false | Auto retry (connection issue) |
/// | Canceled | ❌ false | ❌ false | Stop (user canceled) |
///
/// Example usage:
/// ```dart
/// try {
///   await correctRetryExample('https://huggingface.co/...');
/// } catch (e) {
///   // Will only reach here if:
///   // 1. Auth error (401/403)
///   // 2. Not found (404)
///   // 3. Max retries exceeded
///   showErrorDialog(e.toString());
/// }
/// ```
