import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';

/// Fluent builder for inference model installation
///
/// Provides type-safe API for installing inference models with optional LoRA weights.
/// Automatically sets the installed model as the active inference model.
///
/// Usage:
/// ```dart
/// await FlutterGemma.installModel(
///   modelType: ModelType.gemmaIt,
/// )
///   .fromNetwork('https://example.com/model.task', token: 'hf_...')
///   .withProgress((progress) => print('$progress%'))
///   .install();
/// ```
class InferenceInstallationBuilder {
  final ModelType _modelType;
  final ModelFileType _fileType;

  ModelSource? _modelSource;
  ModelSource? _loraSource;
  void Function(int progress)? _onProgress;
  CancelToken? _cancelToken;

  /// Create builder with model identity
  InferenceInstallationBuilder({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
  }) : _modelType = modelType,
       _fileType = fileType;

  /// Set model source from network URL (HTTP/HTTPS)
  ///
  /// Parameters:
  /// - [url]: The HTTP/HTTPS URL to download from
  /// - [token]: Optional authentication token (e.g., HuggingFace token)
  /// - [foreground]: Android foreground service mode (shows notification, no timeout)
  ///   - null (default): NO foreground service — this branch configures no
  ///     notification, and the platform needs one before it starts the service
  ///   - true: always use foreground
  ///   - false: never use foreground
  InferenceInstallationBuilder fromNetwork(
    String url, {
    String? token,
    bool? foreground,
  }) {
    _modelSource = ModelSource.network(
      url,
      authToken: token,
      foreground: foreground,
    );
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

  /// Set model source from a file in a Hugging Face repo.
  ///
  /// Builds `https://huggingface.co/<repo>/resolve/<revision>/<file>` and
  /// installs it via the network path — the plugin already applies the
  /// configured HuggingFace token to `huggingface.co` URLs for gated repos, so
  /// [token] is only needed to override it.
  ///
  /// Pass [file] explicitly, or take it from
  /// [FlutterGemma.resolveHuggingFace] when the repo ships a deployment
  /// manifest (`ResolvedHfModel.file`). [file] may contain `/` for a repo that
  /// nests variants in subfolders (e.g. `int4/model.litertlm`); each segment is
  /// URL-encoded independently so the path structure survives.
  InferenceInstallationBuilder fromHuggingFace(
    String repo, {
    required String file,
    String revision = 'main',
    String? token,
    bool? foreground,
  }) {
    // Fail loud at the seam — a resolver that returns an empty file, or an
    // empty repo, would otherwise build a directory URL that only 404s (or,
    // worse, saves a CDN error page as the model) far downstream.
    if (repo.trim().isEmpty) {
      throw ArgumentError.value(repo, 'repo', 'must be a non-empty "org/name"');
    }
    if (file.trim().isEmpty) {
      throw ArgumentError.value(
        file,
        'file',
        'must be a non-empty repo-relative path',
      );
    }
    final encodedPath = file.split('/').map(Uri.encodeComponent).join('/');
    final url = 'https://huggingface.co/$repo/resolve/$revision/$encodedPath';
    return fromNetwork(url, token: token, foreground: foreground);
  }

  /// Optional: Add LoRA weights from custom source
  InferenceInstallationBuilder withLora(ModelSource loraSource) {
    _loraSource = loraSource;
    return this;
  }

  /// Convenience: Add LoRA weights from network URL
  InferenceInstallationBuilder withLoraFromNetwork(
    String url, {
    String? token,
  }) {
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
  InferenceInstallationBuilder withProgress(
    void Function(int progress) onProgress,
  ) {
    _onProgress = onProgress;
    return this;
  }

  /// Set cancellation token for this installation
  ///
  /// The same token will be used for both model and LoRA downloads.
  ///
  /// Example:
  /// ```dart
  /// final cancelToken = CancelToken();
  ///
  /// final future = FlutterGemma.installModel(modelType: ModelType.gemmaIt)
  ///   .fromNetwork(url)
  ///   .withCancelToken(cancelToken)
  ///   .install();
  ///
  /// // Cancel from elsewhere
  /// cancelToken.cancel('User cancelled');
  /// ```
  InferenceInstallationBuilder withCancelToken(CancelToken cancelToken) {
    _cancelToken = cancelToken;
    return this;
  }

  /// Execute the installation and automatically set as active inference model
  ///
  /// Returns [InferenceInstallation] with details about installed model.
  ///
  /// Throws:
  /// - [StateError] if no model source configured
  /// - [DownloadCancelledException] if cancelled via cancelToken
  /// - [Exception] on installation failure
  ///
  /// Note: This method is idempotent - calling install() on an already-installed
  /// model will skip download and just set it as active.
  Future<InferenceInstallation> install() async {
    // Check cancellation before starting
    _cancelToken?.throwIfCancelled();

    if (_modelSource == null) {
      throw StateError(
        'Model source not configured. Use fromNetwork(), fromAsset(), fromBundled(), or fromFile().',
      );
    }

    // Built-in OS models: no file to install. Validate constraints, build the
    // spec, and persist the active identity without touching SourceHandlers
    // or ServiceRegistry (native side owns the model — nothing to download).
    if (_fileType == ModelFileType.builtIn) {
      if (_loraSource != null) {
        throw ArgumentError(
          'LoRA is not supported for built-in OS models (ModelFileType.builtIn).',
        );
      }
      final modelFile = InferenceModelFile.fromSource(_modelSource!);
      final spec = InferenceModelSpec(
        name: FileNameUtils.getBaseName(modelFile.filename),
        modelSource: _modelSource!,
        replacePolicy: ModelReplacePolicy.keep,
        modelType: _modelType,
        fileType: _fileType,
      );
      final manager = FlutterGemmaPlugin.instance.modelManager;
      manager.setActiveModel(spec);
      gemmaLog('✅ Built-in model set as active: ${spec.name}');
      return InferenceInstallation(spec: spec);
    }

    // ONNX on WEB: Transformers.js (@huggingface/transformers) resolves +
    // caches the whole Hugging Face repo itself from a repo id — the model
    // identity is a repo id, not a single downloadable file, so there is
    // nothing for a SourceHandler to fetch. Persist the active identity only,
    // exactly like the built-in path above. This is WEB-ONLY: on native, an
    // ONNX model is a real on-disk directory (genai_config.json + .onnx +
    // tokenizer) that DOES install through the handler path below, so the
    // fileless shortcut must never fire off-web.
    if (kIsWeb && _fileType == ModelFileType.onnx) {
      if (_loraSource != null) {
        throw ArgumentError(
          'LoRA is not supported for ONNX web models (ModelFileType.onnx).',
        );
      }
      final modelFile = InferenceModelFile.fromSource(_modelSource!);
      final spec = InferenceModelSpec(
        name: FileNameUtils.getBaseName(modelFile.filename),
        modelSource: _modelSource!,
        replacePolicy: ModelReplacePolicy.keep,
        modelType: _modelType,
        fileType: _fileType,
      );
      final manager = FlutterGemmaPlugin.instance.modelManager;
      manager.setActiveModel(spec);
      gemmaLog(
        '✅ ONNX web model set as active (Transformers.js owns the weights): '
        '${spec.name}',
      );
      return InferenceInstallation(spec: spec);
    }

    // Create spec
    final modelFile = InferenceModelFile.fromSource(_modelSource!);
    final spec = InferenceModelSpec(
      name: FileNameUtils.getBaseName(modelFile.filename),
      modelSource: _modelSource!,
      loraSource: _loraSource,
      replacePolicy: ModelReplacePolicy.keep,
      modelType: _modelType,
      fileType: _fileType,
    );

    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;

    // spec.files is [modelFile, loraFile?] in that fixed order (see
    // InferenceModelSpec.files) — reuse the ALREADY-namespaced identity
    // instead of recomputing a basename, so the isInstalled check and the
    // download target always agree.
    final files = spec.files;
    final namespacedModelFilename = files[0].filename;

    // Check if model is already installed
    final isInstalled = await repository.isInstalled(namespacedModelFilename);

    if (isInstalled) {
      gemmaLog(
        'ℹ️  Model already installed: $namespacedModelFilename (skipping download)',
      );
    } else {
      // Install model file
      final handlerRegistry = registry.sourceHandlerRegistry;
      final handler = handlerRegistry.getHandler(_modelSource!);
      if (_onProgress != null) {
        await for (final progress in handler!.installWithProgress(
          _modelSource!,
          cancelToken: _cancelToken,
          targetFilename: namespacedModelFilename,
        )) {
          _onProgress!(progress);
        }
      } else {
        await handler!.install(
          _modelSource!,
          cancelToken: _cancelToken,
          targetFilename: namespacedModelFilename,
        );
      }

      // Install LoRA if provided
      if (_loraSource != null) {
        final namespacedLoraFilename = files[1].filename;
        final loraHandler = handlerRegistry.getHandler(_loraSource!);
        await loraHandler!.install(
          _loraSource!,
          cancelToken: _cancelToken,
          targetFilename: namespacedLoraFilename,
        );
      }
    }

    // AUTO-SET as active inference model (even if already installed)
    final manager = FlutterGemmaPlugin.instance.modelManager;
    manager.setActiveModel(spec);

    gemmaLog('✅ Inference model installed and set as active: ${spec.name}');

    return InferenceInstallation(spec: spec);
  }
}

/// Result of inference model installation
class InferenceInstallation {
  final InferenceModelSpec spec;

  InferenceInstallation({required this.spec});

  /// Model ID (filename without extension)
  String get modelId => spec.name;

  /// Model type (gemmaIt, deepSeek, etc.)
  ModelType get modelType => spec.modelType;

  /// File type (task, binary)
  ModelFileType get fileType => spec.fileType;

  /// Whether LoRA weights were installed
  bool get hasLora => spec.loraSource != null;
}
