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
  });

  final String label;
  final String url;
  final String fileName;
  final ModelType modelType;
  final String sizeLabel;
}

/// The model this step swaps to, and the one `complete` ships.
///
/// The repository is ungated, so nothing here needs a Hugging Face token and
/// no run needs `--dart-define`.
abstract final class Models {
  /// Gemma 4 E2B reads pictures and listens to audio with the same weights.
  ///
  /// Step 2's SmolVLM2 has no audio encoder, and a session flag cannot switch
  /// on something the checkpoint does not carry — so audio costs a second
  /// download, seven times the first at 2.59 GB. You pay it once: both
  /// modalities come out of these weights, so nothing here ever holds two
  /// models open to cover two kinds of input.
  static const gemma4 = ModelChoice(
    label: 'Gemma 4 E2B',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    modelType: ModelType.gemma4,
    sizeLabel: '2.59 GB',
  );
}
