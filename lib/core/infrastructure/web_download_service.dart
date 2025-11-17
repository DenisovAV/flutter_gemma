import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/download_exception.dart';
import 'package:flutter_gemma/core/domain/download_error.dart';
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_js_interop.dart';
import 'package:flutter_gemma/core/infrastructure/blob_url_manager.dart';
import 'package:flutter_gemma/core/infrastructure/web_cache_service.dart';
import 'package:flutter_gemma/core/infrastructure/url_utils.dart';

/// Web implementation of DownloadService
///
/// This implementation doesn't actually download files. Instead, it registers
/// URLs with the WebFileSystemService so MediaPipe can fetch them directly.
///
/// Features:
/// - URL registration (no actual download)
/// - Progress simulation for UX consistency (matches mobile experience)
/// - Authentication token support (passed to MediaPipe)
/// - Fast "installation" (just URL registration)
///
/// Design rationale:
/// - Web browsers handle download/caching automatically
/// - MediaPipe fetches models from URLs at session creation time
/// - Simulating progress gives users consistent UX across platforms
/// - No local storage needed (browser manages cache)
///
/// Platform: Web only
class WebDownloadService implements DownloadService {
  final WebFileSystemService _fileSystem;
  final WebJsInterop _jsInterop;
  final BlobUrlManager _blobUrlManager;
  final WebCacheService cacheService;

  WebDownloadService(
    this._fileSystem,
    this._jsInterop,
    this._blobUrlManager,
    this.cacheService,
  );

  @override
  Future<void> download(
    String url,
    String targetPath, {
    String? token,
    CancelToken? cancelToken,
  }) async {
    // Delegate to downloadWithProgress, ignore progress events
    await for (final _ in downloadWithProgress(
      url,
      targetPath,
      token: token,
      cancelToken: cancelToken,
    )) {
      // Ignore progress updates
    }
  }

  @override
  Stream<int> downloadWithProgress(
    String url,
    String targetPath, {
    String? token,
    int maxRetries = 10,
    CancelToken? cancelToken,
  }) async* {
    // Check cancellation before starting
    cancelToken?.throwIfCancelled();

    // Normalize URL for cache lookup
    final normalizedUrl = UrlUtils.normalizeUrl(url);

    // Check cache first (works for both public and private models)
    final cachedBlobUrl = await cacheService.getCachedBlobUrl(normalizedUrl);
    if (cachedBlobUrl != null) {
      debugPrint('✅ Model found in cache (skipping download): $url');

      // Register cached blob URL
      _fileSystem.registerUrl(targetPath, cachedBlobUrl);
      _blobUrlManager.track(targetPath, cachedBlobUrl);

      // Simulate instant progress
      yield 100;
      return;
    }

    // Not in cache - proceed with download
    debugPrint('📥 Model not in cache, downloading: $url');

    if (token == null) {
      // PUBLIC PATH: Download and cache
      yield* _downloadPublic(url, normalizedUrl, targetPath, cancelToken);
    } else {
      // PRIVATE PATH: Fetch with auth
      debugPrint('WebDownloadService: Starting authenticated download for $targetPath');

      yield* _downloadWithAuth(url, normalizedUrl, targetPath, token, cancelToken);
    }
  }

  /// Download public model (no auth) and cache
  Stream<int> _downloadPublic(
    String url,
    String normalizedUrl,
    String targetPath,
    CancelToken? cancelToken,
  ) async* {
    try {
      cancelToken?.throwIfCancelled();

      // Use unified caching helper with progress
      yield* cacheService.getOrCacheAndRegisterWithProgress(
        cacheKey: normalizedUrl,
        loader: (onProgress) async {
          cancelToken?.throwIfCancelled();

          debugPrint('[WebDownloadService] 📥 Downloading public model: $url');

          // Note: fetchFile doesn't support progress callbacks yet
          final response = await _jsInterop.fetchFile(url);

          debugPrint('[WebDownloadService] ✅ Downloaded: ${response.data.length} bytes');
          onProgress(1.0);

          return response.data;
        },
        targetPath: targetPath,
      );

      // Track blob URL for cleanup (works with or without cache)
      final blobUrl = _fileSystem.getUrl(targetPath);
      if (blobUrl != null) {
        _blobUrlManager.track(targetPath, blobUrl);
      }

      debugPrint('[WebDownloadService] ✅ Public model downloaded and cached');
    } on DownloadCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('[WebDownloadService] ❌ Public download failed: $e');
      throw DownloadException(
        DownloadError.unknown('Failed to download public model: $e'),
      );
    }
  }

  Stream<int> _downloadWithAuth(
    String url,
    String normalizedUrl,
    String targetPath,
    String authToken,
    CancelToken? cancelToken,
  ) async* {
    try {
      cancelToken?.throwIfCancelled();

      debugPrint('WebDownloadService: Starting authenticated download for $targetPath');

      // Use unified caching helper with auth download
      yield* cacheService.getOrCacheAndRegisterWithProgress(
        cacheKey: normalizedUrl,
        loader: (onProgress) async {
          cancelToken?.throwIfCancelled();

          debugPrint('[WebDownloadService] 📥 Downloading authenticated model: $url');

          // Create completer for async result
          final completer = Completer<Uint8List>();

          // Start download with streaming progress
          _jsInterop.fetchWithAuth(
            url,
            authToken,
            onProgress: onProgress, // Pass progress callback directly
          ).then((response) {
            debugPrint('[WebDownloadService] ✅ Downloaded: ${response.data.length} bytes');
            completer.complete(response.data);
          }).catchError((error) {
            completer.completeError(error);
          });

          return await completer.future;
        },
        targetPath: targetPath,
      );

      // Track blob URL for cleanup (works with or without cache)
      final blobUrl = _fileSystem.getUrl(targetPath);
      if (blobUrl != null) {
        _blobUrlManager.track(targetPath, blobUrl);
      }

      debugPrint('[WebDownloadService] ✅ Authenticated model downloaded and cached');
    } on DownloadCancelledException {
      debugPrint('WebDownloadService: Download cancelled for $targetPath');
      rethrow;
    } catch (e) {
      debugPrint('[WebDownloadService] ❌ Authenticated download failed: $e');
      throw DownloadException(
        DownloadError.unknown('Failed to download authenticated model: $e'),
      );
    }
  }

}
