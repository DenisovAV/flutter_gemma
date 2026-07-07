import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show InferenceModel, InferenceModelSession;
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;

import '../pigeon.g.dart';
import 'builtin_ai_session.dart';

/// A loaded OS built-in model (Gemini Nano / Apple Foundation Models).
///
/// The OS owns the weights; this model is a thin session factory over the
/// pigeon [BuiltInAiService]. Sessions are keyed by a monotonically increasing
/// [sessionId] so the shared event channel can be demuxed per session. Mixes
/// [CloseNotifier] so core can reset its singleton bookkeeping on close.
class BuiltInAiModel extends InferenceModel with CloseNotifier {
  BuiltInAiModel({
    required this.service,
    required this.modelType,
    required this.onClose,
    this.fileType = ModelFileType.builtIn,
    this.maxTokens = 1024,
    this.supportImage = false,
    this.systemInstruction,
  });

  final BuiltInAiService service;
  final ModelType modelType;
  final VoidCallback onClose;
  final bool supportImage;
  final String? systemInstruction;

  @override
  final ModelFileType fileType;

  @override
  final int maxTokens;

  @override
  PreferredBackend? get activeBackend => null;

  bool _isClosed = false;
  BuiltInAiSession? _session;

  /// Monotonic session-id generator. Starts at 1.
  int _nextSessionId = 1;

  @override
  InferenceModelSession? get session => _session;

  @override
  List<InferenceModelSession> get sessions => List.unmodifiable([?_session]);

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
    int? maxOutputTokens,
  }) async {
    if (_isClosed) {
      throw StateError(
        'Model is closed. Create a new instance to use it again',
      );
    }
    if (enableAudioModality == true) {
      throw UnsupportedError('Audio is not supported by built-in OS models');
    }

    // Fresh native session with a clean context; close any prior singleton.
    if (_session case final previous?) {
      await previous.close();
    }

    final id = _nextSessionId++;
    await service.createSession(
      sessionId: id,
      temperature: temperature,
      topK: topK,
      topP: topP,
      maxOutputTokens: maxOutputTokens,
      systemInstruction: systemInstruction ?? this.systemInstruction,
    );

    late final BuiltInAiSession session;
    session = BuiltInAiSession(
      sessionId: id,
      service: service,
      modelType: modelType,
      fileType: fileType,
      supportImage: enableVisionModality ?? supportImage,
      systemInstruction: systemInstruction ?? this.systemInstruction,
      // Identity-guarded so a late close of a superseded session can't null a
      // newer `_session`.
      onClose: () {
        if (identical(_session, session)) _session = null;
      },
    );
    _session = session;
    return session;
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
    int? maxOutputTokens,
  }) async {
    if (supportAudio == true) {
      throw UnsupportedError('Audio is not supported by built-in OS models');
    }
    chat = InferenceChat(
      sessionCreator: () => createSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? this.supportImage,
        systemInstruction: systemInstruction ?? this.systemInstruction,
        enableThinking: isThinking,
        maxOutputTokens: maxOutputTokens,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? this.supportImage,
      supportAudio: false,
      supportsFunctionCalls: supportsFunctionCalls ?? false,
      maxFunctionBufferLength:
          maxFunctionBufferLength ?? defaultMaxFunctionBufferLength,
      tools: tools,
      modelType: modelType ?? this.modelType,
      isThinking: isThinking,
      fileType: fileType,
      toolChoice: toolChoice,
      systemInstruction: systemInstruction ?? this.systemInstruction,
    );
    await chat!.initSession();
    return chat!;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _session?.close();
    _session = null;
    onClose();
    fireCloseListeners();
    await service.closeModel();
  }
}
