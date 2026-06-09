import 'dart:async';

import '../core/chat.dart';
import '../core/model.dart';
import '../core/tool.dart';
import '../core/domain/model_source.dart';
import '../flutter_gemma_interface.dart';
import '../mobile/flutter_gemma_mobile.dart'
    show EmbeddingModelSpec, InferenceModelSpec;
import '../pigeon.g.dart';

typedef DesktopInferenceModelFactory = FutureOr<InferenceModel?> Function(
    DesktopInferenceRequest request);

typedef DesktopEmbeddingModelFactory = FutureOr<EmbeddingModel?> Function(
    DesktopEmbeddingRequest request);

/// Request payload for custom desktop inference runtimes.
///
/// Integrators can inspect the resolved file paths, active [InferenceModelSpec],
/// and requested runtime knobs to decide whether they want to handle the model.
/// Returning `null` means "not supported, continue with the built-in LiteRT
/// desktop runtime".
class DesktopInferenceRequest {
  const DesktopInferenceRequest({
    required this.spec,
    required this.modelPath,
    required this.modelType,
    required this.fileType,
    required this.maxTokens,
    required this.cacheDir,
    this.loraPath,
    this.preferredBackend,
    this.loraRanks,
    this.maxNumImages,
    this.supportImage = false,
    this.supportAudio = false,
    this.enableSpeculativeDecoding,
  });

  final InferenceModelSpec spec;
  final String modelPath;
  final String? loraPath;
  final ModelType modelType;
  final ModelFileType fileType;
  final int maxTokens;
  final String cacheDir;
  final PreferredBackend? preferredBackend;
  final List<int>? loraRanks;
  final int? maxNumImages;
  final bool supportImage;
  final bool supportAudio;
  final bool? enableSpeculativeDecoding;
}

/// Request payload for custom desktop embedding runtimes.
///
/// Returning `null` from the factory means the extension declines the request
/// and flutter_gemma should keep using its bundled embedding path.
class DesktopEmbeddingRequest {
  const DesktopEmbeddingRequest({
    required this.modelPath,
    required this.tokenizerPath,
    this.spec,
    this.preferredBackend,
  });

  final EmbeddingModelSpec? spec;
  final String modelPath;
  final String tokenizerPath;
  final PreferredBackend? preferredBackend;
}

/// Describes a pluggable desktop runtime.
///
/// Example use cases:
/// - MLX-backed inference on macOS
/// - Project-specific native bridges
/// - Experimental runtimes that should coexist with LiteRT fallback
class DesktopRuntimeExtension {
  const DesktopRuntimeExtension({
    required this.name,
    this.createInferenceModel,
    this.createEmbeddingModel,
  });

  final String name;
  final DesktopInferenceModelFactory? createInferenceModel;
  final DesktopEmbeddingModelFactory? createEmbeddingModel;
}

/// Registry for pluggable desktop runtimes.
///
/// flutter_gemma ships with a built-in LiteRT desktop path. This registry makes
/// it possible to add alternative runtimes without forking core model/session
/// APIs. The first extension that returns a non-null model wins; otherwise the
/// built-in LiteRT implementation is used.
class DesktopRuntimeRegistry {
  final List<DesktopRuntimeExtension> _extensions = [];

  List<DesktopRuntimeExtension> get extensions =>
      List.unmodifiable(_extensions);

  void register(DesktopRuntimeExtension extension) {
    unregister(extension.name);
    _extensions.add(extension);
  }

  bool unregister(String name) {
    final index = _extensions.indexWhere((extension) => extension.name == name);
    if (index == -1) return false;
    _extensions.removeAt(index);
    return true;
  }

  void clear() => _extensions.clear();

  Future<InferenceModel?> createInferenceModel(
    DesktopInferenceRequest request,
  ) async {
    for (final extension in _extensions) {
      final factory = extension.createInferenceModel;
      if (factory == null) continue;
      final model = await factory(request);
      if (model != null) {
        return model;
      }
    }
    return null;
  }

  Future<EmbeddingModel?> createEmbeddingModel(
    DesktopEmbeddingRequest request,
  ) async {
    for (final extension in _extensions) {
      final factory = extension.createEmbeddingModel;
      if (factory == null) continue;
      final model = await factory(request);
      if (model != null) {
        return model;
      }
    }
    return null;
  }

  Future<InferenceModel?> createManagedInferenceModel(
    DesktopInferenceRequest request, {
    required FutureOr<void> Function() onClose,
  }) async {
    final model = await createInferenceModel(request);
    if (model == null) return null;
    return _ManagedInferenceModel(delegate: model, onClose: onClose);
  }

  Future<EmbeddingModel?> createManagedEmbeddingModel(
    DesktopEmbeddingRequest request, {
    required FutureOr<void> Function() onClose,
  }) async {
    final model = await createEmbeddingModel(request);
    if (model == null) return null;
    return _ManagedEmbeddingModel(delegate: model, onClose: onClose);
  }
}

class _ManagedInferenceModel extends InferenceModel {
  _ManagedInferenceModel({
    required InferenceModel delegate,
    required FutureOr<void> Function() onClose,
  })  : _delegate = delegate,
        _onClose = onClose;

  final InferenceModel _delegate;
  final FutureOr<void> Function() _onClose;
  bool _closed = false;

  @override
  InferenceModelSession? get session => _delegate.session;

  @override
  InferenceChat? get chat => _delegate.chat;

  @override
  set chat(InferenceChat? value) => _delegate.chat = value;

  @override
  int get maxTokens => _delegate.maxTokens;

  @override
  ModelFileType get fileType => _delegate.fileType;

  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
  }) {
    return _delegate.createSession(
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      topP: topP,
      loraPath: loraPath,
      enableVisionModality: enableVisionModality,
      enableAudioModality: enableAudioModality,
      systemInstruction: systemInstruction,
      enableThinking: enableThinking,
      tools: tools,
    );
  }

  @override
  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false,
    ModelType? modelType,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxFunctionBufferLength,
    String? systemInstruction,
  }) {
    return _delegate.createChat(
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      topP: topP,
      tokenBuffer: tokenBuffer,
      loraPath: loraPath,
      supportImage: supportImage,
      supportAudio: supportAudio,
      tools: tools,
      supportsFunctionCalls: supportsFunctionCalls,
      isThinking: isThinking,
      modelType: modelType,
      toolChoice: toolChoice,
      maxFunctionBufferLength: maxFunctionBufferLength,
      systemInstruction: systemInstruction,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _delegate.close();
    } finally {
      await _onClose();
    }
  }
}

class _ManagedEmbeddingModel extends EmbeddingModel {
  _ManagedEmbeddingModel({
    required EmbeddingModel delegate,
    required FutureOr<void> Function() onClose,
  })  : _delegate = delegate,
        _onClose = onClose;

  final EmbeddingModel _delegate;
  final FutureOr<void> Function() _onClose;
  bool _closed = false;

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) {
    return _delegate.generateEmbedding(text, taskType: taskType);
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) {
    return _delegate.generateEmbeddings(texts, taskType: taskType);
  }

  @override
  Future<int> getDimension() => _delegate.getDimension();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _delegate.close();
    } finally {
      await _onClose();
    }
  }
}
