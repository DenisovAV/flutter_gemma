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
    required this.supportsImage,
    required this.supportsAudio,
  });

  final String label;
  final String url;
  final String fileName;
  final ModelType modelType;
  final String sizeLabel;

  /// What the WEIGHTS accept. Properties of the checkpoint, not of the
  /// device: the same answer on a Pixel, on a Mac and in Chrome. They are
  /// only half of "can this app send one" — the other half is in
  /// `capabilities.dart`, and on this codelab's single model it is the only
  /// half that ever says no.
  final bool supportsImage;
  final bool supportsAudio;
}

/// The one model this codelab uses, from Step 2 to the end.
///
/// The repository is ungated, so nothing here needs a Hugging Face token and
/// no run needs `--dart-define`.
abstract final class Models {
  /// Gemma 4 E2B reads pictures and listens to audio with the same weights.
  /// You download it once, in Step 2, and Step 3 adds a second modality to
  /// the model that is already on the device.
  static const gemma4 = ModelChoice(
    label: 'Gemma 4 E2B',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
        'resolve/main/gemma-4-E2B-it.litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    modelType: ModelType.gemma4,
    sizeLabel: '2.59 GB',
    supportsImage: true,
    supportsAudio: true,
  );
}
