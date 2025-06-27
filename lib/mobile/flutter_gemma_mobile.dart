import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:large_file_handler/large_file_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flutter_gemma.dart';

part 'flutter_gemma_mobile_model_manager.dart';
part 'flutter_gemma_mobile_inference_model.dart';

@visibleForTesting
const eventChannel = EventChannel('flutter_gemma_stream');

final _platformService = PlatformService();

class FlutterGemma extends FlutterGemmaPlugin {
  Completer<InferenceModel>? _initCompleter;
  InferenceModel? _initializedModel;

  @override
  late final MobileModelManager modelManager = MobileModelManager(
    onDeleteModel: _closeModelBeforeDeletion,
    onDeleteLora: _closeModelBeforeDeletion,
  );

  @override
  InferenceModel? get initializedModel => _initializedModel;

  @override
  Future<InferenceModel> createModel({
    required ModelType modelType,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages,
    bool supportImage = false,
  }) async {
    if (_initCompleter case Completer<InferenceModel> completer) {
      return completer.future;
    }

    final completer = _initCompleter = Completer<InferenceModel>();

    final (isModelInstalled, isLoraInstalled, File? modelFile, File? loraFile) =
        await (
      modelManager.isModelInstalled,
      modelManager.isLoraInstalled,
      modelManager._modelFile,
      modelManager._loraFile,
    ).wait;

    if (!isModelInstalled || modelFile == null) {
      completer.completeError(
        Exception(
            'Gemma Model is not installed yet. Use the `modelManager` to load the model first'),
      );
      return completer.future;
    }

    try {
      await _platformService.createModel(
        maxTokens: maxTokens,
        modelPath: modelFile.path,
        loraRanks: loraRanks ?? supportedLoraRanks,
        preferredBackend: preferredBackend,
        maxNumImages: supportImage ? (maxNumImages ?? 1) : null,
      );

      final model = _initializedModel = MobileInferenceModel(
        maxTokens: maxTokens,
        modelType: modelType,
        modelManager: modelManager,
        preferredBackend: preferredBackend,
        supportedLoraRanks: loraRanks ?? supportedLoraRanks,
        supportImage: supportImage,
        maxNumImages: maxNumImages,
        onClose: () {
          _initializedModel = null;
          _initCompleter = null;
        },
      );

      completer.complete(model);
      return model;
    } catch (e, st) {
      completer.completeError(e, st);
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> _closeModelBeforeDeletion() {
    return _initializedModel?.close() ?? Future.value();
  }
}
