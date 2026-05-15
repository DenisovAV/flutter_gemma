// Web stub for `LitertEmbeddingModel`. Web has no dart:ffi support so the
// real implementation can't be compiled to JS/Wasm. The web plugin
// (FlutterGemmaWeb) registers itself as FlutterGemmaPlugin.instance via
// registerWith() before flutter_gemma_mobile.dart runs, so this stub is
// never called at runtime; it only exists to satisfy the compiler when
// dart2js builds the mobile entry point.

import '../../flutter_gemma_interface.dart' show EmbeddingModel, TaskType;

typedef VoidCallback = void Function();

class LitertEmbeddingModel extends EmbeddingModel {
  LitertEmbeddingModel._();

  static Future<LitertEmbeddingModel> create({
    required String modelPath,
    required String tokenizerPath,
    int? inputSequenceLength,
    int? outputDimension,
    VoidCallback? onClose,
  }) async {
    throw UnsupportedError(
        'LitertEmbeddingModel is not available on web — use FlutterGemmaWeb');
  }

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) =>
      throw UnsupportedError('stub');

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) =>
      throw UnsupportedError('stub');

  @override
  Future<int> getDimension() => throw UnsupportedError('stub');

  @override
  Future<void> close() async {}
}
