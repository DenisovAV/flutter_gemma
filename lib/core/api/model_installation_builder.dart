import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/api/model_installation.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';

/// Fluent builder for model installation
///
/// Provides type-safe, readable API for installing models from various sources.
///
/// Usage:
/// ```dart
/// final installation = await FlutterGemma.installModel()
///   .fromNetwork('https://example.com/model.bin')
///   .withProgress((progress) => print('$progress%'))
///   .install();
/// ```
class ModelInstallationBuilder {
  ModelSource? _source;
  void Function(int progress)? _onProgress;

  /// Install from network URL (HTTP/HTTPS)
  ///
  /// Supports:
  /// - Progress tracking
  /// - Resume on interruption
  /// - HuggingFace authentication (configured via ServiceRegistry or explicit token)
  ///
  /// Parameters:
  /// - [url]: The HTTP/HTTPS URL to download from
  /// - [token]: Optional authentication token (e.g., HuggingFace token)
  ModelInstallationBuilder fromNetwork(String url, {String? token}) {
    _source = ModelSource.network(url, authToken: token);
    return this;
  }

  /// Install from Flutter asset
  ///
  /// Path should be relative to assets directory.
  /// Handles 'assets/' prefix automatically.
  ///
  /// Example: 'models/gemma.bin' or 'assets/models/gemma.bin'
  ModelInstallationBuilder fromAsset(String path) {
    _source = ModelSource.asset(path);
    return this;
  }

  /// Install from bundled native resource
  ///
  /// Platform-specific paths:
  /// - Android: assets/models/{resourceName}
  /// - iOS: Bundle.main.path(forResource:)
  /// - Web: /assets/{resourceName}
  ModelInstallationBuilder fromBundled(String resourceName) {
    _source = ModelSource.bundled(resourceName);
    return this;
  }

  /// Install from external file path
  ///
  /// File must exist at the specified path.
  /// Path must be absolute.
  /// File is protected from cleanup operations.
  ///
  /// Use case: User-provided models via file picker
  ModelInstallationBuilder fromFile(String path) {
    _source = ModelSource.file(path);
    return this;
  }

  /// Add progress callback
  ///
  /// Called periodically during installation with progress percentage (0-100).
  /// Not all sources support granular progress (assets/bundled/file report 100% at completion).
  ModelInstallationBuilder withProgress(void Function(int progress) onProgress) {
    _onProgress = onProgress;
    return this;
  }

  /// Execute the installation
  ///
  /// Returns [ModelInstallation] which can be used to load the model for inference.
  ///
  /// Throws:
  /// - [StateError] if no source configured
  /// - [Exception] on installation failure
  Future<ModelInstallation> install() async {
    if (_source == null) {
      throw StateError('No model source configured. Use fromNetwork(), fromAsset(), fromBundled(), or fromFile().');
    }

    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;
    final handler = handlerRegistry.getHandler(_source!);

    if (_onProgress != null) {
      // Use progress tracking when callback provided
      try {
        await for (final progress in handler!.installWithProgress(_source!)) {
          _onProgress!(progress);
        }
      } catch (e) {
        // Re-throw to ensure errors propagate correctly
        rethrow;
      }
    } else {
      // Simple install without progress
      await handler!.install(_source!);
    }

    return ModelInstallation(source: _source!);
  }
}
