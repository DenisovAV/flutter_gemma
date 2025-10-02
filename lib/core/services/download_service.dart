/// Abstraction for downloading files from network
/// Different implementations for different strategies
///
/// Platform implementations:
/// - BackgroundDownloaderService: uses background_downloader package
/// - SimpleDownloadService: uses http package
/// - MockDownloadService: for testing
abstract interface class DownloadService {
  /// Downloads a file from URL to target path
  ///
  /// Parameters:
  /// - [url]: Source URL (must be HTTP/HTTPS)
  /// - [targetPath]: Full path where file should be saved
  /// - [token]: Optional authentication token
  ///
  /// Throws:
  /// - [NetworkException] for network errors
  /// - [FileSystemException] for file write errors
  Future<void> download(String url, String targetPath, {String? token});

  /// Downloads a file with progress tracking
  ///
  /// Returns a stream of progress percentages (0-100)
  ///
  /// Example:
  /// ```dart
  /// await for (final progress in downloader.downloadWithProgress(...)) {
  ///   print('Progress: $progress%');
  /// }
  /// ```
  Stream<int> downloadWithProgress(String url, String targetPath, {String? token});

  /// Checks if a download task can be resumed
  ///
  /// Parameters:
  /// - [taskId]: ID of the download task
  ///
  /// Returns true if:
  /// - Task exists
  /// - Partial file exists
  /// - Server supports resume (ETag/Range headers)
  Future<bool> canResume(String taskId);

  /// Resumes a previously interrupted download
  ///
  /// Throws:
  /// - [UnsupportedError] if task cannot be resumed
  /// - [NetworkException] for network errors
  Future<void> resume(String taskId);

  /// Cancels an active download
  ///
  /// Does nothing if task doesn't exist or is already complete
  Future<void> cancel(String taskId);
}
