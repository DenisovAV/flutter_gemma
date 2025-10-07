import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_gemma/model_file_manager_interface.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as path;

/// Fluent builder for embedding model installation
///
/// Provides type-safe API for installing embedding models (requires model + tokenizer).
/// Automatically sets the installed model as the active embedding model.
///
/// Usage:
/// ```dart
/// await FlutterGemma.installEmbeddingModel()
///   .modelFromNetwork('https://example.com/model.tflite', token: 'hf_...')
///   .tokenizerFromNetwork('https://example.com/tokenizer.model', token: 'hf_...')
///   .withModelProgress((p) => print('Model: $p%'))
///   .withTokenizerProgress((p) => print('Tokenizer: $p%'))
///   .install();
/// ```
class EmbeddingInstallationBuilder {
  ModelSource? _modelSource;
  ModelSource? _tokenizerSource;
  void Function(int progress)? _onModelProgress;
  void Function(int progress)? _onTokenizerProgress;

  // === Model source setters ===

  /// Set model source from network URL (HTTP/HTTPS)
  EmbeddingInstallationBuilder modelFromNetwork(String url, {String? token}) {
    _modelSource = ModelSource.network(url, authToken: token);
    return this;
  }

  /// Set model source from Flutter asset
  EmbeddingInstallationBuilder modelFromAsset(String path) {
    _modelSource = ModelSource.asset(path);
    return this;
  }

  /// Set model source from bundled native resource
  EmbeddingInstallationBuilder modelFromBundled(String resourceName) {
    _modelSource = ModelSource.bundled(resourceName);
    return this;
  }

  /// Set model source from external file path
  EmbeddingInstallationBuilder modelFromFile(String path) {
    _modelSource = ModelSource.file(path);
    return this;
  }

  // === Tokenizer source setters ===

  /// Set tokenizer source from network URL (HTTP/HTTPS)
  EmbeddingInstallationBuilder tokenizerFromNetwork(String url, {String? token}) {
    _tokenizerSource = ModelSource.network(url, authToken: token);
    return this;
  }

  /// Set tokenizer source from Flutter asset
  EmbeddingInstallationBuilder tokenizerFromAsset(String path) {
    _tokenizerSource = ModelSource.asset(path);
    return this;
  }

  /// Set tokenizer source from bundled native resource
  EmbeddingInstallationBuilder tokenizerFromBundled(String resourceName) {
    _tokenizerSource = ModelSource.bundled(resourceName);
    return this;
  }

  /// Set tokenizer source from external file path
  EmbeddingInstallationBuilder tokenizerFromFile(String path) {
    _tokenizerSource = ModelSource.file(path);
    return this;
  }

  // === Progress callbacks ===

  /// Add model file progress callback
  EmbeddingInstallationBuilder withModelProgress(void Function(int progress) onProgress) {
    _onModelProgress = onProgress;
    return this;
  }

  /// Add tokenizer file progress callback
  EmbeddingInstallationBuilder withTokenizerProgress(void Function(int progress) onProgress) {
    _onTokenizerProgress = onProgress;
    return this;
  }

  /// Execute the installation and automatically set as active embedding model
  ///
  /// Returns [EmbeddingInstallation] with details about installed model.
  ///
  /// Throws:
  /// - [StateError] if model or tokenizer source not configured
  /// - [Exception] on installation failure
  Future<EmbeddingInstallation> install() async {
    if (_modelSource == null || _tokenizerSource == null) {
      throw StateError(
        'Both model and tokenizer required. Use modelFromNetwork() and tokenizerFromNetwork().',
      );
    }

    // Create spec
    final modelFilename = _extractFilename(_modelSource!);

    final spec = EmbeddingModelSpec(
      name: modelFilename.split('.').first,
      modelSource: _modelSource!,
      tokenizerSource: _tokenizerSource!,
      replacePolicy: ModelReplacePolicy.keep,
    );

    final registry = ServiceRegistry.instance;
    final handlerRegistry = registry.sourceHandlerRegistry;

    // Install model file
    debugPrint('📥 Installing embedding model...');
    final modelHandler = handlerRegistry.getHandler(_modelSource!);
    if (_onModelProgress != null) {
      await for (final progress in modelHandler!.installWithProgress(_modelSource!)) {
        _onModelProgress!(progress);
      }
    } else {
      await modelHandler!.install(_modelSource!);
    }

    // Install tokenizer file
    debugPrint('📥 Installing tokenizer...');
    final tokenizerHandler = handlerRegistry.getHandler(_tokenizerSource!);
    if (_onTokenizerProgress != null) {
      await for (final progress in tokenizerHandler!.installWithProgress(_tokenizerSource!)) {
        _onTokenizerProgress!(progress);
      }
    } else {
      await tokenizerHandler!.install(_tokenizerSource!);
    }

    // AUTO-SET as active embedding model
    final manager = FlutterGemmaPlugin.instance.modelManager;
    manager.setActiveModel(spec);

    debugPrint('✅ Embedding model installed and set as active: ${spec.name}');

    return EmbeddingInstallation(spec: spec);
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

/// Result of embedding model installation
class EmbeddingInstallation {
  final EmbeddingModelSpec spec;

  EmbeddingInstallation({required this.spec});

  /// Model ID (filename without extension)
  String get modelId => spec.name;
}
