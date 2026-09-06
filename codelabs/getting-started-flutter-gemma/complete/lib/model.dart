import 'package:flutter_gemma/flutter_gemma.dart';

/// One model this app knows how to install.
///
/// [fileName] doubles as the model's id: `FlutterGemma.isModelInstalled` takes
/// the file name the model was installed under, not a display name.
class ModelChoice {
  const ModelChoice({
    required this.label,
    required this.url,
    required this.fileName,
    required this.modelType,
    required this.sizeLabel,
    required this.requiresToken,
  });

  final String label;
  final String url;
  final String fileName;
  final ModelType modelType;
  final String sizeLabel;

  /// Hugging Face serves this repo behind a licence gate. Accept the licence
  /// once on the model page, then run with `--dart-define=HF_TOKEN=hf_...`.
  final bool requiresToken;
}

/// The models this quickstart offers.
///
/// Both are `.litertlm`, the format the LiteRT-LM engine reads on Android,
/// iOS and desktop. (`.task` files are MediaPipe-only — a different engine
/// package, and no desktop support.)
abstract final class Models {
  /// The plugin's namesake. `ekv4096` in the file name is the KV-cache the
  /// weights were built for, so this model can carry a 4096-token context.
  static const gemma3 = ModelChoice(
    label: 'Gemma 3 1B',
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
        'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    fileName: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    modelType: ModelType.gemmaIt,
    sizeLabel: '0.5 GB',
    requiresToken: true,
  );

  /// No Hugging Face account? This repo is ungated. Same code path — the only
  /// thing that changes is which constant you hand to the app.
  static const qwen3 = ModelChoice(
    label: 'Qwen3 0.6B',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
        'Qwen3-0.6B.litertlm',
    fileName: 'Qwen3-0.6B.litertlm',
    modelType: ModelType.qwen3,
    sizeLabel: '0.6 GB',
    requiresToken: false,
  );
}
