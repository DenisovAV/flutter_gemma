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
  /// `capabilities.dart`. Both halves really do refuse things, and they refuse
  /// different ones: Step 2's SmolVLM2 answers no to audio on a device holding
  /// a microphone, while this model answers yes to both on a platform that
  /// will carry neither.
  final bool supportsImage;
  final bool supportsAudio;
}

/// The one model this app ships. Two modalities, one checkpoint.
///
/// The repository is ungated, so nothing here needs a Hugging Face token and
/// no run needs `--dart-define`.
abstract final class Models {
  /// Gemma 4 E2B reads pictures and listens to audio with the same weights —
  /// the reason Step 3 paid 2.59 GB for it, and the reason that is the last
  /// download in the codelab. An app that took a model per modality would be
  /// holding two of them open by now; this one holds one.
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
