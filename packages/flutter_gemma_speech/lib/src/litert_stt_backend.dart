import 'package:flutter_gemma/core/registry/stt_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show SpeechRecognizer;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show SttModelSpec;
import 'litert/litert_speech_recognizer.dart';
import 'model/stt_model_profile.dart';

/// LiteRT C API STT backend. Sole `.tflite` STT backend — the *model* is
/// selected by [SttModelSpec.sttModelType] (mirrors [InferenceModelSpec.modelType]),
/// not by the backend, so `canHandle` is unconditionally `true`.
///
/// Pure factory; core owns the singleton lifecycle via
/// [SpeechRecognizer.addCloseListener]. Mirrors `LiteRtEmbeddingBackend`.
class LiteRtSttBackend implements SttBackendProvider {
  const LiteRtSttBackend();

  @override
  String get name => 'LiteRT STT';

  @override
  int get priority => 0;

  @override
  bool canHandle(SttModelSpec spec) => true; // sole STT backend

  @override
  Future<SpeechRecognizer> createModel(
    SttModelSpec spec,
    RuntimeConfig config,
  ) async {
    final tokenizerPath = config.tokenizerPath;
    if (tokenizerPath == null) {
      throw StateError(
        'LiteRtSttBackend requires config.tokenizerPath (resolved by core '
        'from the active STT model).',
      );
    }
    // spec.sttModelType (e.g. SttModelType.moonshine) selects the runtime
    // profile — this backend never hardcodes a model.
    return LiteRtSpeechRecognizer.create(
      profile: SttModelProfile.forType(spec.sttModelType),
      modelPath: config.modelPath,
      tokenizerPath: tokenizerPath,
      preferredBackend: config.preferredBackend,
      onClose: () {},
    );
  }
}
