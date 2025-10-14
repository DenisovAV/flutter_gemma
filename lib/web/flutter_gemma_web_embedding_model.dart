import 'dart:async';
import 'package:flutter/foundation.dart';
import '../flutter_gemma_interface.dart';

class WebEmbeddingModel extends EmbeddingModel {
  WebEmbeddingModel({
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
    // TODO: Implement web embedding generation
    throw UnimplementedError('Web embedding generation not yet implemented');
  }

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    _assertNotClosed();
    // TODO: Implement web batch embedding generation
    throw UnimplementedError('Web batch embedding generation not yet implemented');
  }

  @override
  Future<int> getDimension() async {
    _assertNotClosed();
    // TODO: Implement getting dimension from web model
    throw UnimplementedError('Web embedding dimension not yet implemented');
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    onClose();
  }
}