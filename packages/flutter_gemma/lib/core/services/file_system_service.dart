import 'dart:typed_data';

/// Abstraction for file system operations
/// Allows different implementations for different platforms (mobile/web)
/// and easy mocking in tests
///
/// Platform implementations:
/// - PlatformFileSystemService: uses dart:io for mobile
/// - WebFileSystemService: uses IndexedDB/LocalStorage for web
abstract interface class FileSystemService {
  /// Writes data to a file at the given path
  ///
  /// Creates parent directories if they don't exist
  ///
  /// Throws:
  /// - [FileSystemException] if write fails
  Future<void> writeFile(String path, Uint8List data);

  /// Reads data from a file at the given path
  ///
  /// Throws:
  /// - [FileSystemException] if file doesn't exist or read fails
  Future<Uint8List> readFile(String path);

  /// Deletes a file at the given path
  ///
  /// Does nothing if file doesn't exist
  ///
  /// Throws:
  /// - [FileSystemException] if delete fails
  Future<void> deleteFile(String path);

  /// Checks if a file exists at the given path
  Future<bool> fileExists(String path);

  /// Gets the size of a file in bytes
  ///
  /// Returns 0 if file doesn't exist
  Future<int> getFileSize(String path);

  /// Gets the target path for storing a model file with given filename.
  ///
  /// Returns the canonical write destination (no legacy probe). Writers
  /// must use this method so that files always land in the correct location
  /// and never accidentally migrate to the legacy Documents path.
  ///
  /// Example: '/data/data/com.app/files/model.bin'
  Future<String> getWriteTargetPath(String filename);

  /// Gets the path for reading a model file with given filename.
  ///
  /// On desktop (macOS/Windows/Linux) performs a legacy-Documents fallback
  /// probe so that models installed before 0.15.1 (which stored everything
  /// in `~/Documents/`) continue to load on upgrade without a forced
  /// re-install. A single debug log is emitted per unique legacy path to
  /// nudge the user to re-install.
  ///
  /// Writers must use [getWriteTargetPath] instead.
  Future<String> getReadTargetPath(String filename);

  /// Deprecated. Use [getReadTargetPath] for reads or [getWriteTargetPath]
  /// for writes to route paths correctly.
  @Deprecated(
    'Use getReadTargetPath for reads or getWriteTargetPath for writes',
  )
  Future<String> getTargetPath(String filename);

  /// Gets the path to a bundled native resource
  ///
  /// This is platform-specific:
  /// - Android: assets/models/{resourceName}
  /// - iOS: Bundle.main.path(forResource:)
  /// - Web: /assets/{resourceName}
  ///
  /// Throws:
  /// - [UnsupportedError] if bundled resources not supported
  /// - [FileSystemException] if resource not found
  Future<String> getBundledResourcePath(String resourceName);

  /// Registers an external file path (for FileSource)
  ///
  /// This marks the file as external so it won't be cleaned up
  /// The actual path mapping is stored in ProtectedFilesRegistry
  Future<void> registerExternalFile(String filename, String externalPath);

  /// Returns the canonical directory where model files are stored.
  ///
  /// On mobile this is the app's Documents directory; on desktop it is the
  /// platform-appropriate Application Support subdirectory that avoids
  /// cloud-synced paths (see [PlatformFileSystemService._getDocumentsDirectory]).
  ///
  /// Returns the directory path as a [String] so that this interface remains
  /// usable without importing [dart:io] (which is unavailable on Web).
  ///
  /// Throws [UnsupportedError] on Web (no local file system).
  Future<String> getModelStorageDirectory();
}
