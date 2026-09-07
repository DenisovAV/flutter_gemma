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

/// The model this step runs.
///
/// The repository is ungated, so nothing here needs a Hugging Face token and
/// no run needs `--dart-define`.
abstract final class Models {
  /// A vision-language model small enough to feel like a text model. 0.36 GB
  /// is roughly what a photo-heavy app already spends on its image cache, so
  /// this is the version of "multimodal" you can put in a shipping app
  /// without an argument about download size — about a minute of download,
  /// and then it is looking at your photograph.
  ///
  /// It cannot hear, and that is not a gap in this step: these weights have
  /// no audio encoder, so no session flag can switch one on. It is why Step 3
  /// changes models, and it is the model half of the question `complete` asks
  /// at the end — a half that says no here while the device, happily holding
  /// a microphone, says yes.
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
  );
}
