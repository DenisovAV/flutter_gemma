import 'dart:async';
import 'package:flutter/foundation.dart';
import '../flutter_gemma_interface.dart';
import 'litert_web_embeddings.dart';

class WebEmbeddingModel extends EmbeddingModel {
  WebEmbeddingModel({
    required this.onClose,
    String? modelPath,
    String? tokenizerPath,
  })  : _modelPath = modelPath,
        _tokenizerPath = tokenizerPath;

  final VoidCallback onClose;
  final String? _modelPath;
  final String? _tokenizerPath;
  bool _isClosed = false;
  bool _isInitialized = false;

  // Public getters for parameter comparison
  String? get modelPath => _modelPath;
  String? get tokenizerPath => _tokenizerPath;

  void _assertNotClosed() {
    if (_isClosed) {
      throw StateError('EmbeddingModel is closed. Create a new instance to use it again');
    }
  }

  /// Initialize the LiteRT model if not already initialized
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    if (_modelPath == null || _tokenizerPath == null) {
      throw StateError(
          'Model and tokenizer paths must be provided. Use createEmbeddingModel with modelPath and tokenizerPath parameters.');
    }

    try {
      await LiteRTWebEmbeddings.initialize(
        _modelPath,
        _tokenizerPath,
        wasmPath: '/wasm/', // WASM files in example/web/wasm/
      );
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('✅ LiteRT embeddings initialized successfully');
      }
    } catch (e) {
      throw Exception('Failed to initialize LiteRT embeddings: $e');
    }
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    _assertNotClosed();
    await _ensureInitialized();

    try {
      return await LiteRTWebEmbeddings.generateEmbedding(text);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to generate embedding: $e');
      }
      rethrow;
    }
  }

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    _assertNotClosed();
    await _ensureInitialized();

    try {
      final embeddings = await LiteRTWebEmbeddings.generateEmbeddings(texts);
      if (kDebugMode) {
        debugPrint('✅ Generated ${embeddings.length} embeddings');
      }
      return embeddings;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to generate embeddings: $e');
      }
      rethrow;
    }
  }

  @override
  Future<int> getDimension() async {
    _assertNotClosed();
    // Don't need to initialize just to get dimension (it's a constant)
    return LiteRTWebEmbeddings.getDimension();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;

    // Cleanup LiteRT resources
    if (_isInitialized) {
      try {
        await LiteRTWebEmbeddings.dispose();
        if (kDebugMode) {
          debugPrint('✅ LiteRT embeddings disposed');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️  Warning: Failed to dispose LiteRT embeddings: $e');
        }
      }
    }

    onClose();
  }
}
