import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';

/// One model this app can run — either a file it downloads, or the model the
/// OS already ships.
///
/// The two differ in where the weights come from and nothing else: the same
/// [id] / [modelType] / [fileType] triple drives install, activation and chat.
class ModelChoice {
  const ModelChoice({
    required this.label,
    required this.id,
    required this.modelType,
    required this.fileType,
    this.url,
    this.sizeLabel = '',
    this.requiresToken = false,
  });

  final String label;

  /// What `FlutterGemma.isModelInstalled` is keyed by. For a downloaded model
  /// that is its file name; for a built-in one, the OS model's name.
  final String id;

  /// What the model IS — decides the chat template.
  final ModelType modelType;

  /// Which engine opens it. `.litertlm` → LiteRtLmEngine, `.builtIn` →
  /// BuiltInAiEngine. This field is the whole "engine switch".
  final ModelFileType fileType;

  /// Where the bytes are. `null` for a built-in model — there is no file.
  final String? url;

  final String sizeLabel;

  /// Hugging Face serves this repo behind a licence gate; run with
  /// `--dart-define=HF_TOKEN=hf_...`.
  final bool requiresToken;

  bool get isBuiltIn => fileType == ModelFileType.builtIn;
}

abstract final class Models {
  /// The plugin's namesake, run by the LiteRT-LM engine from a downloaded file.
  static const gemma3 = ModelChoice(
    label: 'Gemma 3 1B',
    id: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
        'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    sizeLabel: '0.5 GB',
    requiresToken: true,
  );

  /// Ungated alternative — no Hugging Face account needed.
  static const qwen3 = ModelChoice(
    label: 'Qwen3 0.6B',
    id: 'Qwen3-0.6B.litertlm',
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
        'Qwen3-0.6B.litertlm',
    sizeLabel: '0.6 GB',
  );

  /// The model the OS ships: Gemini Nano on Android, Apple Foundation Models
  /// on iOS. Nothing to download — the OS owns the weights, so [url] is null
  /// and [sizeLabel] says so.
  ///
  /// A getter, not a const: the ready-made specs are chosen per platform.
  static ModelChoice get builtIn {
    final spec = defaultTargetPlatform == TargetPlatform.android
        ? BuiltInAiModels.geminiNano
        : BuiltInAiModels.appleFoundationModels;
    return ModelChoice(
      label: defaultTargetPlatform == TargetPlatform.android
          ? 'Gemini Nano'
          : 'Apple Foundation Models',
      id: spec.name,
      modelType: spec.modelType,
      fileType: ModelFileType.builtIn,
      sizeLabel: 'already on the device',
    );
  }
}
