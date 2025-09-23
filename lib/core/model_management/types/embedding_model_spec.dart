part of '../../../mobile/flutter_gemma_mobile.dart';

/// Model file for embedding models (.bin files)
class EmbeddingModelFile extends ModelFile {
  final String _url;
  final String _filename;

  EmbeddingModelFile({
    required String url,
    required String filename,
  })  : _url = url,
        _filename = filename;

  @override
  String get url => _url;

  @override
  String get filename => _filename;

  @override
  String get prefsKey => 'embedding_model_file';

  @override
  bool get isRequired => true;
}

/// Tokenizer file for embedding models (.json files)
class EmbeddingTokenizerFile extends ModelFile {
  final String _url;
  final String _filename;

  EmbeddingTokenizerFile({
    required String url,
    required String filename,
  })  : _url = url,
        _filename = filename;

  @override
  String get url => _url;

  @override
  String get filename => _filename;

  @override
  String get prefsKey => 'embedding_tokenizer_file';

  @override
  bool get isRequired => true;
}

/// Specification for embedding models (model.bin + tokenizer.json)
class EmbeddingModelSpec extends ModelSpec {
  final String _name;
  final String _modelUrl;
  final String _tokenizerUrl;
  final ModelReplacePolicy _replacePolicy;

  EmbeddingModelSpec({
    required String name,
    required String modelUrl,
    required String tokenizerUrl,
    ModelReplacePolicy replacePolicy = ModelReplacePolicy.keep,
  })  : _name = name,
        _modelUrl = modelUrl,
        _tokenizerUrl = tokenizerUrl,
        _replacePolicy = replacePolicy;

  @override
  ModelManagementType get type => ModelManagementType.embedding;

  @override
  String get name => _name;

  @override
  ModelReplacePolicy get replacePolicy => _replacePolicy;

  @override
  List<ModelFile> get files => [
        EmbeddingModelFile(
          url: _modelUrl,
          filename: _extractFilename(_modelUrl),
        ),
        EmbeddingTokenizerFile(
          url: _tokenizerUrl,
          filename: _extractFilename(_tokenizerUrl),
        ),
      ];

  /// Extract filename from URL
  static String _extractFilename(String url) {
    return Uri.parse(url).pathSegments.last;
  }

  /// Convenience getters for backward compatibility
  String get modelUrl => _modelUrl;
  String get tokenizerUrl => _tokenizerUrl;
  String get modelFilename => _extractFilename(_modelUrl);
  String get tokenizerFilename => _extractFilename(_tokenizerUrl);
}