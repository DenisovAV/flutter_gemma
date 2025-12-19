part of 'flutter_gemma_mobile.dart';

class MobileEmbeddingModel extends EmbeddingModel {
  MobileEmbeddingModel({
    required this.onClose,
  });

  final VoidCallback onClose;
  bool _isClosed = false;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('EmbeddingModel is closed. Create a new instance to use it again');
    }
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    _assertNotClosed();
    return await _platformService.generateEmbeddingFromModel(text);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    _assertNotClosed();
    final result = await _platformService.generateEmbeddingsFromModel(texts);
    // Deep cast: platform channel returns List<Object?> with inner List<Object?>
    return result.map((inner) => (inner as List).cast<double>()).toList();
  }

  @override
  Future<int> getDimension() async {
    _assertNotClosed();
    return await _platformService.getEmbeddingDimension();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    await _platformService.closeEmbeddingModel();
    onClose();
  }
}
