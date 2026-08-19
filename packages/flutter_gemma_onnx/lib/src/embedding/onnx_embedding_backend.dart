// ONNX Runtime embedding backend (Phase 2 — plain-ORT embedding forward
// pass, hardened plan Task 3). Mirrors `flutter_gemma_litertlm`'s
// `LiteRtEmbeddingBackend` shape: builds a `ForwardPassDescriptor` and hands
// it to the runtime-agnostic `CommonEmbeddingModel`.

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'
    show CommonEmbeddingModel, EmbeddingOutputContract, ForwardPassDescriptor;

import 'onnx_embedding_forward_pass.dart';
import 'onnx_tokenizer_loader.dart';

/// ONNX Runtime embedding backend — plain ORT forward pass (no GenAI, no
/// text generation) over an `.onnx`/`.ort` embedding model directory. Pure
/// factory; core owns the singleton lifecycle via
/// [EmbeddingModel.addCloseListener].
///
/// Priority 10 (above LiteRT's catch-all 0) so an app that registers both
/// backends and installs an `.onnx` model gets this one, not LiteRT's
/// `canHandle: true` catch-all.
class OnnxEmbeddingBackend implements EmbeddingBackendProvider {
  const OnnxEmbeddingBackend();

  /// Unlike [OnnxEngine], [canHandle] here MUST stay extension-based (not
  /// platform-gated): if it went false on an unsupported host,
  /// `LiteRtEmbeddingBackend`'s `canHandle => true` catch-all (priority 0)
  /// would silently claim the `.onnx`/`.ort` file and fail deep inside
  /// LiteRT native load instead of here, with a confusing error. So the
  /// platform gate lives in [createModel] as a loud [StateError] instead —
  /// same `_isSupportedHost` shape as `OnnxEngine`, kept in lockstep with
  /// `hook/build.dart`'s platform table (macOS/Linux/Windows/Android arm64 —
  /// all device-verified; see `OnnxEngine._isSupportedHost`'s doc).
  static bool get _isSupportedHost {
    if (debugForceUnsupportedHost == true) return false;
    final abi = Abi.current();
    // Keep in lockstep with hook/build.dart's `_archivesFor` table — all four
    // arm/x64 hosts device-verified (Android on FTL 2026-08-19).
    return (Platform.isMacOS && abi == Abi.macosArm64) ||
        (Platform.isLinux && abi == Abi.linuxX64) ||
        (Platform.isWindows && abi == Abi.windowsX64) ||
        (Platform.isAndroid && abi == Abi.androidArm64);
  }

  /// Test-only override — see `OnnxEngine.debugForceUnsupportedHost` (same
  /// seam, same rationale). Never read or set outside `test/`. Reset to
  /// `null` in `tearDown`.
  @visibleForTesting
  static bool? debugForceUnsupportedHost;

  @override
  String get name => 'ONNX Embedding';

  @override
  int get priority => 10;

  /// `EmbeddingModelSpec` has no `fileType` field (unlike
  /// `InferenceModelSpec`) — the installed model file's extension is this
  /// backend's identity signal instead. `.onnx` (single-file export) and
  /// `.ort` (ORT-optimized format) both route here. `spec.files.first` is
  /// always the model file (see `EmbeddingModelSpec.files`: `[modelFile,
  /// tokenizerFile]`).
  @override
  bool canHandle(EmbeddingModelSpec spec) {
    final modelFilename = spec.files.first.filename;
    return modelFilename.endsWith('.onnx') || modelFilename.endsWith('.ort');
  }

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) async {
    if (!_isSupportedHost) {
      throw StateError(
        'OnnxEmbeddingBackend.createModel called on unsupported host '
        '${Platform.operatingSystem}/${Abi.current()} — ONNX embedding '
        'native archives are macOS-arm64/linux-x64/windows-x64/android-arm64-'
        'only in v1 (iOS pending).',
      );
    }
    final tokenizerPath = config.tokenizerPath;
    if (tokenizerPath == null) {
      throw StateError(
        'OnnxEmbeddingBackend requires config.tokenizerPath (resolved by '
        'core from the active embedding model).',
      );
    }
    return CommonEmbeddingModel.create(
      descriptor: ForwardPassDescriptor(
        engineTag: 'ONNX',
        modelPath: config.modelPath,
        factory: createOnnxEmbeddingForwardPass,
        tokenizerFactory: loadOnnxEmbeddingTokenizer,
        // Default only — the real value is discovered once the ONNX session
        // opens and its output names are visible, then reported per-request
        // via `OnnxEmbeddingForwardPass.outputContract` (design D-T2). The
        // worker resolves `pass.outputContract ?? descriptor.outputContract`,
        // so this default is never actually used once `load()` completes.
        outputContract: EmbeddingOutputContract.tokenLevel,
      ),
      tokenizerPath: tokenizerPath,
      onClose: () {}, // core resets its state via addCloseListener
    );
  }
}
