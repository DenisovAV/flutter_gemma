import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;
import 'package:flutter_gemma/flutter_gemma.dart';

/// Fluent builder for TTS (text-to-speech) model installation.
///
/// The model is a bundle of files (see [TtsModelType.manifest]) fetched from
/// one base source; install requires [fromNetwork] + [ofType]. Automatically
/// sets the installed model as the active TTS model.
///
/// Usage:
/// ```dart
/// await FlutterGemma.installTts()
///   .fromNetwork('https://example.com/matcha/', token: 'hf_...')
///   .ofType(TtsModelType.matcha)
///   .withProgress((p) => print('$p%'))
///   .install();
/// ```
class TtsInstallationBuilder {
  String? _baseUrl;
  String? _token;
  TtsModelType? _ttsModelType;
  String? _name;
  void Function(int overallPercent)? _onProgress;
  CancelToken? _cancelToken;

  /// Base URL the bundle files live under (each manifest filename is
  /// appended to it to derive the per-file network source).
  TtsInstallationBuilder fromNetwork(String baseUrl, {String? token}) {
    _baseUrl = baseUrl;
    _token = token;
    return this;
  }

  /// Set the TTS model family ([TtsModelType]) this install represents.
  ///
  /// Required — determines the manifest of files fetched from the base
  /// source, and carried on the installed [TtsModelSpec] so a single
  /// generic backend can select the right runtime profile.
  TtsInstallationBuilder ofType(TtsModelType ttsModelType) {
    _ttsModelType = ttsModelType;
    return this;
  }

  /// Override the installed spec's name. Defaults to [ttsModelType]'s name.
  TtsInstallationBuilder named(String name) {
    _name = name;
    return this;
  }

  /// Overall bundle install progress (0-100), across all manifest files.
  TtsInstallationBuilder withProgress(void Function(int overallPercent) cb) {
    _onProgress = cb;
    return this;
  }

  /// Set cancellation token for this installation.
  TtsInstallationBuilder withCancelToken(CancelToken cancelToken) {
    _cancelToken = cancelToken;
    return this;
  }

  /// Execute the installation and automatically set as active TTS model.
  ///
  /// Returns [TtsInstallation] with details about the installed model.
  ///
  /// Throws:
  /// - [StateError] if the base source or [ofType] was not configured
  /// - [DownloadCancelledException] if cancelled via cancelToken
  /// - [Exception] on installation failure
  ///
  /// Note: This method is idempotent - already-installed bundle files are
  /// skipped and the spec is just (re-)set as active.
  Future<TtsInstallation> install() async {
    _cancelToken?.throwIfCancelled();

    final baseUrl = _baseUrl;
    if (baseUrl == null) {
      throw StateError('Base source required. Use fromNetwork(baseUrl).');
    }
    final ttsModelType = _ttsModelType;
    if (ttsModelType == null) {
      throw StateError(
        'ofType(TtsModelType) is required, e.g. ofType(TtsModelType.matcha).',
      );
    }

    String joinUrl(String base, String fn) =>
        base.endsWith('/') ? '$base$fn' : '$base/$fn';

    final spec = TtsModelSpec.fromManifest(
      name: _name ?? ttsModelType.name,
      ttsModelType: ttsModelType,
      sourceFor: (fn) =>
          ModelSource.network(joinUrl(baseUrl, fn), authToken: _token),
    );

    final registry = ServiceRegistry.instance;
    final repository = registry.modelRepository;
    final fileSystem = registry.fileSystemService;
    final handlerRegistry = registry.sourceHandlerRegistry;

    final manifest = ttsModelType.manifest;
    // Only a bundle basename that is UNIQUE across the ENTIRE TTS catalog is
    // safe to adopt from a pre-refactor flat install: a shared basename (e.g. a
    // generic `config.json`) carries no type marker, so blindly adopting it
    // could hand THIS model another TTS model's file — the exact collision the
    // namespacing refactor fixes (see FileSystemService.adoptLegacyFile's
    // contract). Today matcha is the only type, so every basename is unique;
    // this guard keeps the adoption correct the moment a second TTS model
    // shares a basename (that basename then falls through to a fresh download).
    final catalogBasenameCounts = <String, int>{};
    for (final type in TtsModelType.values) {
      final List<String> typeManifest;
      try {
        typeManifest = type.manifest;
      } on UnimplementedError {
        // A not-yet-wired TTS type has no installed files, so it can't own a
        // colliding plain file — skip it rather than let its manifest getter
        // throw.
        continue;
      }
      for (final fn in typeManifest) {
        catalogBasenameCounts[fn] = (catalogBasenameCounts[fn] ?? 0) + 1;
      }
    }

    final files = spec.files;
    var done = 0;
    for (var i = 0; i < files.length; i++) {
      _cancelToken?.throwIfCancelled();
      final file = files[i];
      final legacyBasename = manifest[i];
      final adoptable = (catalogBasenameCounts[legacyBasename] ?? 0) == 1;

      if (await repository.isInstalled(file.filename)) {
        gemmaLog('ℹ️  TTS bundle file already installed: ${file.filename}');
      } else if (adoptable &&
          await fileSystem.adoptLegacyFile(legacyBasename, file.filename)) {
        gemmaLog(
          '♻️  Adopted legacy TTS bundle file: $legacyBasename -> ${file.filename}',
        );
        final newPath = await fileSystem.getWriteTargetPath(file.filename);
        final sizeBytes = await fileSystem.getFileSize(newPath);
        await repository.saveModel(
          repo.ModelInfo(
            id: file.filename,
            source: file.source,
            installedAt: DateTime.now(),
            sizeBytes: sizeBytes,
            type: repo.ModelType.tts,
            hasLoraWeights: false,
          ),
        );
      } else {
        gemmaLog('📥 Installing TTS bundle file: ${file.filename}...');
        final handler = handlerRegistry.getHandler(file.source);
        await handler!.install(
          file.source,
          cancelToken: _cancelToken,
          targetFilename: file.filename,
        );
      }
      done++;
      _onProgress?.call(((done / files.length) * 100).round());
    }

    // AUTO-SET as active TTS model (even if already installed).
    final manager = FlutterGemmaPlugin.instance.modelManager;
    manager.setActiveModel(spec);

    gemmaLog('✅ TTS model installed and set as active: ${spec.name}');

    return TtsInstallation(spec: spec);
  }
}

/// Result of TTS model installation.
class TtsInstallation {
  final TtsModelSpec spec;

  TtsInstallation({required this.spec});

  /// Model ID (bundle name).
  String get modelId => spec.name;
}
