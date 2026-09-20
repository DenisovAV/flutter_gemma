// Web stub for `CommonEmbeddingModel`. Web has no dart:ffi support so the
// real (isolate + native forward-pass) implementation can't be compiled to
// JS/Wasm. The web plugin (FlutterGemmaWeb) registers its own web embedding
// backend before flutter_gemma_mobile.dart runs, so this stub is never
// called at runtime; it only exists to satisfy the compiler when dart2js/
// dart2wasm builds the mobile entry point.

import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show EmbeddingModel, TaskType;
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';

import 'forward_pass.dart';

typedef VoidCallback = void Function();

class CommonEmbeddingModel extends EmbeddingModel with CloseNotifier {
  CommonEmbeddingModel._();

  static Future<CommonEmbeddingModel> create({
    required ForwardPassDescriptor descriptor,
    required String tokenizerPath,
    VoidCallback? onClose,
  }) async {
    throw UnsupportedError(
      'CommonEmbeddingModel is not available on web — use the web-specific '
      'embedding backend',
    );
  }

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) => throw UnsupportedError('stub');

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) => throw UnsupportedError('stub');

  @override
  Future<int> getDimension() => throw UnsupportedError('stub');

  @override
  Future<void> close() async {}
}
