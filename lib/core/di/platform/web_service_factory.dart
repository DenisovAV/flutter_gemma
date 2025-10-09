/// Web-platform service factory.
/// This file is only compiled on web platform.
/// Uses dart:js_interop for browser-based downloads.
library;

import '../../infrastructure/web_download_service.dart';
import '../../infrastructure/web_file_system_service.dart';
import '../../infrastructure/web_js_interop.dart';
import '../../infrastructure/blob_url_manager.dart';
import '../../services/download_service.dart';

/// Creates the default DownloadService for web platform
///
/// Web platform uses WebDownloadService with authenticated fetch
/// support via WebJsInterop and blob URL management.
///
/// The [fileSystem] parameter is required on web platform.
/// Throws if not provided.
DownloadService createDownloadService([WebFileSystemService? fileSystem]) {
  if (fileSystem == null) {
    throw ArgumentError(
      'WebFileSystemService is required for web platform. '
      'This should never happen - bug in ServiceRegistry.',
    );
  }

  final jsInteropInstance = WebJsInterop();
  final blobManager = BlobUrlManager(jsInteropInstance, fileSystem);

  // Link cleanup callback
  fileSystem.setOnBlobUrlRemoved(blobManager.cleanupByUrl);

  return WebDownloadService(fileSystem, jsInteropInstance, blobManager);
}
