part of '../../../mobile/flutter_gemma_mobile.dart';

/// Model file for inference models (.bin, .task files)
class InferenceModelFile extends ModelFile {
  final String _url;
  final String _filename;

  InferenceModelFile({
    required String url,
    required String filename,
  })  : _url = url,
        _filename = filename;

  @override
  String get url => _url;

  @override
  String get filename => _filename;

  @override
  String get prefsKey => 'installed_model_file_name';

  @override
  bool get isRequired => true;
}

/// Model file for LoRA weights
class LoraModelFile extends ModelFile {
  final String _url;
  final String _filename;

  LoraModelFile({
    required String url,
    required String filename,
  })  : _url = url,
        _filename = filename;

  @override
  String get url => _url;

  @override
  String get filename => _filename;

  @override
  String get prefsKey => 'installed_lora_file_name';

  @override
  bool get isRequired => false;
}

/// Specification for inference models (main model + optional LoRA)
class InferenceModelSpec extends ModelSpec {
  final String _name;
  final String _modelUrl;
  final String? _loraUrl;
  final ModelReplacePolicy _replacePolicy;

  InferenceModelSpec({
    required String name,
    required String modelUrl,
    String? loraUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  })  : _name = name,
        _modelUrl = modelUrl,
        _loraUrl = loraUrl,
        _replacePolicy = replacePolicy;

  @override
  ModelManagementType get type => ModelManagementType.inference;

  @override
  String get name => _name;

  @override
  ModelReplacePolicy get replacePolicy => _replacePolicy;

  @override
  List<ModelFile> get files {
    final result = <ModelFile>[
      InferenceModelFile(
        url: _modelUrl,
        filename: _extractFilename(_modelUrl),
      ),
    ];

    if (_loraUrl != null) {
      result.add(LoraModelFile(
        url: _loraUrl,
        filename: _extractFilename(_loraUrl),
      ));
    }

    return result;
  }

  /// Extract filename from URL
  static String _extractFilename(String url) {
    return Uri.parse(url).pathSegments.last;
  }

  /// Convenience getters for backward compatibility
  String get modelUrl => _modelUrl;
  String? get loraUrl => _loraUrl;
  String get modelFilename => _extractFilename(_modelUrl);
  String? get loraFilename => _loraUrl != null ? _extractFilename(_loraUrl) : null;
}