/// Web-platform service factory.
/// This file is only compiled on web platform.
/// Uses dart:js_interop for browser-based downloads.
library;

import 'package:shared_preferences/shared_preferences.dart';
import '../../infrastructure/web_download_service.dart';
import '../../infrastructure/web_file_system_service.dart';
import '../../infrastructure/web_js_interop.dart';
import '../../infrastructure/blob_url_manager.dart';
import '../../infrastructure/web_cache_service.dart';
import '../../infrastructure/web_cache_interop.dart';
import '../../services/download_service.dart';
import '../../services/file_system_service.dart';

/// Creates the default DownloadService for web platform
///
/// Web platform uses WebDownloadService with authenticated fetch
/// support via WebJsInterop, blob URL management, and Cache API
/// for persistent model storage.
///
/// The [fileSystem] parameter is required on web platform (must be WebFileSystemService).
/// The [enableCache] parameter controls whether models are cached persistently.
/// The [prefs] parameter must be pre-initialized SharedPreferences instance.
DownloadService createDownloadService(
  FileSystemService fileSystem,
  bool enableCache,
  SharedPreferences prefs,
) {
  // Cast to WebFileSystemService (guaranteed by ServiceRegistry validation)
  final webFs = fileSystem as WebFileSystemService;

  final jsInteropInstance = WebJsInterop();
  final blobManager = BlobUrlManager(jsInteropInstance, webFs);

  // Link cleanup callback
  webFs.setOnBlobUrlRemoved(blobManager.cleanupByUrl);

  // Create WebCacheService with pre-initialized SharedPreferences
  final cacheService = WebCacheService(
    WebCacheInterop(),
    prefs,
    webFs,
    enableCache: enableCache,
  );

  return WebDownloadService(webFs, jsInteropInstance, blobManager, cacheService);
}
