import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart'
    show HuggingFaceResolver, ResolvedHfModel;

/// [HuggingFaceResolver] for ONNX models.
///
/// It claims the `ModelFileType.onnx` slot in the resolver registry so that
/// `FlutterGemma.resolveHuggingFace(repo, fileType: ModelFileType.onnx)`
/// answers with a clear, ONNX-specific error instead of core's generic
/// "no resolver registered" `StateError` — the "works everywhere" contract
/// [FlutterGemma.resolveHuggingFace] promises.
///
/// [resolve] currently throws [UnimplementedError]: ORT-GenAI models install
/// as a DIRECTORY (`genai_config.json` + `.onnx`[+ `.onnx_data`] + tokenizer),
/// which the single-file network-install path does not cover yet. A
/// `genai_config.json`-driven directory resolver is the follow-up; until then
/// install an ONNX model from a local directory.
///
/// Register it via `FlutterGemma.initialize(huggingFaceResolvers: [...])`,
/// exactly like the engine (`OnnxEngine`) and backend (`OnnxEmbeddingBackend`).
class OnnxHuggingFaceResolver implements HuggingFaceResolver {
  const OnnxHuggingFaceResolver();

  @override
  String get name => 'onnx-huggingface';

  @override
  int get priority => 0;

  @override
  bool canResolve(String repo, {ModelFileType? fileType}) =>
      fileType == ModelFileType.onnx;

  @override
  Future<ResolvedHfModel> resolve(
    String repo, {
    String? token,
    String? platform,
    PreferredBackend? preferredBackend,
  }) {
    throw UnimplementedError(
      'Resolving an ONNX model from a Hugging Face repo is not implemented yet '
      '("$repo"). ORT-GenAI models install as a directory (genai_config.json + '
      '.onnx [+ .onnx_data] + tokenizer); manifest-driven HF resolution is a '
      'follow-up. For now install an ONNX model from a local directory.',
    );
  }
}
