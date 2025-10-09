import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_gemma/model_file_manager_interface.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as path;

/// Fluent builder for inference model installation
///
/// Provides type-safe API for installing inference models with optional LoRA weights.
/// Automatically sets the installed model as the active inference model.
///
/// Usage:
/// ```dart
/// await FlutterGemma.installInferenceModel()
///   .fromNetwork('https://example.com/model.task', token: 'hf_...')
///   .withProgress((progress) => print('$progress%'))
///   .install();
/// ```
class InferenceInstallationBuilder {
  ModelSource? _modelSource;
  ModelSource? _loraSource;
  void Function(int progress)? _onProgress;

  /// Set model source from network URL (HTTP/HTTPS)
  ///
  /// Parameters:
  /// - [url]: The HTTP/HTTPS URL to download from
  /// - [token]: Optional authentication token (e.g., HuggingFace token)
  InferenceInstallationBuilder fromNetwork(String url, {String? token}) {
    _modelSource = ModelSource.network(url, authToken: token);
    return this;
  }

  /// Set model source from Flutter asset
  ///
  /// Path should be relative to assets directory.
  /// Handles 'assets/' prefix automatically.
  InferenceInstallationBuilder fromAsset(String path) {
    _modelSource = ModelSource.asset(path);
    return this;
  }

  /// Set model source from bundled native resource
  ///
  /// Platform-specific paths:
  /// - Android: assets/models/{resourceName}
  /// - iOS: Bundle.main.path(forResource:)
  /// - Web: /assets/{resourceName}
  InferenceInstallationBuilder fromBundled(String resourceName) {
    _modelSource = ModelSource.bundled(resourceName);
    return this;
  }

  /// Set model source from external file path
  ///
  /// File must exist at the specified absolute path.
  /// Use case: User-provided models via file picker
  InferenceInstallationBuilder fromFile(String path) {
    _modelSource = ModelSource.file(path);
    return this;
  }

  /// Optional: Add LoRA weights from custom source
  InferenceInstallationBuilder withLora(ModelSource loraSource) {
    _loraSource = loraSource;
    return this;
  }

  /// Convenience: Add LoRA weights from network URL
  InferenceInstallationBuilder withLoraFromNetwork(String url, {String? token}) {
    _loraSource = ModelSource.network(url, authToken: token);
    return this;
  }

  /// Convenience: Add LoRA weights from asset
  InferenceInstallationBuilder withLoraFromAsset(String path) {
    _loraSource = ModelSource.asset(path);
    return this;
  }

  /// Convenience: Add LoRA weights from bundled resource
  InferenceInstallationBuilder withLoraFromBundled(String resourceName) {
    _loraSource = ModelSource.bundled(resourceName);
    return this;
  }

  /// Convenience: Add LoRA weights from file
  InferenceInstallationBuilder withLoraFromFile(String path) {
    _loraSource = ModelSource.file(path);
    return this;
  }

  /// Add progress callback
  ///
  /// Called periodically during installation with progress percentage (0-100).
  InferenceInstallationBuilder withProgress(void Function(int progress) onProgress) {
    _onProgress = onProgress;
    return this;
  }

  /// Execute the installation and automatically set as active inference model
  ///
  /// Returns [InferenceInstallation] with details about installed model.
  ///
  /// Throws:
  /// - [StateError] if no model source configured
  /// - [Exception] on installation failure
  Future<InferenceInstallation> install() async {
    if (_modelSource == null) {
      throw StateError('Model source not configured. Use fromNetwork(), fromAsset(), fromBundled(), or fromFile().');
    }

    // Create spec
    final filename = _extractFilename(_modelSource!);
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(filename),
      modelSource: _modelSource!,
      loraSource: _loraSource,
      replacePolicy: ModelReplacePolicy.keep,
    );

    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;

    // Install model file
    final handler = handlerRegistry.getHandler(_modelSource!);
    if (_onProgress != null) {
      await for (final progress in handler!.installWithProgress(_modelSource!)) {
        _onProgress!(progress);
      }
    } else {
      await handler!.install(_modelSource!);
    }

    // Install LoRA if provided
    if (_loraSource != null) {
      final loraHandler = handlerRegistry.getHandler(_loraSource!);
      await loraHandler!.install(_loraSource!);
    }

    // AUTO-SET as active inference model
    final manager = FlutterGemmaPlugin.instance.modelManager;
    manager.setActiveModel(spec);

    debugPrint('✅ Inference model installed and set as active: ${spec.name}');

    return InferenceInstallation(spec: spec);
  }

  String _extractFilename(ModelSource source) {
    return switch (source) {
      NetworkSource(:final url) => path.basename(Uri.parse(url).path),
      AssetSource(:final path) => path.split('/').last,
      BundledSource(:final resourceName) => resourceName,
      FileSource(:final path) => path.split('/').last,
    };
  }
}

/// Result of inference model installation
class InferenceInstallation {
  final InferenceModelSpec spec;

  InferenceInstallation({required this.spec});

  /// Model ID (filename without extension)
  String get modelId => spec.name;

  /// Whether LoRA weights were installed
  bool get hasLora => spec.loraSource != null;
}
