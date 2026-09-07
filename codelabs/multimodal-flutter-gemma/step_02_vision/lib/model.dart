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
  });

  final String label;
  final String url;
  final String fileName;
  final ModelType modelType;
  final String sizeLabel;

  /// Whether these WEIGHTS were trained to look at a picture.
  ///
  /// A property of the checkpoint, not of the device: the answer is the same
  /// on a Pixel, on a Mac and in Chrome. It is only half of "can this app
  /// send an image" — the other half lives in `capabilities.dart`.
  final bool supportsImage;
}

/// The models this codelab offers.
///
/// Both repositories are ungated, so nothing here needs a Hugging Face token
/// and no run needs `--dart-define`.
abstract final class Models {
  /// A vision-language model small enough to feel like a text model. 0.36 GB
  /// is roughly what a photo-heavy app already spends on its image cache, so
  /// this is the version of "multimodal" you can put in a shipping app
  /// without an argument about download size.
  static const smolVlm2 = ModelChoice(
    label: 'SmolVLM2 500M',
    url:
        'https://huggingface.co/litert-community/SmolVLM2-500M/resolve/main/'
        'SmolVLM2-500M.litertlm',
    fileName: 'SmolVLM2-500M.litertlm',
    // `general` and not `gemmaIt`: SmolVLM2 is not a Gemma, and the chat
    // template that ships inside the `.litertlm` is the right one to use.
    modelType: ModelType.general,
    sizeLabel: '0.36 GB',
    supportsImage: true,
  );
}
