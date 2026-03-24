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
  })  : _interpreter = interpreter;

  final TfLiteInterpreter _interpreter;

  /// Tokenization function: text → list of token IDs.
  /// Injected to decouple model from tokenizer implementation.
  final List<int> Function(String text) tokenize;

  final VoidCallback onClose;
  bool _isClosed = false;

  static const String _taskPrefix = 'task: search result | query: ';

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError(
          'EmbeddingModel is closed. Create a new instance to use it again');
    }
  }

  /// Tokenize text with task prefix.
  /// BOS/EOS are added by the tokenizer via SentencePieceConfig.gemma.
  List<int> _prepareTokens(String text) {
    final fullText = _taskPrefix + text;
    return tokenize(fullText);
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    _assertNotClosed();
    final tokens = _prepareTokens(text);
    return _interpreter.run(tokens);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    _assertNotClosed();
    return texts.map((text) {
      final tokens = _prepareTokens(text);
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
    _interpreter.close();
    onClose();
  }
}
