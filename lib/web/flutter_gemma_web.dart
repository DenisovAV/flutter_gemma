import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gemma/core/extensions.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/parsing/sdk_response_parser.dart';
import 'package:flutter_gemma/core/parsing/sdk_text_extractor.dart';
// Conditional import: same pattern WebDownloadService uses so the opfsService
// field type matches statically (both sides of the resolver agree on the type).
import 'package:flutter_gemma/core/infrastructure/web_opfs_interop_stub.dart'
    if (dart.library.js_interop) 'package:flutter_gemma/core/infrastructure/web_opfs_service.dart';
import 'package:flutter_gemma/core/model_management/constants/preferences_keys.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_download_service.dart';
import 'package:flutter_gemma/core/infrastructure/web_vector_store_repository.dart';
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/core/utils/file_name_utils.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'litert_lm_web.dart';
import 'llm_inference_web.dart';
import 'flutter_gemma_web_embedding_model.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';

part '../core/model_management/managers/web_model_manager.dart';
part 'web_model_source.dart';
part 'litert_lm_web_inference.dart';

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

/// Audio prompt part with raw audio bytes
/// For Gemma 3n E4B models - supports PCM audio (16kHz, 16-bit, mono)
class AudioPromptPart extends PromptPart {
  final Uint8List audioBytes;
  AudioPromptPart(this.audioBytes);
}

class FlutterGemmaWeb extends FlutterGemmaPlugin {
  FlutterGemmaWeb();

  static void registerWith(Registrar registrar) {
    FlutterGemmaPlugin.instance = FlutterGemmaWeb();
  }

  // WebModelManager singleton
  static WebModelManager? _webManager;

  // VectorStore repository (SQLite WASM)
  VectorStoreRepository? _vectorStoreRepository;

  @override
  ModelFileManager get modelManager {
    // Use WebModelManager
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
    bool supportAudio = false, // Enabling audio support (Gemma 3n E4B)
    bool? enableSpeculativeDecoding, // Ignored on web (MediaPipe path).
    int? maxConcurrentSessions,
  }) async {
    // TODO: Implement multimodal support for web
    if (supportImage || maxNumImages != null) {
      if (kDebugMode) {
        gemmaLog(
            'Warning: Image support is not yet implemented for web platform');
      }
    }

    // Check if model already exists with different parameters. Two web engine
    // types coexist now (MediaPipe `.task` and LiteRT-LM `.litertlm`), so the
    // cached singleton can be either — type-check, then compare params.
    if (_initializedModel != null) {
      final existing = _initializedModel!;
      bool parametersChanged;
      if (existing is WebInferenceModel) {
        parametersChanged = existing.modelType != modelType ||
            existing.fileType != fileType ||
            existing.maxTokens != maxTokens ||
            existing.supportImage != supportImage ||
            existing.supportAudio != supportAudio ||
            (existing.maxNumImages ?? 0) != (maxNumImages ?? 0);
      } else if (existing is LiteRtLmWebInferenceModel) {
        parametersChanged = existing.modelType != modelType ||
            existing.fileType != fileType ||
            existing.maxTokens != maxTokens;
      } else {
        // Unknown engine type — always replace.
        parametersChanged = true;
      }
      if (parametersChanged) {
        if (kDebugMode) {
          gemmaLog(
              '[FlutterGemmaWeb] Model parameters changed, closing existing model');
        }
        await existing.close();
        _initializedModel = null;
      }
    }

    if (_initializedModel != null) {
      return _initializedModel!;
    }

    // Engine selection by file type, mirroring the mobile branch in
    // FlutterGemmaMobile.createModel: .task → MediaPipe (WebInferenceModel),
    // .litertlm → LiteRT-LM JS via @litert-lm/core (LiteRtLmWebInferenceModel).
    // Both share one [WebModelSourceResolver] — the storage-mode branch
    // (Blob URL vs OPFS ReadableStream) lives there, not here.
    final webManager = modelManager as WebModelManager;
    final sourceResolver = WebModelSourceResolver(webManager);
    if (fileType == ModelFileType.litertlm) {
      _initializedModel = LiteRtLmWebInferenceModel(
        modelType: modelType,
        maxTokens: maxTokens,
        sourceResolver: sourceResolver,
        maxConcurrentSessions: maxConcurrentSessions,
        onClose: () {
          _initializedModel = null;
        },
      );
    } else {
      _initializedModel = WebInferenceModel(
        modelType: modelType,
        fileType: fileType,
        maxTokens: maxTokens,
        loraRanks: loraRanks,
        sourceResolver: sourceResolver,
        supportImage: supportImage, // Passing the flag
        supportAudio: supportAudio, // Passing the audio flag
        maxNumImages: maxNumImages,
        maxConcurrentSessions: maxConcurrentSessions,
        onClose: () {
          _initializedModel = null;
        },
      );
    }
    return _initializedModel!;
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
      final activeModelPath =
          modelFilePaths[PreferencesKeys.embeddingModelFile];
      final activeTokenizerPath =
          modelFilePaths[PreferencesKeys.embeddingTokenizerFile];

      if (activeModelPath == null || activeTokenizerPath == null) {
        throw StateError(
            'Could not find model or tokenizer path in active embedding model');
      }

      modelPath = activeModelPath;
      tokenizerPath = activeTokenizerPath;

      if (kDebugMode) {
        gemmaLog(
            'Using active embedding model: $modelPath, tokenizer: $tokenizerPath');
      }
    }

    // Check if model already exists with different parameters
    if (_initializedEmbeddingModel != null) {
      final existing = _initializedEmbeddingModel! as WebEmbeddingModel;

      // Check if paths changed (indicates different model)
      final bool modelChanged = existing.modelPath != modelPath ||
          existing.tokenizerPath != tokenizerPath;

      if (modelChanged) {
        if (kDebugMode) {
          gemmaLog(
              '[FlutterGemmaWeb] Embedding model paths changed, closing existing model');
        }
        await existing.close();
        _initializedEmbeddingModel = null;
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
    return model;
  }

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    try {
      _vectorStoreRepository = WebVectorStoreRepository();
      await _vectorStoreRepository!.initialize(databasePath);
      gemmaLog('[FlutterGemmaWeb] VectorStore initialized with SQLite WASM');
    } catch (e) {
      gemmaLog('[FlutterGemmaWeb] Failed to initialize VectorStore: $e');
      rethrow;
    }
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    if (_vectorStoreRepository == null) {
      throw StateError(
          'VectorStore not initialized. Call initializeVectorStore() first.');
    }

    await _vectorStoreRepository!.addDocument(
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
    if (_vectorStoreRepository == null) {
      throw StateError(
          'VectorStore not initialized. Call initializeVectorStore() first.');
    }

    if (_initializedEmbeddingModel == null) {
      throw StateError(
          'Embedding model not created. Call createEmbeddingModel() first.');
    }

    // Generate embedding and add document
    final embedding = await _initializedEmbeddingModel!.generateEmbedding(
      content,
      taskType: TaskType.retrievalDocument,
    );
    await _vectorStoreRepository!.addDocument(
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
    Filter? filter, // ignored on Web (wa-sqlite has no payload filtering)
  }) async {
    if (_vectorStoreRepository == null) {
      throw StateError(
          'VectorStore not initialized. Call initializeVectorStore() first.');
    }

    if (_initializedEmbeddingModel == null) {
      throw StateError(
          'Embedding model not created. Call createEmbeddingModel() first.');
    }

    // Generate query embedding and search
    final queryEmbedding =
        await _initializedEmbeddingModel!.generateEmbedding(query);
    return await _vectorStoreRepository!.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: topK,
      threshold: threshold,
      filter: filter,
    );
  }

  @override
  Future<VectorStoreStats> getVectorStoreStats() async {
    if (_vectorStoreRepository == null) {
      throw StateError(
          'VectorStore not initialized. Call initializeVectorStore() first.');
    }

    return await _vectorStoreRepository!.getStats();
  }

  @override
  Future<void> clearVectorStore() async {
    if (_vectorStoreRepository == null) {
      throw StateError(
          'VectorStore not initialized. Call initializeVectorStore() first.');
    }

    await _vectorStoreRepository!.clear();
  }

  @override
  bool get enableHnsw => _vectorStoreRepository?.enableHnsw ?? true;

  @override
  set enableHnsw(bool value) {
    if (_vectorStoreRepository != null) {
      _vectorStoreRepository!.enableHnsw = value;
    }
  }
}

class WebInferenceModel extends InferenceModel {
  final VoidCallback onClose;
  @override
  final int maxTokens;

  final ModelType modelType;
  @override
  final ModelFileType fileType;
  @override
  PreferredBackend? get activeBackend => null;
  final List<int>? loraRanks;
  final WebModelSourceResolver sourceResolver;
  final bool supportImage; // Enabling image support
  final bool supportAudio; // Enabling audio support (Gemma 3n E4B)
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
    required this.sourceResolver,
    this.supportImage = false,
    this.supportAudio = false,
    this.maxNumImages,
    this.maxConcurrentSessions,
  });

  /// Cap on concurrent [openSession] sessions; null = unlimited. Accepted
  /// for API symmetry. The MediaPipe web `.task` path doesn't support
  /// concurrent sessions yet (openSession inherits the interface's
  /// UnsupportedError), so this is currently informational.
  final int? maxConcurrentSessions;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = 0.8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Enabling vision modality support
    bool? enableAudioModality, // Enabling audio modality support (Gemma 3n E4B)
    String? systemInstruction,
    bool enableThinking = false, // Not supported on Web (MediaPipe)
    List<Tool> tools =
        const [], // Tools wired through chat.dart prompt; SDK tools_json N/A on web
  }) async {
    // Thinking mode not supported on Web (MediaPipe has no extraContext/channels API)
    if (enableThinking) {
      if (kDebugMode) {
        gemmaLog('Warning: enableThinking is not supported on Web (MediaPipe). '
            'Use Android or Desktop with .litertlm models for Gemma 4 thinking mode.');
      }
    }

    // TODO: Implement vision modality for web
    if (enableVisionModality == true) {
      if (kDebugMode) {
        gemmaLog(
            'Warning: Vision modality is not yet implemented for web platform');
      }
    }

    // Audio modality is handled via supportAudio flag in the model
    if (enableAudioModality == true && !supportAudio) {
      if (kDebugMode) {
        gemmaLog('Warning: Audio modality requested but supportAudio is false');
      }
    }

    if (_initCompleter case Completer<InferenceModelSession> completer) {
      return completer.future;
    }
    final completer = _initCompleter = Completer<InferenceModelSession>();
    try {
      // Shared resolver handles activeModel lookup + storage-mode branch.
      // Used identically by LiteRtLmWebInferenceModel.
      final resolved = await sourceResolver.resolveActiveInferenceModel();

      final fileset = await FilesetResolver.forGenAiTasks(
              'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27/wasm'
                  .toJS)
          .toDart;

      // LoRA path comes from the resolver alongside the model source.
      final loraPathToUse = loraPath ?? resolved.loraPath;
      final hasLoraParams = loraPathToUse != null && loraRanks != null;

      // MediaPipe consumes either modelAssetPath (Blob URL string) or
      // modelAssetBuffer (ReadableStreamDefaultReader, for OPFS streaming).
      final baseOptions = switch (resolved.model) {
        BlobUrlModelSource(:final url) =>
          LlmInferenceBaseOptions(modelAssetPath: url),
        OpfsStreamModelSource() => LlmInferenceBaseOptions(
            modelAssetBuffer:
                await (resolved.model as OpfsStreamModelSource).openReader()),
      };

      final config = LlmInferenceOptions(
          baseOptions: baseOptions,
          maxTokens: maxTokens,
          randomSeed: randomSeed,
          topK: topK,
          temperature: temperature,
          topP: topP,
          supportedLoraRanks:
              !hasLoraParams ? null : Int32List.fromList(loraRanks!).toJS,
          loraPath: !hasLoraParams ? null : loraPathToUse,
          maxNumImages: supportImage ? (maxNumImages ?? 1) : null);

      final llmInference =
          await LlmInference.createFromOptions(fileset, config).toDart;

      session = WebModelSession(
        modelType: modelType,
        fileType: fileType,
        llmInference: llmInference,
        supportImage: supportImage, // Enabling image support
        supportAudio: supportAudio, // Enabling audio support
        systemInstruction: systemInstruction,
        onClose: onClose,
      );

      completer.complete(session);
      return completer.future;
    } catch (e, st) {
      _initCompleter = null;
      completer.completeError(e, st);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await session?.close();
    session = null;
    _initCompleter = null;
    onClose();
  }
}

class WebModelSession extends InferenceModelSession {
  final ModelType modelType;
  final ModelFileType fileType;
  final LlmInference llmInference;
  final VoidCallback onClose;
  final bool supportImage; // Enabling image support
  final bool supportAudio; // Enabling audio support (Gemma 3n E4B)
  StreamController<String>? _controller;
  final List<PromptPart> _promptParts = [];

  final String? systemInstruction;
  bool _systemInstructionSent = false;

  WebModelSession({
    required this.llmInference,
    required this.onClose,
    required this.modelType,
    this.fileType = ModelFileType.task,
    this.supportImage = false,
    this.supportAudio = false,
    this.systemInstruction,
  });

  @override
  Future<int> sizeInTokens(String text) async {
    final size = llmInference.sizeInTokens(text.toJS);
    return size.toDartInt;
  }

  @override
  Future<void> addQueryChunk(Message message) async {
    if (kDebugMode) {
      gemmaLog(
          '🟢 WebModelSession.addQueryChunk() called - hasImage: ${message.hasImage}, hasAudio: ${message.hasAudio}, supportImage: $supportImage, supportAudio: $supportAudio');
    }

    var messageToSend = message;
    if (message.isUser &&
        !_systemInstructionSent &&
        systemInstruction != null &&
        systemInstruction!.isNotEmpty) {
      _systemInstructionSent = true;
      messageToSend = message.copyWith(
        text: '[System: ${systemInstruction!}]\n\n${message.text}',
      );
    }

    final finalPrompt = messageToSend.transformToChatPrompt(
        type: modelType, fileType: fileType);

    // Add image parts first, then audio, then text last.
    if (message.hasImage) {
      if (!supportImage) {
        if (kDebugMode) {
          gemmaLog('🔴 Model does not support images - throwing exception');
        }
        throw ArgumentError('This model does not support images');
      }

      final images = message.images.isNotEmpty
          ? message.images
          : (message.imageBytes != null
              ? [message.imageBytes!]
              : const <Uint8List>[]);
      for (final imageBytes in images) {
        if (kDebugMode) {
          gemmaLog('🟢 Processing image: ${imageBytes.length} bytes');
        }
        final imagePart = ImagePromptPart.fromBytes(imageBytes);
        _promptParts.add(imagePart);
        if (kDebugMode) {
          gemmaLog(
              '🟢 Added image part with dataUrl length: ${imagePart.dataUrl.length}');
        }
      }
    }

    // Handle audio processing for web (Gemma 3n E4B)
    if (message.hasAudio && message.audioBytes != null) {
      if (kDebugMode) {
        gemmaLog('🎵 Processing audio: ${message.audioBytes!.length} bytes');
      }
      if (!supportAudio) {
        if (kDebugMode) {
          gemmaLog('🔴 Model does not support audio - throwing exception');
        }
        throw ArgumentError('This model does not support audio');
      }
      // Add audio part
      final audioPart = AudioPromptPart(message.audioBytes!);
      _promptParts.add(audioPart);
      if (kDebugMode) {
        gemmaLog(
            '🎵 Added audio part with ${message.audioBytes!.length} bytes');
      }
    }

    // Add text part last so multimodal turns keep image/audio context first.
    _promptParts.add(TextPromptPart(finalPrompt));
    if (kDebugMode) {
      gemmaLog(
          '🟢 Added text part: ${finalPrompt.substring(0, math.min(100, finalPrompt.length))}...');
    }

    if (kDebugMode) {
      gemmaLog('🟢 Total prompt parts: ${_promptParts.length}');
    }
  }

  /// Convert PromptParts to JavaScript array for MediaPipe
  JSAny _createPromptArray() {
    if (kDebugMode) {
      gemmaLog(
          '🔧 _createPromptArray: Starting with ${_promptParts.length} prompt parts');
    }

    if (_promptParts.isEmpty) {
      if (kDebugMode) {
        gemmaLog(
            '📝 _createPromptArray: Empty prompt parts, returning empty string');
      }
      return ''.toJS; // Empty string fallback
    }

    // If only text parts, join them
    if (_promptParts.every((part) => part is TextPromptPart)) {
      final fullText =
          _promptParts.cast<TextPromptPart>().map((part) => part.text).join('');
      if (kDebugMode) {
        gemmaLog(
            '📝 _createPromptArray: All text parts, returning string of length ${fullText.length}');
        gemmaLog(
            '📝 _createPromptArray: Text preview: ${fullText.substring(0, math.min(100, fullText.length))}...');
      }
      return fullText.toJS;
    }

    // Multimodal: create array of parts following MediaPipe documentation format
    if (kDebugMode) {
      gemmaLog(
          '🎯 _createPromptArray: Multimodal mode - creating array with proper format');
    }

    final jsArray = <JSAny>[];

    // Add conversation start token
    jsArray.add('<ctrl99>user\n'.toJS);

    for (int i = 0; i < _promptParts.length; i++) {
      final part = _promptParts[i];

      if (part is TextPromptPart) {
        if (kDebugMode) {
          gemmaLog(
              '📝 _createPromptArray: Adding text part: "${part.text.substring(0, math.min(50, part.text.length))}..."');
        }
        jsArray.add(part.text.toJS);
      } else if (part is ImagePromptPart) {
        if (kDebugMode) {
          gemmaLog(
              '🖼️ _createPromptArray: Adding image part with data URL length: ${part.dataUrl.length}');
          gemmaLog(
              '🖼️ _createPromptArray: Image data URL prefix: ${part.dataUrl.substring(0, math.min(50, part.dataUrl.length))}...');
        }

        // Create proper image object for MediaPipe
        final imageObj = <String, String>{'imageSource': part.dataUrl}.jsify();
        if (kDebugMode) {
          gemmaLog('🖼️ _createPromptArray: Created image object with jsify()');
        }
        jsArray.add(imageObj as JSAny);
      } else if (part is AudioPromptPart) {
        if (kDebugMode) {
          gemmaLog(
              '🎵 _createPromptArray: Adding audio part with ${part.audioBytes.length} bytes');
        }

        // Create proper audio object for MediaPipe
        // Audio is passed as raw PCM bytes (16kHz, 16-bit, mono)
        final audioObj = <String, Object>{
          'audioSource': part.audioBytes.buffer.asUint8List()
        }.jsify();
        if (kDebugMode) {
          gemmaLog('🎵 _createPromptArray: Created audio object with jsify()');
        }
        jsArray.add(audioObj as JSAny);
      } else {
        if (kDebugMode) {
          gemmaLog(
              '❌ _createPromptArray: Unsupported prompt part type: ${part.runtimeType}');
        }
        throw Exception('Unsupported prompt part type: $part');
      }
    }

    // Add conversation end and model start tokens
    jsArray.add('<ctrl100>\n<ctrl99>model\n'.toJS);

    if (kDebugMode) {
      gemmaLog(
          '✅ _createPromptArray: Created JS array with ${jsArray.length} elements (including control tokens)');
      gemmaLog('🎯 _createPromptArray: Array structure ready for MediaPipe');
    }

    return jsArray.toJS;
  }

  @override
  Future<String> getResponse() async {
    if (kDebugMode) {
      gemmaLog('🚀 getResponse: Starting response generation');
    }

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        gemmaLog(
            '🎯 getResponse: Prompt array type: ${promptArray.runtimeType}');
        gemmaLog('🎯 getResponse: Is JSString? ${promptArray is JSString}');
      }

      String response;

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          gemmaLog(
              '📝 getResponse: Using generateResponse for text-only prompt');
        }
        response =
            (await llmInference.generateResponse(promptArray, null).toDart)
                .toDart;
      } else {
        if (kDebugMode) {
          gemmaLog(
              '🖼️ getResponse: Using generateResponseMultimodal for multimodal prompt');
        }
        response = (await llmInference
                .generateResponseMultimodal(promptArray, null)
                .toDart)
            .toDart;
      }

      if (kDebugMode) {
        gemmaLog(
            '✅ getResponse: Successfully generated response of length ${response.length}');
        gemmaLog(
            '✅ getResponse: Response preview: ${response.substring(0, math.min(100, response.length))}...');
      }

      // Don't add response back to promptParts - that's handled by InferenceChat
      return response;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        gemmaLog('❌ getResponse: Exception caught: $e');
        gemmaLog('❌ getResponse: Stack trace: $stackTrace');
      }
      _promptParts.clear();
      rethrow;
    }
  }

  @override
  Stream<String> getResponseAsync() {
    if (kDebugMode) {
      gemmaLog('🌊 getResponseAsync: Starting async response generation');
    }

    // Close previous controller to prevent leak if called again before completion
    _controller?.close();
    _controller = StreamController<String>();

    try {
      final promptArray = _createPromptArray();

      if (kDebugMode) {
        gemmaLog(
            '🎯 getResponseAsync: Prompt array type: ${promptArray.runtimeType}');
        gemmaLog(
            '🎯 getResponseAsync: Is JSString? ${promptArray is JSString}');
      }

      // Use appropriate method based on prompt type
      if (promptArray is JSString) {
        if (kDebugMode) {
          gemmaLog(
              '📝 getResponseAsync: Using generateResponse for text-only prompt');
        }
        llmInference.generateResponse(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                gemmaLog(
                    '📝 getResponseAsync: Received partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  gemmaLog('✅ getResponseAsync: Text response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                gemmaLog('❌ getResponseAsync: Error in text callback: $e');
              }
              _controller?.addError(e);
            }
          }).toJS,
        );
      } else {
        if (kDebugMode) {
          gemmaLog(
              '🖼️ getResponseAsync: Using generateResponseMultimodal for multimodal prompt');
        }
        llmInference.generateResponseMultimodal(
          promptArray,
          ((JSString partialJs, JSAny completeRaw) {
            try {
              final complete = completeRaw.parseBool();
              final partial = partialJs.toDart;
              if (kDebugMode) {
                gemmaLog(
                    '🖼️ getResponseAsync: Received multimodal partial (complete: $complete): ${partial.substring(0, math.min(50, partial.length))}...');
              }
              _controller?.add(partial);
              if (complete) {
                if (kDebugMode) {
                  gemmaLog('✅ getResponseAsync: Multimodal response completed');
                }
                _controller?.close();
              }
            } catch (e) {
              if (kDebugMode) {
                gemmaLog(
                    '❌ getResponseAsync: Error in multimodal callback: $e');
              }
              _controller?.addError(e);
            }
          }).toJS,
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        gemmaLog('❌ getResponseAsync: Exception during setup: $e');
        gemmaLog('❌ getResponseAsync: Stack trace: $stackTrace');
      }
      _controller?.addError(e);
    }

    return _controller!.stream;
  }

  @override
  Future<void> stopGeneration() async {
    try {
      llmInference.cancelProcessing();
    } catch (e) {
      if (kDebugMode) {
        gemmaLog('[WebModelSession] cancelProcessing error: $e');
      }
    } finally {
      _controller?.close();
      _controller = null;
      _promptParts.clear();
    }
  }

  @override
  SessionMetrics getSessionMetrics() {
    // Web MediaPipe implementation doesn't expose detailed token metrics.
    // Users can estimate using sizeInTokens() before/after generation.
    return SessionMetrics();
  }

  @override
  Future<void> close() async {
    // Cleanup MediaPipe LlmInference WASM resources (important for hot restart)
    // This prevents memory leaks and "memory access out of bounds" errors
    // Note: MediaPipe's close() will also release any OPFS stream readers internally
    try {
      llmInference.close();
      if (kDebugMode) {
        gemmaLog('[WebModelSession] Cleaned up LlmInference resources');
      }
    } catch (e) {
      if (kDebugMode) {
        gemmaLog('[WebModelSession] Warning: Error closing LlmInference: $e');
      }
    }

    _promptParts.clear();
    _controller?.close();
    _controller = null;
    onClose();
  }
}
