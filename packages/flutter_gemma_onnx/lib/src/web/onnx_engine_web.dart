// Web arm of `OnnxEngine` (ONNX web PR, `feat/onnx-web`). Text generation on
// web routes through Transformers.js (`@huggingface/transformers`), NOT
// ORT-GenAI — a different model-provisioning story entirely (an HF-repo-id
// model, downloaded and cached by transformers.js itself, versus the native
// arm's ORT-GenAI model DIRECTORY). That work is scoped as its own
// fast-follow PR (design doc §B Task 3) with its own model-identity design,
// example catalog entry, and browser device gate.
//
// This stub exists so `OnnxEngine` has the SAME public shape on web as on
// native (HARD RULE 2) — an app's `gemma_bootstrap.dart`-style registration
// list never needs an `if (kIsWeb)` branch to use it — while declining every
// spec until the fast-follow lands. [canHandle] always returns false with a
// loud [gemmaLog] pointing at the gap, so a web app that registers this
// engine gets a clear "not yet" instead of a silent no-op or a confusing
// downstream native-only error.
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show InferenceModelSpec;
import 'package:flutter_gemma/core/registry/inference_engine_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart' show gemmaLog;
import 'package:flutter_gemma/flutter_gemma_interface.dart' show InferenceModel;

/// ONNX Runtime GenAI on-device inference engine — web arm.
///
/// **Not yet implemented.** Text generation on web needs Transformers.js
/// (`@huggingface/transformers`), a different model-provisioning story than
/// the native ORT-GenAI arm (see this file's module doc). [canHandle] always
/// declines; use [OnnxEmbeddingBackend] for the web embeddings arm, which
/// IS implemented (onnxruntime-web).
class OnnxEngine implements InferenceEngineProvider {
  const OnnxEngine();

  @override
  String get name => 'ONNX';

  @override
  int get priority => 0;

  @override
  bool canHandle(InferenceModelSpec spec) {
    if (spec.fileType != ModelFileType.onnx) return false;
    gemmaLog(
      'OnnxEngine (web) declined: text generation via Transformers.js is '
      'not yet implemented on web — only OnnxEmbeddingBackend (embeddings, '
      'onnxruntime-web) is available in this release. See the ONNX web PR '
      'design doc §B Task 3 for the planned fast-follow.',
    );
    return false;
  }

  @override
  Future<InferenceModel> createModel(
    InferenceModelSpec spec,
    RuntimeConfig config,
  ) async {
    throw UnsupportedError(
      'OnnxEngine.createModel is not yet implemented on web (text '
      'generation needs Transformers.js — a fast-follow PR, see this file\'s '
      'module doc). canHandle() should have already declined this spec; '
      'this is reachable only via a direct createModel() call that bypasses '
      'the registry.',
    );
  }
}
