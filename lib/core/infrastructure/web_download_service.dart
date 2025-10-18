import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/services/download_service.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_js_interop.dart';
import 'package:flutter_gemma/core/infrastructure/blob_url_manager.dart';
import 'package:flutter_gemma/core/domain/download_exception.dart';
import 'package:flutter_gemma/core/domain/download_error.dart';

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

  WebDownloadService(
    this._fileSystem,
    this._jsInterop,
    this._blobUrlManager,
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

    if (token == null) {
      // PUBLIC PATH: Direct URL registration
      try {
        final uri = Uri.tryParse(url);
        if (uri == null || (!uri.isScheme('HTTP') && !uri.isScheme('HTTPS'))) {
          throw ArgumentError('Invalid URL: $url. Must be HTTP or HTTPS.');
        }

        debugPrint('WebDownloadService: Registering public URL for $targetPath');

        // Register direct URL
        _fileSystem.registerUrl(targetPath, url);

        // Simulate progress with cancellation checks
        const totalSteps = 20;
        const stepDelay = Duration(milliseconds: 50);

        for (int i = 0; i <= totalSteps; i++) {
          // Check cancellation on each step
          cancelToken?.throwIfCancelled();

          final progress = (i * 100 ~/ totalSteps).clamp(0, 100);
          yield progress;

          if (i < totalSteps) {
            await Future.delayed(stepDelay);
          }
        }

        debugPrint('WebDownloadService: Completed registration for $targetPath');
      } catch (e) {
        debugPrint('WebDownloadService: Registration failed for $targetPath: $e');
        if (e is ArgumentError || e is DownloadCancelledException) {
          rethrow;
        }
        throw DownloadException(
          DownloadError.unknown('Failed to register model URL: $e'),
        );
      }
    } else {
      // PRIVATE PATH: Fetch with auth
      debugPrint('WebDownloadService: Starting authenticated download for $targetPath');

      yield* _downloadWithAuth(url, targetPath, token, cancelToken);
    }
  }

  Stream<int> _downloadWithAuth(
    String url,
    String targetPath,
    String authToken,
    CancelToken? cancelToken,
  ) async* {
    try {
      // Check cancellation before starting
      cancelToken?.throwIfCancelled();

      var lastProgress = 0;

      final blobUrl = await _jsInterop.fetchWithAuthAndCreateBlob(
        url,
        authToken,
        onProgress: (progress) {
          // Convert 0.0-1.0 to 0-100
          final progressPercent = (progress * 100).clamp(0, 100).toInt();
          lastProgress = progressPercent;
        },
      );

      // Yield progress updates with cancellation checks
      for (int i = 0; i <= lastProgress; i += 5) {
        cancelToken?.throwIfCancelled();
        yield i;
        await Future.delayed(const Duration(milliseconds: 10));
      }

      cancelToken?.throwIfCancelled();
      yield 100;

      // Register blob URL
      _fileSystem.registerUrl(targetPath, blobUrl);
      _blobUrlManager.track(targetPath, blobUrl);

      debugPrint('WebDownloadService: Completed authenticated download for $targetPath');
      debugPrint('WebDownloadService: Blob URL created: $blobUrl');
    } on JsInteropException catch (e) {
      debugPrint('WebDownloadService: Authenticated download failed: $e');
      throw DownloadException(
        DownloadError.unknown('Failed to download authenticated model: $e'),
      );
    } on DownloadCancelledException {
      debugPrint('WebDownloadService: Download cancelled for $targetPath');
      rethrow;
    } catch (e) {
      debugPrint('WebDownloadService: Download failed for $targetPath: $e');
      throw DownloadException(
        DownloadError.unknown('Failed to download model: $e'),
      );
    }
  }
}
