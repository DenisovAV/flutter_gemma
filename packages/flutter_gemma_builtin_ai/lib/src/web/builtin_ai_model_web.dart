import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show InferenceModel, InferenceModelSession;
import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;

import 'builtin_ai_session_web.dart';
import 'language_model_interop.dart';

/// One-time guard so requesting thinking mode logs a single warning rather
/// than spamming one per session/chat. Mirrors the native model's flag.
bool _thinkingUnsupportedWarned = false;

@visibleForTesting
void resetThinkingUnsupportedWarningWeb() => _thinkingUnsupportedWarned = false;

/// One-time guards (per knob) for every `createSession` parameter the
/// Chrome Prompt API has no equivalent for. Chosen over a single shared flag
/// so setting two unsupported knobs on the same call logs once EACH,
/// pinpointing which knob to drop from the call site.
final Set<String> _droppedParamsWarned = {};

@visibleForTesting
void resetDroppedParamWarningsWeb() => _droppedParamsWarned.clear();

void _warnParamDroppedOnce(String param, String detail) {
  if (!_droppedParamsWarned.add(param)) return;
  gemmaLog(
    '[BuiltInAI/web] $param is not supported by the Chrome Prompt API; $detail',
  );
}

bool _visionUnsupportedWarned = false;

@visibleForTesting
void resetVisionUnsupportedWarningWeb() => _visionUnsupportedWarned = false;

void _warnVisionIgnoredOnce() {
  if (_visionUnsupportedWarned) return;
  _visionUnsupportedWarned = true;
  gemmaLog(
    '[BuiltInAI/web] Vision input is not wired on the web Prompt API path '
    '(v1, text-only) — images are dropped. Track: expectedInputs:[{type:"image"}].',
  );
}

/// A loaded Chrome Prompt API "model" (Gemini Nano via `self.LanguageModel`).
///
/// The Prompt API has no separate model-load step — `LanguageModel.create()`
/// both loads (if needed) and creates a session in one call — so, like the
/// native [InferenceModel], this is a thin session factory. Mixes
/// [CloseNotifier] so core can reset its singleton bookkeeping on close.
class BuiltInAiModelWeb extends InferenceModel with CloseNotifier {
  BuiltInAiModelWeb({
    required this.modelType,
    required this.onClose,
    this.fileType = ModelFileType.builtIn,
    this.maxTokens = 1024,
    this.supportImage = false,
    this.systemInstruction,
  });

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
  BuiltInAiSessionWeb? _session;

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
    if (enableThinking) {
      if (!_thinkingUnsupportedWarned) {
        _thinkingUnsupportedWarned = true;
        gemmaLog(
          '[BuiltInAI/web] Thinking mode is not supported by the Chrome '
          'Prompt API; the flag is ignored.',
        );
      }
    }
    if (topP != null) {
      _warnParamDroppedOnce(
        'topP',
        'the Prompt API only exposes temperature+topK. Value dropped.',
      );
    }
    if (maxOutputTokens != null) {
      _warnParamDroppedOnce(
        'maxOutputTokens',
        'the Prompt API has no per-session output-length cap. Value dropped.',
      );
    }
    if (randomSeed != 1) {
      _warnParamDroppedOnce(
        'randomSeed',
        'the Prompt API exposes no sampling seed. Value dropped.',
      );
    }
    if (loraPath != null) {
      _warnParamDroppedOnce(
        'loraPath',
        'the Prompt API has no LoRA adapter concept. Value dropped.',
      );
    }
    final wantsVision = enableVisionModality ?? supportImage;
    if (wantsVision) _warnVisionIgnoredOnce();

    // Fresh native session with a clean context; close any prior singleton.
    if (_session case final previous?) {
      await previous.close();
    }

    final effectiveSystemInstruction =
        systemInstruction ?? this.systemInstruction;
    final clamped = await _clampSamplerParams(
      temperature: temperature,
      topK: topK,
    );
    final options = buildCreateOptions(
      systemInstruction: effectiveSystemInstruction,
      temperature: clamped.$1,
      topK: clamped.$2,
    );

    final jsSession = await LanguageModel.create(options).toDart;

    late final BuiltInAiSessionWeb newSession;
    newSession = BuiltInAiSessionWeb(
      session: jsSession,
      modelType: modelType,
      fileType: fileType,
      // v1 web arm is text-only regardless of what was requested.
      supportImage: false,
      systemInstruction: effectiveSystemInstruction,
      // Identity-guarded so a late close of a superseded session can't null a
      // newer `_session`.
      onClose: () {
        if (identical(_session, newSession)) _session = null;
      },
    );
    _session = newSession;
    return newSession;
  }

  /// Clamps (temperature, topK) against `LanguageModel.params()`'s
  /// `maxTemperature`/`maxTopK`, warning once if a clamp occurred. Absent
  /// fields (older Chrome builds) skip that bound. Returns the pair to use.
  Future<(double, int)> _clampSamplerParams({
    required double temperature,
    required int topK,
  }) async {
    // Chrome 151+ dropped the static `LanguageModel.params()` — feature-detect
    // it and skip the clamp (create() validates the values) rather than calling
    // a missing method and swallowing a TypeError on every single session.
    if (!hasLanguageModelParams) return (temperature, topK);
    try {
      final params = await LanguageModel.params().toDart;
      final maxTemp = params
          .getProperty<JSNumber?>('maxTemperature'.toJS)
          ?.toDartDouble;
      final maxTopK = params.getProperty<JSNumber?>('maxTopK'.toJS)?.toDartInt;
      var clampedTemp = temperature;
      var clampedTopK = topK;
      var clamped = false;
      if (maxTemp != null && clampedTemp > maxTemp) {
        clampedTemp = maxTemp;
        clamped = true;
      }
      if (maxTopK != null && clampedTopK > maxTopK) {
        clampedTopK = maxTopK;
        clamped = true;
      }
      if (clamped) {
        gemmaLog(
          '[BuiltInAI/web] Clamped sampler params to the browser\'s reported '
          'max (temperature=$clampedTemp, topK=$clampedTopK).',
        );
      }
      return (clampedTemp, clampedTopK);
    } catch (e) {
      // `params()` is best-effort — a browser that fails/omits it just skips
      // the clamp; `create()` itself is the source of truth for validation.
      if (kDebugMode) {
        gemmaLog('[BuiltInAI/web] LanguageModel.params() failed: $e');
      }
      return (temperature, topK);
    }
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
      // The Prompt API web arm is text-only in v1 (image input needs
      // `expectedInputs:[{type:"image"}]` + a GPU) — never advertise vision to
      // the chat layer, or it treats images as sendable and the session
      // silently drops them. A caller that requested it still gets the
      // one-time "images are dropped" warning from `createSession`.
      supportImage: false,
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
    try {
      await _session?.close();
    } finally {
      _session = null;
      onClose();
      fireCloseListeners();
    }
  }
}
