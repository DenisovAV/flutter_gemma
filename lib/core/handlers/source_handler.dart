import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';

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
  /// Parameters:
  /// - [source]: The model source to install from
  /// - [cancelToken]: Optional token for cancelling the installation
  ///
  /// Throws:
  /// - [UnsupportedError] if this handler doesn't support the source type
  /// - [ArgumentError] if the source is invalid
  /// - [DownloadCancelledException] if cancelled via cancelToken
  /// - Platform-specific exceptions for download/file errors
  Future<void> install(
    ModelSource source, {
    CancelToken? cancelToken,
  });

  /// Installs the model with progress tracking
  ///
  /// Returns a stream of progress percentages (0-100)
  ///
  /// Parameters:
  /// - [source]: The model source to install from
  /// - [cancelToken]: Optional token for cancelling the installation
  ///
  /// Note: Some sources may not support true progress:
  /// - AssetSource: simulates progress (copy is instant)
  /// - BundledSource: returns 100 immediately (no download)
  /// - FileSource: returns 100 immediately (just registration)
  ///
  /// Example:
  /// ```dart
  /// final cancelToken = CancelToken();
  ///
  /// try {
  ///   await for (final progress in handler.installWithProgress(
  ///     source,
  ///     cancelToken: cancelToken,
  ///   )) {
  ///     print('Progress: $progress%');
  ///   }
  /// } catch (e) {
  ///   if (CancelToken.isCancel(e)) {
  ///     print('Installation cancelled');
  ///   }
  /// }
  /// ```
  ///
  /// Throws:
  /// - [DownloadCancelledException] if cancelled via cancelToken
  Stream<int> installWithProgress(
    ModelSource source, {
    CancelToken? cancelToken,
  });

  /// Checks if this source supports resume after interruption
  ///
  /// Only NetworkSource typically supports resume
  bool supportsResume(ModelSource source);
}
