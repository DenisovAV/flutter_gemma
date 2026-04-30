// Web stub for ffi_inference_model.dart
//
// Web build never reaches FFI code paths — the web plugin (FlutterGemmaWeb)
// registers itself as FlutterGemmaPlugin.instance via registerWith(), so the
// mobile/desktop branch in mobile/flutter_gemma_mobile.dart never executes.
// This stub exists purely so the import graph compiles on web (no dart:ffi).

import 'package:flutter/foundation.dart';

import '../../flutter_gemma_interface.dart';
import '../model.dart';
import '../tool.dart';
import 'litert_lm_client_stub.dart';

class FfiInferenceModel extends InferenceModel {
  FfiInferenceModel({
    required LiteRtLmFfiClient ffiClient,
    required int maxTokens,
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.litertlm,
    bool supportImage = false,
    bool supportAudio = false,
    required VoidCallback onClose,
  }) {
    throw UnsupportedError(
        'FfiInferenceModel is not available on web — use FlutterGemmaWeb instead.');
  }

  @override
  ModelFileType get fileType =>
      throw UnsupportedError('web stub — never instantiated');

  @override
  int get maxTokens =>
      throw UnsupportedError('web stub — never instantiated');

  @override
  InferenceModelSession? get session => null;

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
  }) =>
      throw UnsupportedError('web stub — never instantiated');

  @override
  Future<void> close() =>
      throw UnsupportedError('web stub — never instantiated');
}
