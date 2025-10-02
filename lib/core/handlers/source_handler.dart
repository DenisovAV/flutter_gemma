import 'package:flutter_gemma/core/domain/model_source.dart';

/// Base interface for handling different model source types
/// Each source type (Network, Asset, Bundled, File) has its own handler implementation
///
/// This follows the Strategy pattern and allows for:
/// - Type-safe handling of each source type
/// - Dependency injection of platform-specific services
/// - Easy testing with mocks
/// - Extension with new source types without modifying existing code (OCP)
abstract interface class SourceHandler {
  /// Checks if this handler supports the given source type
  ///
  /// Example:
  /// ```dart
  /// final handler = NetworkSourceHandler(...);
  /// handler.supports(ModelSource.network('https://...')); // true
  /// handler.supports(ModelSource.asset('assets/...')); // false
  /// ```
  bool supports(ModelSource source);

  /// Installs the model from the given source
  ///
  /// This method performs the actual installation:
  /// - NetworkSource: downloads from URL
  /// - AssetSource: copies from Flutter assets
  /// - BundledSource: accesses native resources
  /// - FileSource: registers external file path
  ///
  /// Throws:
  /// - [UnsupportedError] if this handler doesn't support the source type
  /// - [ArgumentError] if the source is invalid
  /// - Platform-specific exceptions for download/file errors
  Future<void> install(ModelSource source);

  /// Installs the model with progress tracking
  ///
  /// Returns a stream of progress percentages (0-100)
  ///
  /// Note: Some sources may not support true progress:
  /// - AssetSource: simulates progress (copy is instant)
  /// - BundledSource: returns 100 immediately (no download)
  /// - FileSource: returns 100 immediately (just registration)
  ///
  /// Example:
  /// ```dart
  /// await for (final progress in handler.installWithProgress(source)) {
  ///   print('Progress: $progress%');
  /// }
  /// ```
  Stream<int> installWithProgress(ModelSource source);

  /// Checks if this source supports resume after interruption
  ///
  /// Only NetworkSource typically supports resume
  bool supportsResume(ModelSource source);
}
