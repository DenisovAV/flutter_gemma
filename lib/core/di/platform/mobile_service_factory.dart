/// Mobile-platform service factory.
/// This file is only compiled on iOS/Android platforms.
/// Uses background_downloader for model downloads.
library;

import '../../infrastructure/background_downloader_service.dart';
import '../../services/download_service.dart';
import '../../services/file_system_service.dart';

/// Creates the default DownloadService for mobile platforms
///
/// Mobile platforms use BackgroundDownloaderService which handles
/// actual file downloads using native platform APIs.
///
/// The [fileSystem] parameter is optional and not used on mobile platforms,
/// as mobile uses BackgroundDownloaderService which doesn't need file system injection.
DownloadService createDownloadService([FileSystemService? fileSystem]) {
  return BackgroundDownloaderService();
}
