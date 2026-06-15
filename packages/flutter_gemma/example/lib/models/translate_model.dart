import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_gemma/core/model.dart';

import '../translation/prompt_strategy.dart';
import '../translation/translate_gemma_xml_strategy.dart';
import 'base_model.dart';

/// Translator models (TranslateGemma and any future single-shot translators).
///
/// TranslateGemma 4B is a Gemma 3 fine-tune so it runs through the same
/// `InferenceModel.createSession()` path as any chat model — only the prompt
/// format differs (carried by `promptStrategy`). The `.litertlm` files come
/// from a community conversion at
/// `barakplasma/translategemma-4b-it-android-task-quantized` because Google
/// only ships a `-web.task` for browsers; mobile/desktop bundles are not
/// officially available yet (see HF discussion #5 on the source repo).
///
/// CPU-only by design: the community conversion keeps `EMBEDDING_LOOKUP`
/// weights in float32 for MediaPipe `.task` compatibility. The upstream
/// LiteRT GPU partitioner can't cluster that layout, so Metal/WebGPU
/// `engine_create` aborts (LiteRT-LM#1748). Google's stock Gemma 3
/// `.litertlm` bundles use a quantized embedding and do work on GPU.
enum TranslateModel implements TranslateModelInterface {
  /// INT4 quantization, ~2 GB. Recommended default — loads faster and fits
  /// in 6 GB free RAM on modern phones.
  translateGemma4Int4(
    url:
        'https://huggingface.co/barakplasma/translategemma-4b-it-android-task-quantized/resolve/main/artifacts/int4-generic/translategemma-4b-it-int4-generic.litertlm',
    filename: 'translategemma-4b-it-int4-generic.litertlm',
    displayName: 'TranslateGemma 4B (int4)',
    size: '1.87GB',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    maxTokens: 1024,
  ),

  /// Dynamic INT8, ~4 GB. Better translation quality; needs 8 GB free RAM.
  translateGemma4Int8(
    url:
        'https://huggingface.co/barakplasma/translategemma-4b-it-android-task-quantized/resolve/main/artifacts/dynamic_int8-generic/translategemma-4b-it-dynamic_int8-generic.litertlm',
    filename: 'translategemma-4b-it-dynamic_int8-generic.litertlm',
    displayName: 'TranslateGemma 4B (int8)',
    size: '4GB',
    needsAuth: false,
    preferredBackend: PreferredBackend.cpu,
    maxTokens: 1024,
  );

  const TranslateModel({
    required this.url,
    required this.filename,
    required this.displayName,
    required this.size,
    required this.needsAuth,
    required this.preferredBackend,
    required this.maxTokens,
  });

  @override
  final String url;

  @override
  final String filename;

  @override
  final String displayName;

  @override
  final String size;

  @override
  final bool needsAuth;

  @override
  final PreferredBackend preferredBackend;

  @override
  final int maxTokens;

  @override
  String get name => toString().split('.').last;

  @override
  ModelKind get kind => ModelKind.translation;

  @override
  String? get licenseUrl =>
      'https://huggingface.co/barakplasma/translategemma-4b-it-android-task-quantized';

  /// Gemma-3 fine-tune — uses the same Jinja chat template family.
  @override
  ModelType get modelType => ModelType.gemmaIt;

  ModelFileType get fileType => ModelFileType.litertlm;

  @override
  TranslationPromptStrategy get promptStrategy =>
      const TranslateGemmaXmlPromptStrategy();
}
