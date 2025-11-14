import 'package:flutter/foundation.dart';

/// Utilities for URL manipulation
class UrlUtils {
  /// Normalize URL for cache lookup
  ///
  /// Removes query parameters and trailing slashes to ensure
  /// the same model uses the same cache entry regardless of
  /// authentication tokens in URL.
  static String normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final normalized = uri.replace(query: '').toString();
      return normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
    } catch (e) {
      debugPrint('[UrlUtils] ⚠️  URL normalization failed: $e');
      return url;
    }
  }
}
