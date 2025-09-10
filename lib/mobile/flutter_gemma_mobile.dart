import 'package:flutter_gemma/core/extensions.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_gemma/rag/embedding_models.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_downloader/background_downloader.dart';

import '../flutter_gemma.dart';

part 'flutter_gemma_mobile_model_manager.dart';
part 'flutter_gemma_mobile_inference_model.dart';

class MobileInferenceModelSession extends InferenceModelSession {
  final ModelType modelType;
  final VoidCallback onClose;
  final bool supportImage;
  bool _isClosed = false;

  Completer<void>? _responseCompleter;
  StreamController<String>? _asyncResponseController;
  StreamSubscription? _eventSubscription;

  MobileInferenceModelSession({
    required this.onClose,
    required this.modelType,
    this.supportImage = false,
  });

  void _assertNotClosed() {
    if (_isClosed) {
      throw Exception('Model is closed. Create a new instance to use it again');
    }
  }

  Future<void> _awaitLastResponse() async {
    if (_responseCompleter case Completer<void> completer) {
      await completer.future;
    }
  }

  @override
  Future<int> sizeInTokens(String text) => _platformService.sizeInTokens(text);

  @override
  Future<void> addQueryChunk(Message message) async {
    final finalPrompt = message.transformToChatPrompt(type: modelType);
    await _platformService.addQueryChunk(finalPrompt);
    if (message.hasImage && message.imageBytes != null && supportImage) {
      await _addImage(message.imageBytes!);
    }
  }

  Future<void> _addImage(Uint8List imageBytes) async {
    _assertNotClosed();
    if (!supportImage) {
      throw Exception('This model does not support images');
    }
    await _platformService.addImage(imageBytes);
  }

  @override
  Future<String> getResponse({Message? message}) async {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      if (message != null) {
        await addQueryChunk(message);
      }
      return await _platformService.generateResponse();
    } finally {
      completer.complete();
    }
  }

  @override
  Stream<String> getResponseAsync({Message? message}) async* {
    _assertNotClosed();
    await _awaitLastResponse();
    final completer = _responseCompleter = Completer<void>();
    try {
      final controller = _asyncResponseController = StreamController<String>();

      // Store subscription for proper cleanup
      _eventSubscription = eventChannel.receiveBroadcastStream().listen(
        (event) {
          // Check if controller is still open before adding events
          if (!controller.isClosed) {
            if (event is Map && event.containsKey('code') && event['code'] == "ERROR") {
              controller.addError(Exception(event['message'] ?? 'Unknown async error occurred'));
            } else if (event is Map && event.containsKey('partialResult')) {
              final partial = event['partialResult'] as String;
              controller.add(partial);
            } else {
              controller.addError(Exception('Unknown event type: $event'));
            }
          }
        },
        onError: (error, st) {
          if (!controller.isClosed) {
            controller.addError(error, st);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
        },
      );

      if (message != null) {
        await addQueryChunk(message);
      }
      unawaited(_platformService.generateResponseAsync());

      yield* controller.stream;
    } finally {
      completer.complete();
      _asyncResponseController = null;
    }
  }

  @override
  Future<void> stopGeneration() async {
    try {
      await _platformService.stopGeneration();
    } catch (e) {
      if (e.toString().contains('stop_not_supported')) {
        throw PlatformException(
          code: 'stop_not_supported',
          message: 'Stop generation is not supported on this platform',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;

    // Cancel event subscription first to stop receiving events
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    // Try to stop generation if possible (ignore errors on unsupported platforms)
    try {
      await _platformService.stopGeneration();
    } on PlatformException catch (e) {
      // Ignore "not supported" errors, but rethrow others
      if (e.code != 'stop_not_supported') {
        if (kDebugMode) {
          print('Warning: Failed to stop generation: ${e.message}');
        }
      }
    } catch (e) {
      // Ignore other errors during cleanup
      if (kDebugMode) {
        print('Warning: Unexpected error during stop generation: $e');
      }
    }

    // Close controller after stopping subscription
    _asyncResponseController?.close();

    onClose();
    await _platformService.closeSession();
  }
}

@visibleForTesting
const eventChannel = EventChannel('flutter_gemma_stream');

final _platformService = PlatformService();

class FlutterGemma extends FlutterGemmaPlugin {
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;

  @override
  late final MobileModelManager modelManager = MobileModelManager(
    onDeleteModel: _closeModelBeforeDeletion,
    onDeleteLora: _closeModelBeforeDeletion,
  );

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
  }) async {
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }

    final completer = _initCompleter = Completer<InferenceModel>();

    final (isModelInstalled, isLoraInstalled, File? modelFile, File? loraFile) = await (
      modelManager.isModelInstalled,
      modelManager.isLoraInstalled,
      modelManager._modelFile,
      modelManager._loraFile,
    ).wait;

    if (!isModelInstalled || modelFile == null) {
      completer.completeError(
        Exception('Gemma Model is not installed yet. Use the `modelManager` to load the model first'),
      );
      return completer.future;
    }

    try {
      await _platformService.createModel(
        maxTokens: maxTokens,
        modelPath: modelFile.path,
        loraRanks: loraRanks ?? supportedLoraRanks,
        preferredBackend: preferredBackend,
        maxNumImages: supportImage ? (maxNumImages ?? 1) : null,
      );

      final model = _initializedModel = MobileInferenceModel(
        maxTokens: maxTokens,
        modelType: modelType,
        modelManager: modelManager,
        preferredBackend: preferredBackend,
        supportedLoraRanks: loraRanks ?? supportedLoraRanks,
        supportImage: supportImage,
        maxNumImages: maxNumImages,
        onClose: () {
          _initializedModel = null;
          _initCompleter = null;
        },
      );

      completer.complete(model);
      return model;
    } catch (e, st) {
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> _closeModelBeforeDeletion() {
    return _initializedModel?.close() ?? Future.value();
  }

  // === RAG Methods Implementation ===

  @override
  Future<void> initializeEmbedding({
    required String modelPath,
    required String tokenizerPath,
    bool useGPU = true,
  }) async {
    await _platformService.initializeEmbedding(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      useGPU: useGPU,
    );
  }

  @override
  Future<void> closeEmbedding() async {
    await _platformService.closeEmbedding();
  }

  @override
  Future<List<double>> generateEmbedding(String text) async {
    return await _platformService.generateEmbedding(text);
  }

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    await _platformService.initializeVectorStore(databasePath);
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    await _platformService.addDocument(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadata,
    );
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    // Generate embedding for content first
    final embedding = await generateEmbedding(content);
    
    // Add document with computed embedding
    await addDocumentWithEmbedding(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadata,
    );
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
  }) async {
    // Generate embedding for query
    final queryEmbedding = await generateEmbedding(query);
    
    // Search similar vectors
    return await _platformService.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: topK,
      threshold: threshold,
    );
  }

  @override
  Future<VectorStoreStats> getVectorStoreStats() async {
    return await _platformService.getVectorStoreStats();
  }

  @override
  Future<void> clearVectorStore() async {
    await _platformService.clearVectorStore();
  }
}
