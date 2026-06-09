import 'dart:io';

import 'package:flutter/foundation.dart';

import 'desktop_runtime_extension.dart';
import 'mlx_inference_model.dart';
import 'mlx_native_dispatch.dart';

DesktopRuntimeExtension createBuiltInMlxRuntimeExtension({
  MlxDispatching? dispatcher,
}) {
  return DesktopRuntimeExtension(
    name: 'mlx',
    createInferenceModel: (request) async {
      if (!Platform.isMacOS) {
        return null;
      }
      final modelDirectory = Directory(request.modelPath);
      if (!await modelDirectory.exists()) {
        return null;
      }

      final effectiveDispatcher = dispatcher;
      if (effectiveDispatcher == null && !MlxNativeDispatcher.isAvailable()) {
        debugPrint(
          '[FlutterGemmaDesktop/MLX] Model directory detected but '
          'flm_dispatch_json is not linked into the host process.',
        );
        return null;
      }

      return MlxInferenceModel(
        dispatcher: effectiveDispatcher ?? MlxNativeDispatcher(),
        modelPath: request.modelPath,
        maxTokens: request.maxTokens,
        modelType: request.modelType,
        fileType: request.fileType,
        supportImage: request.supportImage,
        supportAudio: request.supportAudio,
        onClose: () {},
      );
    },
  );
}
