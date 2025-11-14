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
    // Check cancellation before starting
    cancelToken?.throwIfCancelled();

    // On web, just register the URL - no actual download
    // MediaPipe will fetch it when creating a session
    _fileSystem.registerUrl(targetPath, url);

    debugPrint('WebDownloadService: Registered URL for $targetPath');

    // Note: Token is stored but not used here
    // It would need to be passed to MediaPipe when creating session
    if (token != null) {
      debugPrint('WebDownloadService: Token provided (will be used by MediaPipe)');
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

      // Track blob URL for cleanup
      final blobUrl = await cacheService.getCachedBlobUrl(normalizedUrl);
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
      // Check cancellation before starting
      cancelToken?.throwIfCancelled();

      // Use StreamController to bridge callback-based progress to stream
      final progressController = StreamController<int>();
      final completer = Completer<Uint8List>(); // for downloaded data

      // Start download in background
      _jsInterop.fetchWithAuth(
        url,
        authToken,
        onProgress: (progress) {
          // Convert 0.0-1.0 to 0-100 and stream immediately
          final progressPercent = (progress * 100).clamp(0, 100).toInt();
          if (!progressController.isClosed) {
            progressController.add(progressPercent);
          }
        },
      ).then((response) {
        // Download complete - close stream and complete future
        if (!progressController.isClosed) {
          progressController.add(100); // Ensure final 100%
          progressController.close();
        }
        completer.complete(response.data);
      }).catchError((error) {
        // Download failed - forward error
        if (!progressController.isClosed) {
          progressController.addError(error);
          progressController.close();
        }
        completer.completeError(error);
      });

      // Yield progress as it comes in
      await for (final progress in progressController.stream) {
        cancelToken?.throwIfCancelled();
        yield progress;
      }

      // Get downloaded data after stream completes
      cancelToken?.throwIfCancelled();
      final data = await completer.future;

      // Save to Cache API
      debugPrint('💾 Saving authenticated model to cache: ${data.length} bytes');
      await cacheService.cacheModel(normalizedUrl, data);

      // Create blob URL from cached data
      final blobUrl = await cacheService.getCachedBlobUrl(normalizedUrl);
      if (blobUrl == null) {
        throw Exception('Failed to create blob URL from cache');
      }

      // Register blob URL
      _fileSystem.registerUrl(targetPath, blobUrl);
      _blobUrlManager.track(targetPath, blobUrl);

      debugPrint('✅ Authenticated model downloaded and cached');
    } on JsInteropException catch (e) {
      debugPrint('❌ Authenticated download failed: $e');
      throw DownloadException(
        DownloadError.unknown('Failed to download authenticated model: $e'),
      );
    } on DownloadCancelledException {
      debugPrint('WebDownloadService: Download cancelled for $targetPath');
      rethrow;
    } catch (e) {
      debugPrint('❌ Download failed for $targetPath: $e');
      throw DownloadException(
        DownloadError.unknown('Failed to download model: $e'),
      );
    }
  }

}
