part of 'flutter_gemma_desktop.dart';

/// Desktop implementation of EmbeddingModel using TFLite C API via dart:ffi.
///
/// Loads a `.tflite` embedding model directly in the Dart process (no gRPC).
/// Auto-detects sequence length and embedding dimension from the model.
///
/// Pipeline: text → tokenize → add BOS/EOS → pad → Int32 tensor → invoke → Float32 embedding
class DesktopEmbeddingModel extends EmbeddingModel {
  DesktopEmbeddingModel({
    required TfLiteInterpreter interpreter,
    required this.tokenize,
    required this.onClose,
  }) : _interpreter = interpreter;

  final TfLiteInterpreter _interpreter;

  /// Tokenization function: text → list of token IDs.
  /// Injected to decouple model from tokenizer implementation.
  final List<int> Function(String text) tokenize;

  final VoidCallback onClose;
  bool _isClosed = false;

  static const String _queryPrefix = 'task: search result | query: ';
  static const String _docPrefix = 'title: none | text: ';

  /// Gemma standard special token IDs.
  /// dart_sentencepiece_tokenizer defaults to bosId=1/eosId=2 (swapped),
  /// so we add them manually with the correct IDs.
  static const int _bosId = 2;
  static const int _eosId = 1;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
          'EmbeddingModel is closed. Create a new instance to use it again');
    }
  }

  /// Tokenize text with prefix, add BOS/EOS with correct Gemma IDs.
  List<int> _prepareTokens(String text, {required TaskType taskType}) {
    final prefix =
        taskType == TaskType.retrievalDocument ? _docPrefix : _queryPrefix;
    final fullText = prefix + text;
    final tokens = tokenize(fullText);
    return [_bosId, ...tokens, _eosId];
  }

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    _assertNotClosed();
    final tokens = _prepareTokens(text, taskType: taskType);
    return _interpreter.run(tokens);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    _assertNotClosed();
    return texts.map((text) {
      final tokens = _prepareTokens(text, taskType: taskType);
      return _interpreter.run(tokens);
    }).toList();
  }

  @override
  Future<int> getDimension() async {
    _assertNotClosed();
    return _interpreter.outputDimension;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    try {
      _interpreter.close();
    } finally {
      onClose();
    }
  }
}
