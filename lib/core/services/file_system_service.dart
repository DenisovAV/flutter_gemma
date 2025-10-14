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

  /// Gets the target path for storing a model file with given filename
  ///
  /// This returns the full path where the file should be stored,
  /// typically in the app's documents directory
  ///
  /// Example: '/data/data/com.app/files/model.bin'
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
}
