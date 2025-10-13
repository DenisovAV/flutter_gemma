part of '../../../mobile/flutter_gemma_mobile.dart';

/// Model file for inference models (.bin, .task files)
class InferenceModelFile extends ModelFile {
  final ModelSource _source;
  final String _filename;

  InferenceModelFile({
    required ModelSource source,
    required String filename,
  })  : _source = source,
        _filename = filename;

  /// Creates InferenceModelFile from ModelSource
  factory InferenceModelFile.fromSource(ModelSource source) {
    final filename = _extractFilenameFromSource(source);
    return InferenceModelFile(source: source, filename: filename);
  }

  @override
  ModelSource get source => _source;

  @override
  String get filename => _filename;

  @override
  String get prefsKey => PreferencesKeys.installedModelFileName;

  @override
  bool get isRequired => true;

  static String _extractFilenameFromSource(ModelSource source) {
    return switch (source) {
      NetworkSource(:final url) => Uri.parse(url).pathSegments.last,
      AssetSource(:final path) => path.split('/').last,
      BundledSource(:final resourceName) => resourceName,
      FileSource(:final path) => path.split('/').last,
    };
  }
}

/// Model file for LoRA weights
class LoraModelFile extends ModelFile {
  final ModelSource _source;
  final String _filename;

  LoraModelFile({
    required ModelSource source,
    required String filename,
  })  : _source = source,
        _filename = filename;

  /// Creates LoraModelFile from ModelSource
  factory LoraModelFile.fromSource(ModelSource source) {
    final filename = InferenceModelFile._extractFilenameFromSource(source);
    return LoraModelFile(source: source, filename: filename);
  }

  @override
  ModelSource get source => _source;

  @override
  String get filename => _filename;

  @override
  String get prefsKey => PreferencesKeys.installedLoraFileName;

  @override
  bool get isRequired => false;
}

/// Specification for inference models (main model + optional LoRA)
class InferenceModelSpec extends ModelSpec {
  final String _name;
  final ModelSource _modelSource;
  final ModelSource? _loraSource;
  final ModelReplacePolicy _replacePolicy;
  final ModelType _modelType;
  final ModelFileType _fileType;

  InferenceModelSpec({
    required String name,
    required ModelSource modelSource,
    ModelSource? loraSource,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
  })  : _name = name,
        _modelSource = modelSource,
        _loraSource = loraSource,
        _replacePolicy = replacePolicy,
        _modelType = modelType,
        _fileType = fileType;

  /// Legacy compatibility constructor for String URLs
  factory InferenceModelSpec.fromLegacyUrl({
    required String name,
    required String modelUrl,
    String? loraUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
    ModelType modelType = ModelType.general,
    ModelFileType fileType = ModelFileType.task,
  }) {
    return InferenceModelSpec(
      name: name,
      modelSource: _urlToSource(modelUrl),
      loraSource: loraUrl != null ? _urlToSource(loraUrl) : null,
      replacePolicy: replacePolicy,
      modelType: modelType,
      fileType: fileType,
    );
  }

  @override
  ModelManagementType get type => ModelManagementType.inference;

  @override
  String get name => _name;

  @override
  ModelReplacePolicy get replacePolicy => _replacePolicy;

  @override
  List<ModelFile> get files {
    final result = <ModelFile>[
      InferenceModelFile.fromSource(_modelSource),
    ];

    if (_loraSource != null) {
      result.add(LoraModelFile.fromSource(_loraSource));
    }

    return result;
  }

  /// Modern type-safe getters
  ModelSource get modelSource => _modelSource;
  ModelSource? get loraSource => _loraSource;
  ModelType get modelType => _modelType;
  ModelFileType get fileType => _fileType;

  /// Legacy getters for backward compatibility (WEB PLATFORM ONLY)
  @Deprecated('Use modelSource instead. Web platform compatibility only.')
  String get modelUrl => _sourceToUrl(_modelSource);

  @Deprecated('Use loraSource instead. Web platform compatibility only.')
  String? get loraUrl => _loraSource != null ? _sourceToUrl(_loraSource) : null;

  /// Converts ModelSource to legacy URL string (for web platform compatibility)
  static String _sourceToUrl(ModelSource source) {
    return switch (source) {
      NetworkSource(:final url) => url,
      AssetSource(:final path) => 'asset://$path',
      BundledSource(:final resourceName) => 'native://$resourceName',
      FileSource(:final path) => 'file://$path',
    };
  }

  /// Converts legacy URL string to ModelSource (for fromLegacyUrl constructor)
  static ModelSource _urlToSource(String url) {
    if (url.startsWith('https://') || url.startsWith('http://')) {
      return ModelSource.network(url);
    } else if (url.startsWith('asset://')) {
      return ModelSource.asset(url.replaceFirst('asset://', ''));
    } else if (url.startsWith('native://')) {
      return ModelSource.bundled(url.replaceFirst('native://', ''));
    } else if (url.startsWith('file://')) {
      return ModelSource.file(url.replaceFirst('file://', ''));
    } else {
      // Schemeless = asset for backward compatibility
      return ModelSource.asset(url);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InferenceModelSpec) return false;

    return _name == other._name &&
        _modelSource == other._modelSource &&
        _loraSource == other._loraSource &&
        _replacePolicy == other._replacePolicy &&
        _modelType == other._modelType &&
        _fileType == other._fileType;
  }

  @override
  int get hashCode {
    return Object.hash(_name, _modelSource, _loraSource, _replacePolicy, _modelType, _fileType);
  }
}