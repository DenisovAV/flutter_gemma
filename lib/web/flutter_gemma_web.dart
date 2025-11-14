import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_download_service.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'llm_inference_web.dart';
import 'flutter_gemma_web_embedding_model.dart';

part '../core/model_management/managers/web_model_manager.dart';

/// Base class for prompt parts (text, image, audio)
abstract class PromptPart {}

/// Text prompt part
class TextPromptPart extends PromptPart {
  final String text;
  TextPromptPart(this.text);
}

/// Image prompt part with data URL
class ImagePromptPart extends PromptPart {
  final String dataUrl;
  ImagePromptPart(this.dataUrl);

  /// Create ImagePromptPart from Uint8List bytes
  factory ImagePromptPart.fromBytes(Uint8List bytes) {
    final base64String = base64Encode(bytes);
    final mimeType = _detectImageFormat(bytes);
    final dataUrl = 'data:$mimeType;base64,$base64String';
    return ImagePromptPart(dataUrl);
  }

  /// Detect image format from header bytes
  static String _detectImageFormat(Uint8List bytes) {
    if (bytes.length < 4) return 'image/png'; // default fallback

    // JPEG magic number: FF D8 FF
    if (_matchesSignature(bytes, [0xFF, 0xD8, 0xFF])) {
      return 'image/jpeg';
    }

    // PNG magic number: 89 50 4E 47
    if (_matchesSignature(bytes, [0x89, 0x50, 0x4E, 0x47])) {
      return 'image/png';
    }

    // WebP magic number: RIFF at start, WEBP at offset 8
    if (bytes.length >= 12 &&
        _matchesSignature(bytes, [0x52, 0x49, 0x46, 0x46]) &&
        _matchesSignature(bytes.sublist(8), [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }

    return 'image/png'; // default fallback
  }

  /// Check if bytes match a signature at the beginning
  static bool _matchesSignature(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (int i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }
}

class FlutterGemmaWeb extends FlutterGemmaPlugin {
  FlutterGemmaWeb();

  static void registerWith(Registrar registrar) {
    FlutterGemmaPlugin.instance = FlutterGemmaWeb();
  }

  // Use WebModelManager singleton (will be replaced with platform-agnostic manager in future phases)
  static WebModelManager? _webManager;

  @override
  ModelFileManager get modelManager {
    // Use WebModelManager for now (Phase 6 will migrate to fully unified approach)
    _webManager ??= WebModelManager();
    return _webManager!;
  }

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  EmbeddingModel? get initializedEmbeddingModel => _initializedEmbeddingModel;

  InferenceModel? _initializedModel;
  EmbeddingModel? _initializedEmbeddingModel;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false, // Enabling image support
  }) {
    // TODO: Implement multimodal support for web
    if (supportImage || maxNumImages != null) {
      if (kDebugMode) {
        debugPrint('Warning: Image support is not yet implemented for web platform');
      }
    }

    final model = _initializedModel ??= WebInferenceModel(
      modelType: modelType,
      fileType: fileType,
      maxTokens: maxTokens,
      loraRanks: loraRanks,
      modelManager:
          modelManager as WebModelManager, // Use the same instance from FlutterGemmaPlugin.instance
      supportImage: supportImage, // Passing the flag
      maxNumImages: maxNumImages,
      onClose: () {
        _initializedModel = null;
      },
    );
    return Future.value(model);
  }

  // === EmbeddingModel Methods - Web Implementation ===

  @override
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  }) async {
    // Modern API: Use active embedding model if paths not provided
    if (modelPath == null || tokenizerPath == null) {
      final manager = modelManager as WebModelManager;
      final activeModel = manager.activeEmbeddingModel;

      // No active embedding model - user must set one first
      if (activeModel == null) {
        throw StateError(
            'No active embedding model set. Use `FlutterGemma.installEmbedder()` or `modelManager.setActiveModel()` to set a model first');
      }

      // Get the actual model file paths through unified system
      final modelFilePaths = await manager.getModelFilePaths(activeModel);
      if (modelFilePaths == null || modelFilePaths.isEmpty) {
        throw StateError(
            'Embedding model file paths not found. Use the `modelManager` to load the model first');
      }

      // Extract model and tokenizer paths from spec
      final activeModelPath = modelFilePaths[PreferencesKeys.embeddingModelFile];
      final activeTokenizerPath = modelFilePaths[PreferencesKeys.embeddingTokenizerFile];

      if (activeModelPath == null || activeTokenizerPath == null) {
        throw StateError('Could not find model or tokenizer path in active embedding model');
      }

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      if (kDebugMode) {
        debugPrint('Using active embedding model: $modelPath, tokenizer: $tokenizerPath');
      }
    }

    // Create or return existing model instance
    // Note: preferredBackend is ignored on web (LiteRT.js uses WebGPU when available)
    final model = _initializedEmbeddingModel ??= WebEmbeddingModel(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      onClose: () {
        _initializedEmbeddingModel = null;
      },
    );
    return Future.value(model);
  }

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
  }) async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<VectorStoreStats> getVectorStoreStats() async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }

  @override
  Future<void> clearVectorStore() async {
    throw UnimplementedError('RAG is not supported on web platform yet');
  }
}

class WebInferenceModel extends InferenceModel {
  final VoidCallback onClose;
  @override
  final int maxTokens;

  final ModelType modelType;
  @override
  final ModelFileType fileType;
  final List<int>? loraRanks;
  final WebModelManager modelManager;
  final bool supportImage; // Enabling image support
  final int? maxNumImages;
  Completer<InferenceModelSession>? _initCompleter;
  @override
  InferenceModelSession? session;

  WebInferenceModel({
    required this.modelType,
    this.fileType = ModelFileType.task,
    required this.onClose,
    required this.maxTokens,
    this.loraRanks,
    required this.modelManager,
    this.supportImage = false,
    this.maxNumImages,
  });

  @override
  Future<InferenceModelSession> createSession({
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Enabling vision modality support
  }) async {
    // TODO: Implement vision modality for web
    if (enableVisionModality == true) {
      if (kDebugMode) {
        debugPrint('Warning: Vision modality is not yet implemented for web platform');
      }
    }

    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      // Use Modern API to get model path (same as mobile)
      final activeModel = modelManager.activeInferenceModel;
      if (activeModel == null) {
        throw Exception('No active inference model set');
      }

      final modelFilePaths = await modelManager.getModelFilePaths(activeModel);
      if (modelFilePaths == null || modelFilePaths.isEmpty) {
        throw Exception('Model file paths not found');
      }

      // Get model path from Modern API
      final modelPath = modelFilePaths[PreferencesKeys.installedModelFileName];
      if (modelPath == null) {
        throw Exception('Model path not found in file paths');
      }

      final fileset = await FilesetResolver.forGenAiTasks(
              'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@latest/wasm'.toJS)
          .toDart;

      // Get LoRA path if available
      final loraPathToUse = loraPath ?? modelFilePaths[PreferencesKeys.installedLoraFileName];
      final hasLoraParams = loraPathToUse != null && loraRanks != null;

      final config = LlmInferenceOptions(
          baseOptions: LlmInferenceBaseOptions(modelAssetPath: modelPath),
          maxTokens: maxTokens,
          randomSeed: randomSeed,
          topK: topK,
          temperature: temperature,
          topP: topP,
          supportedLoraRanks: !hasLoraParams ? null : Int32List.fromList(loraRanks!).toJS,
          loraPath: !hasLoraParams ? null : loraPathToUse,
          maxNumImages: supportImage ? (maxNumImages ?? 1) : null);

      final llmInference = await LlmInference.createFromOptions(fileset, config).toDart;

      final session = this.session = WebModelSession(
        modelType: modelType,
        fileType: fileType,
        llmInference: llmInference,
        supportImage: supportImage, // Enabling image support
        onClose: onClose,
      );
      completer.complete(session);
      return completer.future;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await session?.close();
    session = null;
    onClose();
  }
}

class WebModelSession extends InferenceModelSession {
  final ModelType modelType;
  final ModelFileType fileType;
  final LlmInference llmInference;
  final VoidCallback onClose;
  final bool supportImage; // Enabling image support
  StreamController<String>? _controller;
  final List<PromptPart> _promptParts = [];

  WebModelSession({
    required this.llmInference,
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
  });

  @override
  Future<int> sizeInTokens(String text) async {
    final size = llmInference.sizeInTokens(text.toJS);
    return size.toDartInt;
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    if (kDebugMode) {
      debugPrint(
          '🟢 WebModelSession.addQueryChunk() called - hasImage: ${message.hasImage}, supportImage: $supportImage');
    }

    final finalPrompt = message.transformToChatPrompt(type: modelType, fileType: fileType);

    // Add text part
    _promptParts.add(TextPromptPart(finalPrompt));
    if (kDebugMode) {
      debugPrint(
          '🟢 Added text part: ${finalPrompt.substring(0, math.min(100, finalPrompt.length))}...');
    }

    // Handle image processing for web
    if (message.hasImage && message.imageBytes != null) {
      if (kDebugMode) {
        debugPrint('🟢 Processing image: ${message.imageBytes!.length} bytes');
      }
      if (!supportImage) {
        if (kDebugMode) {
          debugPrint('🔴 Model does not support images - throwing exception');
        }
        throw ArgumentError('This model does not support images');
      }
      // Add image part
      final imagePart = ImagePromptPart.fromBytes(message.imageBytes!);
      _promptParts.add(imagePart);
      if (kDebugMode) {
        debugPrint('🟢 Added image part with dataUrl length: ${imagePart.dataUrl.length}');
      }
    }

    if (kDebugMode) {
      debugPrint('🟢 Total prompt parts: ${_promptParts.length}');
    }
  }

  /// Convert PromptParts to JavaScript array for MediaPipe
  JSAny _createPromptArray() {
    if (kDebugMode) {
      debugPrint('🔧 _createPromptArray: Starting with ${_promptParts.length} prompt parts');
    }

    if (_promptParts.isEmpty) {
      if (kDebugMode) {
        debugPrint('📝 _createPromptArray: Empty prompt parts, returning empty string');
      }
      return ''.toJS; // Empty string fallback
    }

    // If only text parts, join them
    if (_promptParts.every((part) => part is TextPromptPart)) {
      final fullText = _promptParts.cast<TextPromptPart>().map((part) => part.text).join('');
      if (kDebugMode) {
        debugPrint(
            '📝 _createPromptArray: All text parts, returning string of length ${fullText.length}');
        debugPrint(
            '📝 _createPromptArray: Text preview: ${fullText.substring(0, math.min(100, fullText.length))}...');
      }
      return fullText.toJS;
    }

    // Multimodal: create array of parts following MediaPipe documentation format
    if (kDebugMode) {
      debugPrint('🎯 _createPromptArray: Multimodal mode - creating array with proper format');
    }

    final jsArray = <JSAny>[];

    // Add conversation start token
    jsArray.add('<ctrl99>user\n'.toJS);

    for (int i = 0; i < _promptParts.length; i++) {
      final part = _promptParts[i];

      if (part is TextPromptPart) {
        if (kDebugMode) {
          debugPrint(
              '📝 _createPromptArray: Adding text part: "${part.text.substring(0, math.min(50, part.text.length))}..."');
        }
        jsArray.add(part.text.toJS);
      } else if (part is ImagePromptPart) {
        if (kDebugMode) {
          debugPrint(
              '🖼️ _createPromptArray: Adding image part with data URL length: ${part.dataUrl.length}');
          debugPrint(
              '🖼️ _createPromptArray: Image data URL prefix: ${part.dataUrl.substring(0, math.min(50, part.dataUrl.length))}...');
        }

        // Create proper image object for MediaPipe
        final imageObj = <String, String>{'imageSource': part.dataUrl}.jsify();
        if (kDebugMode) {
          debugPrint('🖼️ _createPromptArray: Created image object with jsify()');
        }
        jsArray.add(imageObj as JSAny);
      } else {
        if (kDebugMode) {
          debugPrint('❌ _createPromptArray: Unsupported prompt part type: ${part.runtimeType}');
        }
        throw Exception('Unsupported prompt part type: $part');
      }
    }

    // Add conversation end and model start tokens
    jsArray.add('<ctrl100>\n<ctrl99>model\n'.toJS);

    if (kDebugMode) {
      debugPrint(
          '✅ _createPromptArray: Created JS array with ${jsArray.length} elements (including control tokens)');
      debugPrint('🎯 _createPromptArray: Array structure ready for MediaPipe');
    }

    return jsArray.toJS;
  }

  @override
  Future<String> getResponse() async {
    if (kDebugMode) {
      debugPrint('🚀 getResponse: Starting response generation');
    }

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        debugPrint('🎯 getResponse: Prompt array type: ${promptArray.runtimeType}');
        debugPrint('🎯 getResponse: Is JSString? ${promptArray is JSString}');
      }

      String response;

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          debugPrint('📝 getResponse: Using generateResponse for text-only prompt');
        }
        response = (await llmInference.generateResponse(promptArray, null).toDart).toDart;
      } else {
        if (kDebugMode) {
          debugPrint('🖼️ getResponse: Using generateResponseMultimodal for multimodal prompt');
        }
        response = (await llmInference.generateResponseMultimodal(promptArray, null).toDart).toDart;
      }

      if (kDebugMode) {
        debugPrint('✅ getResponse: Successfully generated response of length ${response.length}');
        debugPrint(
            '✅ getResponse: Response preview: ${response.substring(0, math.min(100, response.length))}...');
      }

      // Don't add response back to promptParts - that's handled by InferenceChat
      return response;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ getResponse: Exception caught: $e');
        debugPrint('❌ getResponse: Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  @override
  Stream<String> getResponseAsync() {
    if (kDebugMode) {
      debugPrint('🌊 getResponseAsync: Starting async response generation');
    }

    _controller = StreamController<String>();

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        debugPrint('🎯 getResponseAsync: Prompt array type: ${promptArray.runtimeType}');
        debugPrint('🎯 getResponseAsync: Is JSString? ${promptArray is JSString}');
      }

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          debugPrint('📝 getResponseAsync: Using generateResponse for text-only prompt');
        }
        llmInference.generateResponse(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                debugPrint(
                    '📝 getResponseAsync: Received partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  debugPrint('✅ getResponseAsync: Text response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ getResponseAsync: Error in text callback: $e');
              }
              _controller?.addError(e);
            }
          }).toJS,
        );
      } else {
        if (kDebugMode) {
          debugPrint(
              '🖼️ getResponseAsync: Using generateResponseMultimodal for multimodal prompt');
        }
        llmInference.generateResponseMultimodal(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                debugPrint(
                    '🖼️ getResponseAsync: Received multimodal partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  debugPrint('✅ getResponseAsync: Multimodal response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ getResponseAsync: Error in multimodal callback: $e');
              }
              _controller?.addError(e);
            }
          }).toJS,
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ getResponseAsync: Exception during setup: $e');
        debugPrint('❌ getResponseAsync: Stack trace: $stackTrace');
      }
      _controller?.addError(e);
    }

    return _controller!.stream;
  }

  @override
  Future<void> stopGeneration() async {
    throw UnimplementedError('Stop generation is not supported on Web platform yet');
  }

  @override
  Future<void> close() async {
    _promptParts.clear();
    _controller?.close();
    _controller = null;
    onClose();
  }
}
